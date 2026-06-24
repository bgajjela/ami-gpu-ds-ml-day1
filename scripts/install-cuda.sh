#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Bharath Kumar Gajjela
# install-cuda.sh — installs the pinned NVIDIA driver + CUDA toolkit on the GPU
# base AMI. Arch-aware: x86_64 uses the CUDA "x86_64" repo, aarch64 uses "sbsa".
#
# ORDER (critical): this runs on the GPU base build AFTER the kernel-upgrade
# reboot (so DKMS builds against the final kernel) and BEFORE harden.sh (so CIS
# module/sysctl lockdown does not interfere with driver module loading). The
# Packer build reboots once MORE right after this script so the nouveau
# blacklist + initramfs change take effect and the nvidia module loads cleanly.
#
# Version chain (driver <-> CUDA <-> torch) comes entirely from gpu/versions.env.
# To upgrade CUDA, edit that file — not this script.
set -euo pipefail

# ── Load the pinned version chain ─────────────────────────────────────────────
# versions.env is uploaded next to this script by the Packer file provisioner.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${HERE}/versions.env" ]]; then
  # shellcheck source=/dev/null
  source "${HERE}/versions.env"
elif [[ -f /opt/gpu/versions.env ]]; then
  # shellcheck source=/dev/null
  source /opt/gpu/versions.env
else
  echo "ERROR: gpu/versions.env not found (looked in ${HERE} and /opt/gpu)" >&2
  exit 1
fi

ARCH="$(uname -m)"   # x86_64 or aarch64
case "${ARCH}" in
  x86_64)  REPO_ARCH="x86_64" ;;
  aarch64) REPO_ARCH="sbsa"   ;;   # NVIDIA publishes ARM server CUDA under "sbsa"
  *) echo "ERROR: unsupported arch ${ARCH}" >&2; exit 1 ;;
esac

echo "=== install-cuda: arch=${ARCH} repo_arch=${REPO_ARCH} ==="
echo "    driver=${NVIDIA_DRIVER_PKG}  toolkit=${CUDA_TOOLKIT_PKG}  cuda=${CUDA_DOTTED}"

# ── Build prerequisites for DKMS module compilation ───────────────────────────
# linux-headers must match the running kernel so the nvidia kmod builds against it.
sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
  build-essential dkms "linux-headers-$(uname -r)" \
  ca-certificates curl gnupg

# ── Add the NVIDIA CUDA apt repository (pinned keyring) ────────────────────────
KEYRING_DEB="/tmp/cuda-keyring.deb"
KEYRING_URL="https://developer.download.nvidia.com/compute/cuda/repos/${NVIDIA_REPO_DISTRO}/${REPO_ARCH}/cuda-keyring_1.1-1_all.deb"
echo "  fetching CUDA keyring: ${KEYRING_URL}"
curl -fsSL -o "${KEYRING_DEB}" "${KEYRING_URL}"
sudo dpkg -i "${KEYRING_DEB}"
rm -f "${KEYRING_DEB}"
sudo apt-get update

# ── Blacklist nouveau (open-source driver) BEFORE installing the real one ─────
# nouveau grabs the GPU first; the proprietary module cannot load while it is
# resident. Blacklisting + initramfs rebuild + the reboot that follows this
# script ensures nouveau never loads and nvidia takes the device.
sudo tee /etc/modprobe.d/blacklist-nouveau.conf >/dev/null <<'EOF'
# Disable the open-source nouveau driver so the proprietary NVIDIA driver can
# bind the GPU. Required on stock Ubuntu cloud images for g4dn / g5g instances.
blacklist nouveau
options nouveau modeset=0
EOF

# ── Install driver + CUDA toolkit (pinned) ────────────────────────────────────
# cuda-drivers-<branch>: the kernel driver + libcuda (what nvidia-smi needs).
# cuda-toolkit-<series>: nvcc + headers + static/dev libs (customer dev tooling).
# cuDNN is NOT installed here — the PyTorch cu* wheels bundle cuDNN/cuBLAS as pip
# dependencies in build-gpu-envs.sh, which keeps the runtime self-consistent.
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
  "${NVIDIA_DRIVER_PKG}" \
  "${CUDA_TOOLKIT_PKG}"

# ── Pin the driver + toolkit so unattended-upgrades cannot bump them ──────────
# harden.sh runs `apt-get upgrade` and enables unattended-upgrades. An automatic
# driver bump would break the driver<->CUDA<->torch chain, so freeze them.
sudo apt-mark hold "${NVIDIA_DRIVER_PKG}" "${CUDA_TOOLKIT_PKG}" || true

# ── Load nvidia modules at every boot ─────────────────────────────────────────
# Belt-and-suspenders: even though the driver ships udev rules, declaring the
# modules here guarantees they load on every instance launched from this AMI,
# before any workload calls into CUDA.
sudo tee /etc/modules-load.d/nvidia.conf >/dev/null <<'EOF'
nvidia
nvidia_uvm
nvidia_modeset
nvidia_drm
EOF

# ── CUDA on PATH/LD_LIBRARY_PATH via profile.d ────────────────────────────────
# NOT /etc/environment: harden.sh overwrites that file wholesale (JAVA/SPARK
# only). profile.d drop-ins survive hardening. /usr/local/cuda is a symlink the
# toolkit package maintains to the active CUDA version.
sudo tee /etc/profile.d/cuda.sh >/dev/null <<'EOF'
# shellcheck shell=sh
# CUDA toolkit on PATH for nvcc and CUDA dev tooling.
if [ -d /usr/local/cuda/bin ]; then
  case ":${PATH}:" in
    *:/usr/local/cuda/bin:*) ;;
    *) PATH="/usr/local/cuda/bin:${PATH}" ;;
  esac
  export PATH
fi
if [ -d /usr/local/cuda/lib64 ]; then
  LD_LIBRARY_PATH="/usr/local/cuda/lib64${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
  export LD_LIBRARY_PATH
fi
EOF
sudo chmod 0644 /etc/profile.d/cuda.sh

# ── Rebuild initramfs so the nouveau blacklist is applied on next boot ─────────
sudo update-initramfs -u

echo ""
echo "install-cuda complete. A reboot is required next so nouveau unloads and the"
echo "nvidia module binds the GPU. Verification (nvidia-smi / nvcc) runs after that"
echo "reboot in the Packer build."
