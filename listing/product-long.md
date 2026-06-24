Why This AMI
- Ready-to-use NVIDIA GPU data science/ML environment with reproducible Nix builds.
- NVIDIA driver + CUDA 12.8 with GPU-enabled PyTorch and TensorFlow (x86) — no driver wrangling.
- Security-focused: CIS-aligned Ubuntu 22.04 hardening controls, AppArmor, auditd, AIDE support, and on-instance scan tooling.
- Faster onboarding: Python 3.11/3.12/3.13, Julia, R, Go, Rust, Node.js, Java 21 (LTS), Apache Spark.
- Governed by the AWS Standard Contract for AWS Marketplace (paid, hourly software fee).

What's Included
- Ubuntu 22.04 LTS (HVM, EBS gp3)
- NVIDIA driver (570 branch) + CUDA 12.8 toolkit (`nvcc`, `nvidia-smi`), nouveau disabled, driver pinned
- Nix-managed environments under `/opt/nix` with symlinks in `/usr/local/bin`
- Python envs (base): numpy, pandas, scikit-learn, pyarrow, polars, matplotlib, seaborn,
  onnxruntime, OpenCV, PySpark — across Python 3.11, 3.12, and 3.13
- Python envs (pro): all base packages plus **CUDA PyTorch** (cu128), TensorFlow (GPU on x86 / CPU on ARM64),
  Transformers, Datasets, XGBoost, LightGBM, MLflow — across all three Python versions
- Toolchains: Julia, R, Go, Rust/Cargo, Node.js, Java 21 (OpenJDK/Temurin), Apache Spark
- On-demand scanner: `sudo ami-scan` runs Trivy CVE scan + OpenSCAP CIS audit
- Curated and smoke-tested package set intended for common GPU DS/ML workflows; customers remain responsible for validating package compatibility, runtime behavior, and performance for their own use cases before production use

Architectures
- x86_64 — runs on g4dn (NVIDIA T4) and other CUDA-capable instances; AMI: `gpu-ds-ml-ubuntu-2204-{base|pro}-<ts>`
- ARM64/Graviton — runs on g5g (NVIDIA T4G); AMI: `gpu-ds-ml-ubuntu-2204-arm64-{base|pro}-<ts>`
- PyTorch is GPU-enabled on both architectures (cu128 wheels). TensorFlow is GPU-enabled on x86; CPU-only on ARM64 (no official aarch64 TensorFlow GPU wheel)

Security & Compliance
- GPU stack installed before hardening so CIS module/sysctl lockdown does not interfere with driver loading
- CIS-aligned Ubuntu 22.04 hardening controls with on-demand OpenSCAP and Trivy scan support
- SSH: key-only, root login disabled, strong crypto (chacha20/aes-gcm), login banner
- Network controls: UFW (nftables backend) default-deny; SSH access restricted and rate-limited via fail2ban
- Filesystem: /tmp and /var/tmp as tmpfs (nosuid, nodev, noexec); /dev/shm hardened
- Auditing: auditd (640 MB capped, rotated); AppArmor enabled; AIDE included
- Log management: journald compressed (500 MB cap, 2-week retention); logrotate weekly + 100 MB maxsize
- IMDSv2 enforced (prevents SSRF credential theft)
- Export compliance: ECCN 5D002.c.1, License Exception ENC

Operations
- GPU check: `nvidia-smi`, `nvcc --version`; PyTorch GPU: `py311 -c "import torch; print(torch.cuda.is_available())"`
- Driver/CUDA are version-pinned (`apt-mark hold`) so unattended upgrades cannot break the driver↔CUDA↔PyTorch chain
- Rebuild envs via `nix build` from `/opt/nix/flake`; lock revisions with `nix flake lock`
- PySpark: set `PYSPARK_PYTHON` to target interpreter; shuffle stored on EBS (`/opt/spark-local`)
- On-demand CVE + CIS scan: `sudo ami-scan` (results in `/var/log/ami-scan/`)
- GPU tuning: persistence mode, PyTorch expandable-segments allocator, lazy CUDA module loading, TF GPU allow-growth
- Pro also includes THP madvise, BBR TCP, 128 MB socket buffers, 1M fd limit — tuned for PyTorch/TF/Spark + GPU data loading

Support
- Usage: `USAGE.md` on-instance and in the repository
- Security details: `SECURITY_REPORT.md`
- Security is a shared responsibility: this AMI provides build-time hardening and scan support, and customers remain responsible for validating suitability and securely operating deployed instances
- If a packaged component fails in a clean, unmodified AMI and the issue is reproducible using the documented runtime paths or curated smoke-tested stack, the maintainer may provide best-effort guidance or address the issue in a future AMI update
- Support does not include guaranteeing compatibility with every upstream package, framework version, model, GPU instance type, or third-party dependency combination unless explicitly stated in the listing terms
- Support does not extend to customer-installed packages, modified environments, arbitrary third-party dependency combinations, or workload-specific compatibility and performance issues unless explicitly stated in the listing terms
- Contact seller for: additional hardening, custom Nix packages, alternative CUDA versions, VPC/SG guidance
