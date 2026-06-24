#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Bharath Kumar Gajjela
# tune-pro.sh — ML workload optimizations layered on top of base tuning.
#
# Runs as the final step of the pro AMI build (after pip installs).
# Targets CPU-only DS/ML workloads: PyTorch, TensorFlow, PySpark, large datasets.
#
# Three areas:
#   1. Kernel sysctl  — aggressive memory + network settings for ML
#   2. Transparent Huge Pages — madvise mode for large tensor allocations
#   3. Systemd limits — higher resource ceilings for ML processes
set -euo pipefail

echo "=== Applying pro ML performance tuning ==="

# ── 1. Kernel sysctl ──────────────────────────────────────────────────────────
sudo tee /etc/sysctl.d/60-pro-ml-perf.conf >/dev/null <<'EOF'
# ── Memory ────────────────────────────────────────────────────────────────────
# Near-zero swapping: PyTorch and TF tensors must stay in RAM.
# Swapping a 4 GB model to EBS effectively kills training throughput.
vm.swappiness = 1

# Retain inode and dentry caches longer.
# Dataset loaders (PyTorch DataLoader, tf.data) repeatedly stat() the same
# files; lower vfs_cache_pressure keeps those entries in memory.
vm.vfs_cache_pressure = 50

# Allow the kernel to use huge pages speculatively for anonymous mappings.
# PyTorch allocates large contiguous tensors; THP reduces TLB pressure.
# Set via /sys at boot — see the systemd service below, not sysctl.

# ── Network ───────────────────────────────────────────────────────────────────
# Saturate ENA at up to 25 Gbps for S3 training data ingestion.
# x86 (c6i.xlarge / c6i.4xlarge): 12.5–25 Gbps ENA.
# ARM (c7g.xlarge / c7g.4xlarge): 12.5–25 Gbps ENA. Same settings apply.
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
net.core.rmem_default = 1048576
net.core.wmem_default = 1048576
net.ipv4.tcp_rmem = 4096 1048576 134217728
net.ipv4.tcp_wmem = 4096 1048576 134217728

# BBR congestion control + fq qdisc: better throughput and lower RTT variance
# on the long-haul paths to S3 and package mirrors vs. cubic.
# Requires kernel >= 4.9 (Ubuntu 22.04 ships 5.15 — safe).
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

# Keep more outbound connections in the socket backlog for parallel S3 GETs
# (boto3 multipart, s5cmd, PyTorch IterableDataset with multiple workers).
net.core.somaxconn = 65535
net.core.netdev_max_backlog = 16384

# ── Filesystem ────────────────────────────────────────────────────────────────
# Deep dataset trees (ImageNet, Common Crawl) can have millions of files.
# PyTorch DataLoader workers each open their own inotify fd.
fs.inotify.max_user_watches = 524288
fs.inotify.max_user_instances = 2048
fs.inotify.max_queued_events = 32768

# fs.file-max intentionally omitted: harden.sh writes 99-ulimits.conf with
# fs.file-max = 2097152. sysctl.d applies files lexicographically — 99-ulimits
# runs after 60-pro-ml-perf and silently overwrites any value set here.
# 2097152 (2M) is already sufficient for any real workload.
EOF

# BBR requires the tcp_bbr kernel module. On Ubuntu 22.04 (kernel 5.15) it
# ships as a loadable module, not built-in. Load it before applying sysctl so
# the congestion control setting does not silently fall back to cubic.
sudo modprobe tcp_bbr 2>/dev/null || true

sudo sysctl --system >/dev/null 2>&1 || true
echo "  sysctl applied"

# ── 2. Transparent Huge Pages ─────────────────────────────────────────────────
# madvise: THP only for regions that explicitly request it via madvise(MADV_HUGEPAGE).
# PyTorch and TF use madvise for large tensor buffers — they get THP acceleration
# while small allocations (Python objects, metadata) avoid THP fragmentation overhead.
# "always" causes latency spikes from background compaction; "never" loses the benefit.
sudo tee /etc/systemd/system/thp-madvise.service >/dev/null <<'EOF'
[Unit]
Description=Set Transparent Huge Pages to madvise for ML tensor workloads
DefaultDependencies=no
After=sysinit.target local-fs.target
Before=basic.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/sh -c 'echo madvise > /sys/kernel/mm/transparent_hugepage/enabled'
ExecStart=/bin/sh -c 'echo defer+madvise > /sys/kernel/mm/transparent_hugepage/defrag'

[Install]
WantedBy=multi-user.target
EOF
sudo systemctl enable thp-madvise.service
echo "  THP madvise service enabled"

# ── 3. Systemd and PAM resource limits ───────────────────────────────────────
# ML processes (training jobs, Spark executors) need more open files,
# more threads (DataLoader workers × epochs), and more locked memory
# (mlock for pinned CUDA buffers — kept here for compatibility if GPU added later).
sudo tee /etc/security/limits.d/98-ml-pro.conf >/dev/null <<'EOF'
# Raised limits for ML workloads on pro AMI
# nofile: Spark executors + multi-worker DataLoaders open many fds simultaneously
ubuntu  soft  nofile    1048576
ubuntu  hard  nofile    1048576
root    soft  nofile    1048576
root    hard  nofile    1048576

# nproc: PyTorch DataLoader spawns one process per worker × num_replicas
ubuntu  soft  nproc     65536
ubuntu  hard  nproc     65536

# memlock: allows mlock() for pinned memory (large embedding tables, future GPU)
ubuntu  soft  memlock   unlimited
ubuntu  hard  memlock   unlimited
EOF

# Mirror in systemd so services (Jupyter, MLflow server) inherit the same limits
sudo mkdir -p /etc/systemd/system.conf.d
sudo tee /etc/systemd/system.conf.d/98-ml-pro.conf >/dev/null <<'EOF'
[Manager]
DefaultLimitNOFILE=1048576:1048576
DefaultLimitNPROC=65536:65536
DefaultLimitMEMLOCK=infinity:infinity
EOF

sudo systemctl daemon-reload
echo "  resource limits applied"

# ── 4. NVMe / EBS I/O scheduler ──────────────────────────────────────────────
# EC2 Nitro NVMe devices use the 'none' scheduler by default (correct for SSDs).
# Verify and enforce it via udev rule so it survives kernel upgrades.
sudo tee /etc/udev/rules.d/60-nvme-scheduler.rules >/dev/null <<'EOF'
# Keep NVMe disks on 'none' (no-op) scheduler — Nitro NVMe has its own
# internal queue; adding a software scheduler only adds latency.
ACTION=="add|change", KERNEL=="nvme[0-9]*", ATTR{queue/scheduler}="none"
EOF
echo "  NVMe scheduler rule written"

# ── 5. ML threading profile ───────────────────────────────────────────────────
# Default OpenBLAS / OpenMP thread counts to the number of physical CPUs.
# PyTorch and TF override these at runtime, but having a sane default prevents
# accidental thread storms when running NumPy-heavy code outside a framework.
sudo tee /etc/profile.d/ml-threading.sh >/dev/null <<'EOF'
# shellcheck shell=bash
# ML threading defaults — frameworks (PyTorch, TF) override at runtime.
# Explicit here so bare NumPy/SciPy scripts don't spawn 128 threads on large instances.
NCPU="$(nproc 2>/dev/null || echo 4)"
export OMP_NUM_THREADS="${NCPU}"
export OPENBLAS_NUM_THREADS="${NCPU}"
export MKL_NUM_THREADS="${NCPU}"
export NUMEXPR_MAX_THREADS="${NCPU}"
# PyTorch inter/intra-op threads — set at import time; this is documentation only.
# In training scripts: torch.set_num_threads(N); torch.set_num_interop_threads(1)
EOF
sudo chmod 644 /etc/profile.d/ml-threading.sh
echo "  ML threading profile written"

echo ""
echo "Pro ML tuning complete."
echo "  sysctl:   /etc/sysctl.d/60-pro-ml-perf.conf"
echo "  THP:      thp-madvise.service (madvise on boot)"
echo "  limits:   /etc/security/limits.d/98-ml-pro.conf"
echo "  NVMe:     /etc/udev/rules.d/60-nvme-scheduler.rules"
echo "  threads:  /etc/profile.d/ml-threading.sh"
