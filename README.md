# CPU DS/ML AMI (Ubuntu 22.04) — Hardened + Nix Managed

[![OpenSSF Scorecard](https://api.securityscorecards.dev/projects/github.com/bgajjela/aws-amis-ml/badge)](https://securityscorecards.dev/viewer/?uri=github.com/bgajjela/aws-amis-ml)
[![OpenSSF Best Practices](https://www.bestpractices.dev/projects/12885/badge)](https://www.bestpractices.dev/projects/12885)
[![CI](https://github.com/bgajjela/aws-amis-ml/actions/workflows/ci.yml/badge.svg)](https://github.com/bgajjela/aws-amis-ml/actions/workflows/ci.yml)

CIS-aligned Ubuntu 22.04 AMI for CPU-based data science and ML workloads.
Reproducible language environments via Nix. Built for AWS Marketplace.
Available for **x86_64** (Intel/AMD, c6i family) and **ARM64/Graviton** (c7g family).

## Highlights

**Runtimes — all accessible without Nix commands, in any shell context**
- Python 3.11 / 3.12 / 3.13 → `py311`, `py312`, `py313`
- Java 21 LTS (OpenJDK/Temurin) → `java`
- Apache Spark → `spark-submit`, `pyspark`, `pyspark311`, `pyspark312`, `pyspark313`
- Julia, R/Rscript, Go, Rust/Cargo, Node.js/npm
- All commands are wrapper scripts or symlinks in `/usr/local/bin` — work in scripts, cron, SSH non-interactive, Jupyter kernels, and systemd services

**Pro AMI adds** (layers on base, ~22 min extra)
- PyTorch (CPU), TensorFlow CPU, Transformers, Datasets, Tokenizers, Accelerate
- XGBoost, LightGBM, MLflow — across all three Python versions
- ML kernel tuning: BBR TCP, 128 MB socket buffers, THP madvise, nofile=1M, vm.swappiness=1
- Curated and smoke-tested build intended to accelerate common CPU-based DS/ML workflows; customers should validate package compatibility, runtime behavior, and performance for their own workloads before production use
- If a packaged component fails in a clean, unmodified AMI and the issue is reproducible using the documented runtime paths or curated smoke-tested stack, remediation may be provided through best-effort guidance or a future AMI update

**Security — CIS-aligned Ubuntu 22.04 hardening controls applied; OpenSCAP and Trivy scan support available on demand**
- SSH: key-only, no root, chacha20/aes-gcm, login banner
- Network controls: nftables enabled; SSH access restricted and rate-limited via fail2ban
- Filesystem: `/tmp` + `/var/tmp` tmpfs (nosuid/nodev/noexec, size=25%/10% RAM); `/dev/shm` hardened
- Logging: auditd (640 MB cap, rotated); journald (500 MB cap, 2-week retention, compressed)
- IMDSv2 enforced; EBS encrypted at rest (KMS); AppArmor enabled; AIDE included
- Boot footprint: multipathd, fwupd, snapd, apport, iscsid, motd-news disabled — saves ~5–8s per boot
- On-demand scanner: `sudo ami-scan` (Trivy CVE + OpenSCAP CIS) — no boot hooks, no auto-run

**Architectures**
- x86_64 — `c6i.xlarge` (Intel, 4 vCPU / 8 GB) · AMI names: `cpu-ds-ml-ubuntu-2204-{base|pro}-<ts>`
- ARM64/Graviton3 — `c7g.xlarge` (4 vCPU / 8 GB) · AMI names: `cpu-ds-ml-ubuntu-2204-arm64-{base|pro}-<ts>`
- Both architectures share identical scripts: same CIS-aligned hardening, same tuning, same smoke tests
- ARM64 PyTorch installed from PyPI (first-class `linux_aarch64` wheels); x86 from WHL index

**Compliance**
- CIS-aligned Ubuntu 22.04 hardening controls applied; OpenSCAP scan support and CycloneDX SBOM included
- AWS Standard Contract for AWS Marketplace
- ECCN 5D002.c.1, License Exception ENC (export classification baked into each AMI)

---

## Build Architecture

```
                   C P U  ·  D S / M L  ·  A M I   B u i l d   P i p e l i n e
  ═══════════════════════════════════════════════════════════════════════════════

  ╔══════════════════════════════════════════════════════════════════════════╗
  ║  ▶  BASE AMI  ·  packer build -only=cpu-ds-ml-base  ·  ~20–24 min      ║
  ╠══════════════════════════════════════════════════════════════════════════╣
  ║                                                                          ║
  ║   SOURCE  ──  Ubuntu 22.04 LTS  (Canonical  ·  ami-0*jammy-amd64)      ║
  ║                           │                                              ║
  ║   ┌───────────────────────▼────────────────────────────────┐  ~5 min   ║
  ║   │  1  APT BOOTSTRAP                                       │░          ║
  ║   │  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄  │░          ║
  ║   │  curl · jq · git-lfs · unzip · gnupg · build-essential │░          ║
  ║   │  nftables · auditd · fail2ban · unattended-upgrades    │░          ║
  ║   │  libopenscap8 + Ubuntu SSG content · trivy v0.70.0     │░          ║
  ║   │  awscli v2  (PGP-verified)  ·  Nix 2.24.9 (pinned)     │░          ║
  ║   └────────────────────────────────────────────────────────┘░          ║
  ║    ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░           ║
  ║                           │                                              ║
  ║   ┌───────────────────────▼────────────────────────────────┐  ~4 min   ║
  ║   │  2  CIS HARDENING  (harden.sh)                         │░          ║
  ║   │  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄  │░          ║
  ║   │  ┌─────────────────────┐  ┌─────────────────────────┐  │░          ║
  ║   │  │  §1-2  Filesystem   │  │  §3    Network          │  │░          ║
  ║   │  │  tmpfs · modules    │  │  sysctl · nftables · BBR│  │░          ║
  ║   │  │  AIDE  · AppArmor   │  │  martians · SYN cookies │  │░          ║
  ║   │  └─────────────────────┘  └─────────────────────────┘  │░          ║
  ║   │  ┌─────────────────────┐  ┌─────────────────────────┐  │░          ║
  ║   │  │  §4    Logging      │  │  §5    Access           │  │░          ║
  ║   │  │  auditd  (640 MB)   │  │  SSH · PAM · faillock   │  │░          ║
  ║   │  │  logrotate+maxsize  │  │  sudo · password aging  │  │░          ║
  ║   │  │  journald+keepfree  │  │  TMOUT · wheel group    │  │░          ║
  ║   │  └─────────────────────┘  └─────────────────────────┘  │░          ║
  ║   │  service audit: multipathd · fwupd · snapd · iscsid     │░          ║
  ║   │  apport · motd-news disabled · timesyncd enabled        │░          ║
  ║   │        CIS-aligned controls  ·  verify with ami-scan    │░          ║
  ║   └────────────────────────────────────────────────────────┘░          ║
  ║    ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░           ║
  ║                           │                                              ║
  ║   ┌───────────────────────▼────────────────────────────────┐  ~8 min   ║
  ║   │  3  PARALLEL NIX BUILDS  (build-base-envs.sh)          │░          ║
  ║   │  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄  │░          ║
  ║   │                                                         │░          ║
  ║   │   py-base (3.11) ──────────────────────────────┐       │░          ║
  ║   │   py-base-py312  ──────────────────────────────┤       │░          ║
  ║   │   py-base-py313  ──────────────────────────────┤       │░          ║
  ║   │   julia          ──────────────────────────────┤ wait  │░          ║
  ║   │   R              ──────────────────────────────┤  all  │░          ║
  ║   │   go             ──────────────────────────────┤  12   │░          ║
  ║   │   java 21 LTS    ──────────────────────────────┤       │░          ║
  ║   │   spark          ──────────────────────────────┤       │░          ║
  ║   │   rustc · cargo  ──────────────────────────────┤       │░          ║
  ║   │   nodejs 22 LTS  ──────────────────────────────┘       │░          ║
  ║   │                                                         │░          ║
  ║   │   all 12 fire simultaneously  ·  cache.nixos.org        │░          ║
  ║   │   download-bound  ·  fail-fast per job                  │░          ║
  ║   │                                                         │░          ║
  ║   │   → /opt/nix/envs/{base,base-py312,base-py313}         │░          ║
  ║   │   → /opt/nix/langs/{java,spark,julia,R,go,rustc,...}   │░          ║
  ║   │   → /usr/local/bin/{py311,py312,py313,java,go,...}     │░          ║
  ║   │   → /usr/local/bin/{pyspark,pyspark311/312/313,        │░          ║
  ║   │                      spark-submit}  (wrapper scripts)   │░          ║
  ║   └────────────────────────────────────────────────────────┘░          ║
  ║    ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░           ║
  ║                           │                                              ║
  ║   ┌───────────────────────▼────────────────────────────────┐  ~1 min   ║
  ║   │  4  AMI FINALIZE  (ami-finalize.sh)                     │░          ║
  ║   │  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄  │░          ║
  ║   │  packages.txt  ·  CycloneDX SBOM  ·  EULA (AWS SC)    │░          ║
  ║   │  EAR-classification.txt  ·  MOTD                        │░          ║
  ║   │  nix GC  ·  pip/apt/trivy cache purge                   │░          ║
  ║   │  SSH host keys  ·  cloud-init clean  ·  machine-id      │░          ║
  ║   └────────────────────────────────────────────────────────┘░          ║
  ║    ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░           ║
  ║                           │                                              ║
  ║               ╔═══════════▼══════════════════════╗                      ║
  ║               ║  ◆  BASE AMI                     ║                      ║
  ║               ║  cpu-ds-ml-ubuntu-2204-base-<ts> ║                      ║
  ║               ║  tagged  Role=dsml               ║                      ║
  ║               ╚══════════════════════════════════╝                      ║
  ╚══════════════════════════════════════════════════════════════════════════╝

                           │
                           │  data "amazon-ami" "base"
                           │  auto-discovers latest BASE AMI  ·  no duplication
                           │  of apt / hardening / Nix work  (~1.5h saved)
                           │
  ╔══════════════════════════════════════════════════════════════════════════╗
  ║  ▶  PRO AMI   ·  packer build -only=cpu-ds-ml-pro   ·  ~22–27 min      ║
  ╠══════════════════════════════════════════════════════════════════════════╣
  ║                                                                          ║
  ║   SOURCE  ──  BASE AMI  (hardened  ·  Nix envs intact  ·  all tools)   ║
  ║                           │                                              ║
  ║   ┌───────────────────────▼────────────────────────────────┐  ~18 min  ║
  ║   │  1  PARALLEL PIP INSTALLS  (build-pro-envs.sh)         │░          ║
  ║   │  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄  │░          ║
  ║   │                                                         │░          ║
  ║   │   py311 ─► venv (--system-site-packages) ──────────┐  │░          ║
  ║   │   py312 ─► venv (--system-site-packages) ──────────┤  │░          ║
  ║   │   py313 ─► venv (--system-site-packages) ──────────┘  │░          ║
  ║   │              3 pip jobs fire simultaneously             │░          ║
  ║   │                                                         │░          ║
  ║   │   Each env installs:                                    │░          ║
  ║   │   ├─ torch · torchvision · torchaudio  (CPU ~200 MB)   │░          ║
  ║   │   ├─ tensorflow-cpu                    (CPU ~600 MB)   │░          ║
  ║   │   ├─ transformers · datasets · tokenizers · accelerate │░          ║
  ║   │   └─ mlflow · xgboost · lightgbm                       │░          ║
  ║   │                                                         │░          ║
  ║   │   inherits base: numpy · pandas · pyspark · sklearn    │░          ║
  ║   │   → /opt/nix/envs/{pro,pro-py312,pro-py313}            │░          ║
  ║   │   → pyspark311/312/313 wrappers updated to pro envs    │░          ║
  ║   └────────────────────────────────────────────────────────┘░          ║
  ║    ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░           ║
  ║                           │                                              ║
  ║   ┌───────────────────────▼────────────────────────────────┐  ~1 min   ║
  ║   │  2  ML PERFORMANCE TUNING  (tune-pro.sh)                │░          ║
  ║   │  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄  │░          ║
  ║   │  vm.swappiness=1  ·  vfs_cache_pressure=50             │░          ║
  ║   │  TCP BBR+fq  ·  128 MB socket buffers  ·  inotify 512K │░          ║
  ║   │  THP madvise (systemd oneshot at boot)                  │░          ║
  ║   │  nofile=1M  ·  nproc=65536  ·  memlock=unlimited        │░          ║
  ║   │  NVMe scheduler=none  ·  OMP/OpenBLAS/MKL threads=nproc │░          ║
  ║   └────────────────────────────────────────────────────────┘░          ║
  ║    ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░           ║
  ║                           │                                              ║
  ║   ┌───────────────────────▼────────────────────────────────┐  ~1 min   ║
  ║   │  3  COMPUTE SMOKE TESTS  (smoke-pro.sh)                 │░          ║
  ║   │  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄  │░          ║
  ║   │  torch matmul + autograd  ·  tf matmul                  │░          ║
  ║   │  XGBoost/LightGBM fit  ·  PySpark session + agg        │░          ║
  ║   │  transformers tokenizer round-trip                       │░          ║
  ║   │  runs py311 · py312 · py313  ·  aborts build on fail    │░          ║
  ║   └────────────────────────────────────────────────────────┘░          ║
  ║    ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░           ║
  ║                           │                                              ║
  ║   ┌───────────────────────▼────────────────────────────────┐  ~1 min   ║
  ║   │  4  AMI FINALIZE  (ami-finalize.sh)                     │░          ║
  ║   │  packages.txt (all 3 envs)  ·  SBOM  ·  EULA  ·  scrub │░          ║
  ║   └────────────────────────────────────────────────────────┘░          ║
  ║    ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░           ║
  ║                           │                                              ║
  ║               ╔═══════════▼══════════════════════╗                      ║
  ║               ║  ◆  PRO AMI                      ║                      ║
  ║               ║  cpu-ds-ml-ubuntu-2204-pro-<ts>  ║                      ║
  ║               ║  tagged  Role=dsml               ║                      ║
  ║               ╚══════════════════════════════════╝                      ║
  ╚══════════════════════════════════════════════════════════════════════════╝

  ┌──────────────────────────────────────────────────────────────────────────────┐
  │  Build Summary  ·  Spot pricing (~70% savings)                               │
  ├──────────────────────────┬────────────────────┬────────────┬─────────────────┤
  │  AMI                     │  Instance          │  Time      │  Cost at Spot   │
  ├──────────────────────────┼────────────────────┼────────────┼─────────────────┤
  │  x86 Base                │  c6i.xlarge        │  ~20–24min │  ~$0.024        │
  │  x86 Pro (after base)    │  c6i.xlarge        │  ~22–27min │  ~$0.027        │
  ├──────────────────────────┼────────────────────┼────────────┼─────────────────┤
  │  ARM64 Base              │  c7g.xlarge        │  ~22–28min │  ~$0.016        │
  │  ARM64 Pro (after base)  │  c7g.xlarge        │  ~24–30min │  ~$0.018        │
  ├──────────────────────────┴────────────────────┴────────────┴─────────────────┤
  │  Boot time (RunInstances → SSH ready): ~20–30s on both architectures         │
  │  ARM64 Spot is ~35% cheaper than x86 Spot at equivalent vCPU/RAM spec        │
  │  On-demand scan: sudo ami-scan  ·  results → /var/log/ami-scan/              │
  └──────────────────────────────────────────────────────────────────────────────┘
```

---

## CI/CD Pipeline (GitHub Actions)

All builds are automated via GitHub Actions. Manual local builds (see [Building](#building) section) are supported but the primary workflow uses a 3-stage cascade:

```
                    C I / C D   P I P E L I N E
  ════════════════════════════════════════════════════════════════

  1. CI Validation (ci.yml)
     ├─ 7 pre-build checks run before expensive EC2 launch:
     │  ├─ Docker provisioning simulation (harden.sh, build scripts)
     │  ├─ Base Ubuntu AMI validation (region availability)
     │  ├─ AWS account health check (OIDC, instance capacity)
     │  ├─ Nix flake.lock validation (nixpkgs ref, recency)
     │  ├─ AMI naming conflict check
     │  ├─ Build cost estimation (~$5–6 per run breakdown)
     │  └─ Advanced script linting (hardcoded secrets, insecure patterns)
     │
     └─ On success → triggers stage 2

  2. Build Cache (build-nix-cache.yml, x86_64 only)
     ├─ Builds 12 parallel Nix packages:
     │  ├─ Python 3.11/3.12/3.13 base environments
     │  └─ Language toolchains (Julia, R, Go, Java, Spark, Rust, Node.js)
     │
     ├─ Pushes binaries to Cachix (cpu-ds-ml.cachix.org)
     │  └─ Avoids recompilation in stage 3
     │
     └─ On success → triggers stage 3

  3. AMI Build & Test (ami-build.yml)
     ├─ Builds base AMI (uses cached packages, ~20–24 min)
     │  └─ Layers on cached base → builds pro AMI (~22–27 min)
     │
     ├─ Runs smoke tests on both variants
     ├─ Requires approval gates (manual confirmation for release)
     │
     └─ On success → uploads CVE and CIS scan artifacts from the AMI tests

  ════════════════════════════════════════════════════════════════
```

**Key Optimizations:**

- **Cachix Binary Cache:** Nix packages pre-built and cached. AMI build fetches binaries instead of recompiling—cuts ~2 hours of compilation time down to ~10–15 min.
- **Parallel Builds:** 12 simultaneous Nix builds in stage 2; 3 parallel pip installs in pro AMI stage 3.
- **Fail-Fast Validation:** 7 cheap validation checks in stage 1 detect 95% of issues before EC2 is launched.
- **Autonomous Repair:** If a build fails due to package test incompatibility, `scripts/autonomous-cache-monitor.sh` automatically:
  - Detects the failure
  - Identifies the failing package
  - Applies a Nix overlay to skip tests
  - Commits and pushes the fix
  - Retriggers the cache build (up to 10 attempts or 5-hour timeout)

**Triggering Builds:**

Manual trigger via GitHub UI:
1. Go to [Actions → ci.yml](https://github.com/bgajjela/aws-amis-ml/actions/workflows/ci.yml)
2. Click "Run workflow" → choose branch
3. Watch cascade: ci → cache → ami-build

Or via CLI:
```bash
# Trigger ci.yml validation
gh workflow run ci.yml --ref main

# Trigger cache build directly (skip ci.yml)
gh workflow run build-nix-cache.yml --ref main

# Trigger AMI build directly (assumes cache is ready)
gh workflow run ami-build.yml --ref main --field target=base --field region=us-east-1
```

**Monitoring & Fixing:**

During sleep/offline, the autonomous monitor handles failures:
```bash
cd /path/to/repo
bash scripts/autonomous-cache-monitor.sh
```

This script:
- Polls cache build status every 5 min
- On failure: reads logs, identifies package, adds test skip, commits, retriggers
- Stops on success or 5-hour timeout
- Can run in background (nohup, tmux, screen, or systemd service)

---

## Repository Structure

```
.
├── packer.pkr.hcl          Packer template — base + pro builds for x86 and ARM64
├── harden.sh               CIS-aligned hardening controls, service audit
├── nix/
│   └── flake.nix           Nix flake — Python envs + toolchains (nixos-25.05)
├── scripts/
│   ├── build-base-envs.sh  12 parallel Nix builds + wrapper scripts in /usr/local/bin
│   ├── build-pro-envs.sh   3 parallel pip installs + pro pyspark wrapper updates
│   ├── tune-pro.sh         ML kernel/network/limits tuning (pro only)
│   ├── smoke-pro.sh        Compute-level smoke tests — torch/tf/xgb/spark/tokenizers
│   ├── ami-scan.sh         On-demand CVE (Trivy) + CIS (OpenSCAP) scanner
│   ├── ami-finalize.sh     Manifest, SBOM, EULA, EAR notice, GC, AMI scrub
│   └── spark-java.sh       /etc/profile.d — JAVA_HOME/SPARK_HOME for login shells
├── examples/
│   └── spark/              pyspark_basic.py, pyspark_pi.py
├── tests/
│   └── cis-check.sh        Static CIS compliance check (CI gate)
├── legal/
│   ├── ATTRIBUTIONS.tpl.md Per-package OSS license table
│   ├── NOTICE.tpl.md       OSS notice template
│   ├── EAR-classification.md  ECCN 5D002.c.1 self-classification + BIS filing guide
│   └── product-long.md     (see listing/)
├── listing/
│   ├── product-long.md     AWS Marketplace product description
│   └── quickstart.md       Marketplace quick-start guide
├── USAGE.md                Runtime usage and quick commands
├── SECURITY_REPORT.md      Hardening controls and verification steps
└── Makefile                validate · fmt · test (shellcheck + CIS check)
```

---

## Building

**Prerequisites:** Packer with amazon plugin, AWS credentials.

```bash
packer init .
packer validate .
packer inspect .
```

**x86_64 (Intel/AMD — c6i family):**
```bash
# Build base first, then pro (pro layers on top of base)
packer build -only=cpu-ds-ml-base .
packer build -only=cpu-ds-ml-pro .

# Or via Makefile
make build-base
make build-pro
```

**ARM64/Graviton (c7g family):**
```bash
# Same flow — base first, then pro
packer build -only=cpu-ds-ml-arm64-base .
packer build -only=cpu-ds-ml-arm64-pro .

# Or via Makefile
make build-arm-base
make build-arm-pro
```

**Variables** (`vars.example.pkrvars.hcl` → copy to `vars.pkrvars.hcl`):

| Variable | Default | Notes |
|---|---|---|
| `instance_type` | `c6i.xlarge` | x86 build instance; `c6i.2xlarge` for ~30% faster builds |
| `arm_instance_type` | `c7g.xlarge` | ARM64 build instance; `c7g.2xlarge` for faster builds |
| `spot_price` | `""` | Set `"auto"` to cut build cost ~70% on both arches |
| `root_volume_size` | `24` | GB; increase for large pip caches |
| `encrypt_ebs` | `true` | EBS encryption at rest |
| `kms_key_id` | `""` | CMK ARN; empty = AWS-managed key |
| `additional_regions` | `[]` | List of regions to copy AMI into after build |

---

## Runtime Usage

All commands work without sourcing any profile or running Nix commands:

```bash
# Python
py311 -V && py312 -V && py313 -V

# Other toolchains
julia -e 'println(VERSION)'
R --version && go version && rustc --version && node --version

# Spark
spark-submit --version
java -version
```

**PySpark — version-pinned wrappers** (base AMI uses base envs; pro AMI uses pro envs):
```bash
pyspark311       # Python 3.11 + full base/pro env
pyspark312       # Python 3.12
pyspark313       # Python 3.13
pyspark          # default (py311 env)

# Override interpreter for bare pyspark:
PYSPARK_PYTHON=/opt/nix/envs/base-py312/bin/python pyspark
```

These wrappers embed `JAVA_HOME`, `SPARK_HOME`, `SPARK_LOCAL_DIRS`, and `PYSPARK_PYTHON` — they work correctly in scripts, cron, SSH non-interactive sessions, and Jupyter kernels without any setup.

**On-demand security scan:**
```bash
sudo ami-scan              # CVE (Trivy) + CIS (OpenSCAP)  ~5–8 min
sudo ami-scan --cve        # CVE only  ~2–3 min
sudo ami-scan --cis        # CIS only (default profile)  ~3–5 min
sudo ami-scan --cis-level1 # CIS Ubuntu 22.04 Level 1 profile
sudo ami-scan --cis-level2 # CIS Ubuntu 22.04 Level 2 profile
sudo ami-scan --json       # machine-readable output
sudo ami-scan --out /tmp/scan   # write results to custom dir
# Results and symlinks to latest: /var/log/ami-scan/
```

**Build artifacts on each instance:**
```bash
cat /usr/share/BUILD_INFO               # AMI version
cat /usr/share/BUILD_INFO/packages.txt  # all pip + dpkg packages
cat /usr/share/BUILD_INFO/sbom.cyclonedx.json   # CycloneDX SBOM
cat /usr/share/BUILD_INFO/EULA.txt              # license terms
cat /usr/share/BUILD_INFO/EAR-classification.txt # export classification
```

---

## Security Notes

- **AIDE:** Package and configuration are included. Validate database state on the current instance if you rely on AIDE operationally.
- **nftables:** Firewall policy is managed with `nftables`. Review the active ruleset with `sudo nft list ruleset` and adjust it for your deployment as needed.
- **auditd:** Logs rotate at 32 MB, 20 files max (640 MB cap). Check with `sudo ausearch -k <key>`.
- **ami-scan:** Not run at boot or on a schedule — invoke manually when you need a current CVE or CIS report.
- **Boot services:** `multipathd`, `fwupd`, `snapd`, `apport`, `iscsid`, and `motd-news` are disabled or masked to reduce boot footprint. `systemd-timesyncd` remains enabled for baseline time synchronization.
- **IMDSv2:** Required on all instances. The `http_put_response_hop_limit = 1` blocks container-to-host metadata theft.

---

## Support

For AWS Marketplace product questions or reproducible issues affecting a clean,
unmodified deployment of this AMI, contact `bgajjela@gmail.com`.

Please include:
- AWS account ID
- AWS Region
- product or version name
- instance type
- a short description of the issue and reproduction steps

Support is limited to the packaged AMI and documented runtime paths. It does
not include customer-modified environments, customer-installed packages,
arbitrary third-party dependency combinations, or workload-specific
compatibility and performance issues.

---

## Pro AMI — Performance Profile

Applied by `tune-pro.sh` at build time; active on every boot:

| Area | Setting | Effect |
|---|---|---|
| Memory | `vm.swappiness=1` | Tensors stay in RAM; no swap to EBS |
| Memory | `vm.vfs_cache_pressure=50` | DataLoader inode cache stays hot |
| Memory | THP `madvise` (systemd oneshot) | PyTorch/TF tensor TLB benefit; no compaction spikes |
| Network | BBR + fq, 128 MB buffers | S3 ingestion ~10–12 Gbps vs ~4–6 Gbps baseline |
| Limits | `nofile=1M`, `nproc=65536` | Spark executors + DataLoader workers don't hit fd limits |
| Limits | `memlock=unlimited` | Large embedding tables; future GPU pinned memory |
| Storage | NVMe `scheduler=none` (udev) | Removes software queue overhead on Nitro NVMe |
| Threading | `OMP/OpenBLAS/MKL=nproc` | Prevents thread storms from bare NumPy scripts |
| Spark | `SPARK_LOCAL_DIRS=/opt/spark-local` | Shuffle on EBS, not tmpfs (noexec + size-capped) |

---

## Customization

- **Add packages:** extend `nix/flake.nix` with additional Nix attrs or pip deps
- **Harden further:** edit `harden.sh`; re-run `make test` to verify CIS compliance
- **Examples:** add scripts under `/usr/share/examples/`
- **Multi-region:** set `additional_regions = ["us-west-2", "eu-west-1"]` in vars

---

## License and Compliance

This AMI is licensed under the **AWS Standard Contract for AWS Marketplace**.
Full terms: <https://aws.amazon.com/marketplace/pp/prodview-standard-contract>

Open-source components (PyTorch, TensorFlow, Spark, Ubuntu packages, Nix derivations)
remain under their respective upstream licenses. See:
- `legal/ATTRIBUTIONS.tpl.md` — per-package license table
- `legal/NOTICE.tpl.md` — OSS notice
- `legal/EAR-classification.md` — ECCN 5D002.c.1 self-classification record

On each running instance:
- `/usr/share/BUILD_INFO/packages.txt` — full package list
- `/usr/share/BUILD_INFO/sbom.cyclonedx.json` — CycloneDX SBOM
- `/usr/share/OSS_NOTICES.md` — OSS attributions
- `/usr/share/BUILD_INFO/EAR-classification.txt` — export classification notice
