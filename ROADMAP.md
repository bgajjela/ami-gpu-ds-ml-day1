# Roadmap

## Current release — v1.0.0 (May 2026)

- Ubuntu 22.04 LTS with CIS L1+L2 hardening (114 controls)
- Python 3.11, 3.12, 3.13 via Nix (Base and Pro editions)
- PyTorch CPU, TensorFlow, Transformers, XGBoost, LightGBM, MLflow (Pro)
- Apache Spark 3.5.x + Java 21 with PySpark wrappers
- x86_64 and ARM64/Graviton3 builds
- CycloneDX 1.4 SBOM
- SSM-only access (no open SSH port)

## Near term (next 6 months)

- **GPU edition** — CUDA-enabled build for P3/P4 instance families
- **Ubuntu 24.04 LTS** — track next LTS release with updated CIS benchmarks
- **OpenSCAP scan report** — published compliance report shipped with each release
- **Compatibility matrix** — verified instance type and region coverage table
- **Graviton3 benchmarks** — published performance comparison vs x86_64

## Medium term (6–12 months)

- **AWS Marketplace listing** — public AMI listing with pay-as-you-go pricing
- **Python 3.14** — add to Nix environments when stable
- **Spark 4.x** — track Apache Spark major release
- **DISA STIG alignment report** — formal Ubuntu 22.04 STIG compliance documentation
- **Automated CVE patch pipeline** — auto-PR on new HIGH/CRITICAL CVEs in dependencies

## Out of scope

- Windows AMIs
- GPU-only workloads (PyTorch GPU is a separate edition)
- Container images (separate project)
- Non-AWS cloud providers

## How to influence the roadmap

Open a [GitHub issue](https://github.com/bgajjela/aws-amis-ml/issues) with the label `roadmap`. Feature requests with clear use cases and upvotes will be prioritized.
