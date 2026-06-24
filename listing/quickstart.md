Quick Start — CPU DS/ML AMI

Launch
- Recommended instance: c6i.xlarge (4 vCPU / 8 GB) for dev; c6i.4xlarge+ for training/Spark
- Security Group: allow SSH (22) from your IP only; open additional ports only as required
- EBS: root volume encrypted by default; minimum 24 GB (gp3)

First login checks
  py311 -V && py312 -V && py313 -V
  julia -e 'println(VERSION)' && R --version && go version && rustc --version
  java -version && spark-submit --version
  nix --version && nix flake show /opt/nix/flake

Base env — quick test
  py311 -c 'import numpy, pandas, pyspark, sklearn; print("base ok")'
  py312 -c 'import numpy, pandas, pyspark, sklearn; print("base ok")'

Pro env — quick test (pro AMI only)
  py311 -c 'import torch, tensorflow, transformers; print(torch.__version__, tensorflow.__version__)'
  py312 -c 'import torch, tensorflow, transformers; print(torch.__version__, tensorflow.__version__)'

PySpark
  # Default (Python 3.11):
  pyspark

  # Specific version:
  PYSPARK_PYTHON=/opt/nix/envs/base-py312/bin/python pyspark
  PYSPARK_PYTHON=/opt/nix/envs/base-py313/bin/python pyspark

  # Aliases (base AMI):
  pyspark311   pyspark312   pyspark313

On-demand security scan
  sudo ami-scan            # CVE (Trivy) + CIS (OpenSCAP), ~5-8 min
  sudo ami-scan --cve      # CVE only, ~2-3 min
  sudo ami-scan --cis      # CIS only (default profile), ~3-5 min
  sudo ami-scan --cis-level1  # CIS Ubuntu 22.04 Level 1 profile
  sudo ami-scan --cis-level2  # CIS Ubuntu 22.04 Level 2 profile

Build info
  cat /usr/share/BUILD_INFO         # version
  cat /usr/share/BUILD_INFO/packages.txt        # all packages
  cat /usr/share/BUILD_INFO/sbom.cyclonedx.json # CycloneDX SBOM
  cat /usr/share/BUILD_INFO/EULA.txt            # license terms

Security posture
  SSH hardened: no passwords, no root, chacha20/aes-gcm only
  nftables enabled; SSH protected with fail2ban
  CIS-aligned hardening controls applied; validate current results with ami-scan
  IMDSv2 required — prevents SSRF metadata theft
  EBS encrypted at rest (KMS)
