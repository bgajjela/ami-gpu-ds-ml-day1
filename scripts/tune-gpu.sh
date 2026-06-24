#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Bharath Kumar Gajjela
# tune-gpu.sh — GPU performance tuning, layered on top of tune-pro.sh.
#
# Runs on the GPU pro build AFTER build-gpu-envs.sh and tune-pro.sh. tune-pro.sh
# already applied the CPU/memory/network/THP/NVMe tuning (still relevant for data
# loading). This adds the GPU-specific pieces:
#   1. nvidia-persistenced  — keep the driver initialized between processes
#   2. Persistence-mode boot service — fallback if persistenced is unavailable
#   3. CUDA/framework runtime env — allocator + lazy module loading defaults
set -euo pipefail

echo "=== Applying GPU performance tuning ==="

# ── 1. nvidia-persistenced ────────────────────────────────────────────────────
# Without persistence, the driver tears down GPU state when no process holds the
# device, so the NEXT CUDA process pays a multi-second re-init. persistenced keeps
# the driver resident. It ships with the cuda-drivers package.
if systemctl list-unit-files | grep -q '^nvidia-persistenced'; then
  sudo systemctl enable nvidia-persistenced 2>/dev/null || true
  echo "  nvidia-persistenced enabled"
else
  echo "  nvidia-persistenced unit not found — relying on persistence-mode service below"
fi

# ── 2. Persistence-mode boot service (fallback / belt-and-suspenders) ──────────
# Sets persistence mode via nvidia-smi on every boot. Same oneshot pattern as
# thp-madvise.service in tune-pro.sh. Guarded so it no-ops if no GPU is present
# (e.g. if the AMI is ever launched on a non-GPU instance for inspection).
sudo tee /etc/systemd/system/nvidia-persistence-mode.service >/dev/null <<'EOF'
[Unit]
Description=Enable NVIDIA GPU persistence mode for ML workloads
After=multi-user.target
ConditionPathExists=/usr/bin/nvidia-smi

[Service]
Type=oneshot
RemainAfterExit=yes
# '|| true' so a missing/absent GPU does not fail the boot target.
ExecStart=/bin/sh -c '/usr/bin/nvidia-smi -pm 1 || true'

[Install]
WantedBy=multi-user.target
EOF
sudo systemctl enable nvidia-persistence-mode.service 2>/dev/null || true
echo "  nvidia-persistence-mode.service enabled"

# ── 3. CUDA / framework runtime defaults ──────────────────────────────────────
# profile.d drop-in (survives harden.sh's /etc/environment overwrite), sitting
# next to ml-threading.sh from tune-pro.sh.
sudo tee /etc/profile.d/gpu-ml.sh >/dev/null <<'EOF'
# shellcheck shell=sh
# GPU/ML runtime defaults. Frameworks can override these per-process.

# PyTorch CUDA caching allocator: expandable_segments reduces fragmentation and
# out-of-memory failures on long training runs with varying batch shapes.
export PYTORCH_CUDA_ALLOC_CONF="expandable_segments:True"

# Lazy CUDA module loading: only load kernels actually used, cutting process
# startup time and GPU memory footprint (CUDA 11.7+; default-on in 12.x but set
# explicitly so behaviour is stable across driver updates).
export CUDA_MODULE_LOADING="LAZY"

# Stable, predictable device enumeration across reboots and instance types.
export CUDA_DEVICE_ORDER="PCI_BUS_ID"

# TensorFlow: grow GPU memory on demand instead of grabbing all of it at startup,
# so multiple processes / notebooks can share the GPU. (No effect on the
# aarch64 CPU-only TensorFlow build.)
export TF_FORCE_GPU_ALLOW_GROWTH="true"
# Quieten TF's startup banner; keep warnings.
export TF_CPP_MIN_LOG_LEVEL="1"
EOF
sudo chmod 0644 /etc/profile.d/gpu-ml.sh
echo "  GPU runtime env written: /etc/profile.d/gpu-ml.sh"

sudo systemctl daemon-reload || true

echo ""
echo "GPU tuning complete."
echo "  persistence: nvidia-persistenced + nvidia-persistence-mode.service"
echo "  runtime env: /etc/profile.d/gpu-ml.sh"
