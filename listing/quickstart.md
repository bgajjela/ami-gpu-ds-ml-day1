Quick Start — GPU DS/ML AMI

Launch
- x86_64: g4dn.xlarge (NVIDIA T4, 4 vCPU / 16 GB) for dev; g5.2xlarge / g6 / p-family for heavier training
- ARM64/Graviton: g5g.xlarge (NVIDIA T4G, 4 vCPU / 8 GB)
- Security Group: allow SSH (22) from your IP only; open additional ports only as required
- EBS: minimum 80 GB (gp3) — CUDA toolkit, cuDNN, and CUDA wheels are large

First login checks
  nvidia-smi                      # driver + GPU visible
  nvcc --version                  # CUDA 12.8 toolkit
  py311 -V && py312 -V && py313 -V
  julia -e 'println(VERSION)' && R --version && go version && rustc --version
  java -version && spark-submit --version
  nix --version && nix flake show /opt/nix/flake

Base env — quick test
  py311 -c 'import numpy, pandas, pyspark, sklearn; print("base ok")'

GPU PyTorch — quick test (both architectures)
  py311 -c 'import torch; print(torch.__version__, torch.cuda.is_available(), torch.cuda.get_device_name(0))'

Pro env — quick test (pro AMI only)
  # x86: TensorFlow is GPU-enabled; ARM64: TensorFlow is CPU-only
  py311 -c 'import torch, tensorflow as tf, transformers; print(torch.cuda.is_available(), tf.config.list_physical_devices("GPU"))'

PySpark
  pyspark                                   # default (Python 3.11)
  PYSPARK_PYTHON=/opt/nix/envs/pro-py312/bin/python pyspark
  pyspark311   pyspark312   pyspark313      # version-pinned wrappers

On-demand security scan
  sudo ami-scan            # CVE (Trivy) + CIS (OpenSCAP)
  sudo ami-scan --cve      # CVE only
  sudo ami-scan --cis-level2  # CIS Ubuntu 22.04 Level 2 profile

Build info
  cat /usr/share/BUILD_INFO/version             # e.g. 1.0.0-GPU-PRO
  cat /usr/share/BUILD_INFO/packages.txt        # all packages
  cat /usr/share/BUILD_INFO/sbom.cyclonedx.json # CycloneDX SBOM
  cat /usr/share/BUILD_INFO/EULA.txt            # license terms

Security posture
  GPU stack installed before CIS hardening; nouveau disabled, driver pinned
  SSH hardened: no passwords, no root, chacha20/aes-gcm only
  UFW (nftables) default-deny; SSH protected with fail2ban
  CIS-aligned hardening controls applied; validate current results with ami-scan
  IMDSv2 required — prevents SSRF metadata theft

Notes
  Driver/CUDA are apt-mark hold-ed — do not apt-upgrade cuda-drivers-570 / cuda-toolkit-12-8
  TensorFlow GPU is x86-only; on Graviton use PyTorch for GPU work
