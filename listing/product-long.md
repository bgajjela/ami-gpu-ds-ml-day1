Why This AMI
- Ready-to-use CPU data science/ML environment with reproducible Nix builds.
- Security-focused: CIS-aligned Ubuntu 22.04 hardening controls, AppArmor, auditd, AIDE support, and on-instance scan tooling.
- Faster onboarding: Python 3.11/3.12/3.13, Julia, R, Go, Rust, Node.js, Java 21 (LTS), Apache Spark.
- Governed by the AWS Standard Contract for AWS Marketplace.

What's Included
- Ubuntu 22.04 LTS (HVM, EBS gp3, EBS-encrypted by default)
- Nix-managed environments under `/opt/nix` with symlinks in `/usr/local/bin`
- Python envs (base): numpy, pandas, scikit-learn, pyarrow, polars, matplotlib, seaborn,
  onnxruntime, OpenCV, PySpark — across Python 3.11, 3.12, and 3.13
- Python envs (pro): all base packages plus PyTorch (CPU), TensorFlow CPU,
  Transformers, Datasets, XGBoost, LightGBM, MLflow — across all three Python versions
- Toolchains: Julia, R, Go, Rust/Cargo, Node.js, Java 21 (OpenJDK/Temurin), Apache Spark
- On-demand scanner: `sudo ami-scan` runs Trivy CVE scan + OpenSCAP CIS audit
- Curated and smoke-tested package set intended for common CPU-based DS/ML workflows; customers remain responsible for validating package compatibility, runtime behavior, and performance for their own use cases before production use

Security & Compliance
- CIS-aligned Ubuntu 22.04 hardening controls with on-demand OpenSCAP and Trivy scan support
- SSH: key-only, root login disabled, strong crypto (chacha20/aes-gcm), login banner
- Network controls: nftables enabled; SSH access restricted and rate-limited via fail2ban
- Filesystem: /tmp and /var/tmp as tmpfs (nosuid, nodev, noexec); /dev/shm hardened
- Auditing: auditd (640 MB capped, rotated); AppArmor enabled; AIDE included
- Log management: journald compressed (500 MB cap, 2-week retention); logrotate weekly + 100 MB maxsize
- IMDSv2 enforced (prevents SSRF credential theft); EBS encryption at rest
- Export compliance: ECCN 5D002.c.1, License Exception ENC

Operations
- Rebuild envs via `nix build` from `/opt/nix/flake`; lock revisions with `nix flake lock`
- PySpark: set `PYSPARK_PYTHON` to target interpreter; shuffle stored on EBS (`/opt/spark-local`)
- On-demand CVE + CIS scan: `sudo ami-scan` (results in `/var/log/ami-scan/`)
- ML threading: OMP/OpenBLAS/MKL thread count pre-set to `nproc` via `/etc/profile.d/ml-threading.sh`
- Pro: THP madvise mode, BBR TCP, 128 MB socket buffers, 1M fd limit — tuned for PyTorch/TF/Spark

Support
- Usage: `USAGE.md` on-instance and in the repository
- Security details: `SECURITY_REPORT.md`
- Security is a shared responsibility: this AMI provides build-time hardening and scan support, and customers remain responsible for validating suitability and securely operating deployed instances
- If a packaged component fails in a clean, unmodified AMI and the issue is reproducible using the documented runtime paths or curated smoke-tested stack, the maintainer may provide best-effort guidance or address the issue in a future AMI update
- Support does not include guaranteeing compatibility with every upstream package, framework version, model, or third-party dependency combination unless explicitly stated in the listing terms
- Support does not extend to customer-installed packages, modified environments, arbitrary third-party dependency combinations, or workload-specific compatibility and performance issues unless explicitly stated in the listing terms
- Contact seller for: additional hardening, custom Nix packages, GPU variants, VPC/SG guidance
