# Changelog

All notable changes to this project will be documented in this file.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).
Versioning follows [SemVer](https://semver.org/).

## [1.0.0] — 2026-05-18

### Added
- Ubuntu 22.04 LTS base AMI with CIS L1+L2 hardening (114 controls)
- Python 3.11, 3.12, 3.13 environments via Nix (Base and Pro editions)
- PyTorch CPU, TensorFlow, Transformers, XGBoost, LightGBM, MLflow (Pro)
- Apache Spark 3.5.x with Java 21, PySpark wrappers (py311/py312/py313)
- Julia, R, Go, Rust/Cargo toolchains
- AWS CLI v2 with PGP signature verification
- SSM Agent for no-open-SSH access
- On-demand CVE + CIS scanner (`sudo ami-scan`)
- CycloneDX 1.4 SBOM at `/usr/share/BUILD_INFO/sbom.cyclonedx.json`
- ARM64/Graviton3 builds mirroring all x86_64 controls and packages
- STIG-aligned hardening additions (SSH HostKeyAlgorithms, GRUB password,
  sudo timestamp_timeout, TMOUT, ctrl-alt-del masked, TLS 1.2 minimum)
- CI pipeline: ShellCheck, CIS static check, Trivy, Packer validate, Checkov
- OpenSSF Scorecard and Best Practices badge

### Security
- CVE-2026-31431 (Copy Fail — algif_aead local privilege escalation) mitigated
  via kernel module blacklist in `/etc/modprobe.d/cis-blacklist.conf`
