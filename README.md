# GPU DS/ML AMI (Ubuntu 22.04) — CUDA 12.8, Hardened + Nix Managed

[![GPU AMI Build & Test (x86)](https://github.com/bgajjela/ami-gpu-ds-ml-day1/actions/workflows/ami-build-gpu-x86.yml/badge.svg)](https://github.com/bgajjela/ami-gpu-ds-ml-day1/actions/workflows/ami-build-gpu-x86.yml)

CIS-aligned Ubuntu 22.04 AMI for **NVIDIA GPU** data science and ML workloads.
NVIDIA driver + CUDA 12.8, GPU-enabled PyTorch / TensorFlow, reproducible language
environments via Nix. Built for AWS Marketplace (paid, hourly software fee).
Available for **x86_64** (g4dn / NVIDIA T4) and **ARM64/Graviton** (g5g / NVIDIA T4G).

> GPU variant of the CPU project [bgajjela/aws-amis-ml](https://github.com/bgajjela/aws-amis-ml).
> It reuses the same Nix + CIS-hardening base→pro foundation and layers the GPU stack on top.

## The GPU software chain

Driver, CUDA, and the PyTorch wheel index are a **locked chain** — if any one drifts,
the GPU silently falls back to CPU or fails to load. All four values live in one file,
[`gpu/versions.env`](gpu/versions.env); edit it and rebuild to upgrade.

| Layer | Pinned to | Notes |
|---|---|---|
| NVIDIA driver | `570` branch (`cuda-drivers-570`, held) | supports CUDA 12.8 |
| CUDA toolkit | `12.8` (`cuda-toolkit-12-8`, held) | `nvcc` + dev libs |
| PyTorch | `cu128` wheel index | the **only** source of aarch64 CUDA torch wheels (2.8+) |
| cuDNN / cuBLAS | bundled as pip deps of torch | not installed system-wide |

## Highlights

**Runtimes — all accessible without Nix commands, in any shell context**
- Python 3.11 / 3.12 / 3.13 → `py311`, `py312`, `py313`
- Java 21 LTS, Apache Spark (`spark-submit`, `pyspark`, `pyspark311/312/313`)
- Julia, R/Rscript, Go, Rust/Cargo, Node.js/npm
- CUDA toolkit on `PATH` → `nvcc`, `nvidia-smi`
- All commands are wrapper scripts or symlinks in `/usr/local/bin` — work in scripts, cron, SSH non-interactive, Jupyter kernels, and systemd services

**Pro AMI adds** (layers on base)
- **PyTorch with CUDA** (`cu128`), Transformers, Datasets, Tokenizers, Accelerate
- **TensorFlow GPU on x86** (`tensorflow[and-cuda]`); **TensorFlow CPU on ARM64** — there is no official aarch64 TF GPU wheel, and shipping a community build is avoided for a paid product
- XGBoost (GPU hist), LightGBM, MLflow — across all three Python versions
- GPU tuning: persistence mode, expandable-segments allocator, lazy CUDA module loading — plus the inherited CPU/data-loading tuning (BBR, THP madvise, NVMe scheduler, `nofile=1M`)
- Curated and smoke-tested build intended to accelerate common GPU DS/ML workflows; customers should validate package compatibility, runtime behavior, and performance for their own workloads before production use

**Security — CIS-aligned Ubuntu 22.04 hardening controls applied; OpenSCAP and Trivy scan support on demand**
- GPU stack installed **before** hardening so CIS module/sysctl lockdown does not interfere with driver loading; `nouveau` blacklisted, `nvidia` modules loaded at boot
- SSH: key-only, no root, chacha20/aes-gcm, login banner
- Network controls: UFW (nftables backend) default-deny; SSH rate-limited via fail2ban
- Filesystem: `/tmp` + `/var/tmp` tmpfs (nosuid/nodev/noexec); `/dev/shm` hardened
- Logging: auditd (640 MB cap, rotated); journald (500 MB cap, compressed)
- IMDSv2 enforced; AppArmor enabled; AIDE included
- On-demand scanner: `sudo ami-scan` (Trivy CVE + OpenSCAP CIS) — no boot hooks

**Architectures**
- x86_64 — `g4dn.xlarge` (NVIDIA T4, 4 vCPU / 16 GB) · AMI names: `gpu-ds-ml-ubuntu-2204-{base|pro}-<ts>`
- ARM64/Graviton — `g5g.xlarge` (NVIDIA T4G, 4 vCPU / 8 GB) · AMI names: `gpu-ds-ml-ubuntu-2204-arm64-{base|pro}-<ts>`
- Both share identical scripts: same CUDA install, same CIS hardening, same tuning, same GPU smoke tests
- PyTorch CUDA wheels come from the `cu128` index on **both** architectures

**Compliance**
- CIS-aligned Ubuntu 22.04 hardening controls applied; OpenSCAP scan support and CycloneDX SBOM included
- AWS Standard Contract for AWS Marketplace
- ECCN 5D002.c.1, License Exception ENC (export classification baked into each AMI)

---

## Build Architecture

```
                 G P U  ·  D S / M L  ·  A M I   B u i l d   P i p e l i n e
  ═══════════════════════════════════════════════════════════════════════════════

  ╔══════════════════════════════════════════════════════════════════════════╗
  ║  ▶  BASE AMI  ·  -only=gpu-ds-ml-x86-base  ·  on g4dn.xlarge (T4)        ║
  ╠══════════════════════════════════════════════════════════════════════════╣
  ║                                                                          ║
  ║   SOURCE  ──  Ubuntu 22.04 LTS  (Canonical  ·  stock jammy image)      ║
  ║                           │                                              ║
  ║   ┌───────────────────────▼────────────────────────────────┐           ║
  ║   │  1  APT BOOTSTRAP  +  KERNEL REBOOT                     │           ║
  ║   │  apt upgrade → reboot into final kernel (DKMS target)   │           ║
  ║   │  curl · jq · build-essential · nftables · auditd        │           ║
  ║   │  fail2ban · trivy · awscli v2 (PGP) · Nix 2.24.9        │           ║
  ║   └────────────────────────────────────────────────────────┘           ║
  ║                           │                                              ║
  ║   ┌───────────────────────▼────────────────────────────────┐  GPU      ║
  ║   │  2  CUDA INSTALL  (install-cuda.sh)  +  REBOOT          │  ★★★      ║
  ║   │  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄  │           ║
  ║   │  NVIDIA driver 570 + cuda-toolkit-12-8  (apt, pinned)   │           ║
  ║   │  blacklist nouveau · DKMS build · modules-load.d/nvidia │           ║
  ║   │  apt-mark hold · CUDA on PATH via /etc/profile.d        │           ║
  ║   │  reboot → nouveau unloads, nvidia binds → verify        │           ║
  ║   │                       nvidia-smi  ·  nvcc --version      │           ║
  ║   └────────────────────────────────────────────────────────┘           ║
  ║                           │                                              ║
  ║   ┌───────────────────────▼────────────────────────────────┐           ║
  ║   │  3  PARALLEL NIX BUILDS  (build-base-envs.sh)          │           ║
  ║   │  py311/312/313 · julia · R · go · java · spark · ...    │           ║
  ║   │  12 builds, Cachix-backed (cpu-ds-ml.cachix.org)        │           ║
  ║   │  → /usr/local/bin/{py311,py312,py313,spark-submit,...}  │           ║
  ║   └────────────────────────────────────────────────────────┘           ║
  ║                           │                                              ║
  ║   ┌───────────────────────▼────────────────────────────────┐           ║
  ║   │  4  CIS HARDENING  (harden.sh)  — runs AFTER CUDA       │           ║
  ║   │  filesystem · network · logging · access · service audit│           ║
  ║   │  module blacklist does NOT touch nvidia · re-verify GPU │           ║
  ║   └────────────────────────────────────────────────────────┘           ║
  ║                           │                                              ║
  ║   ┌───────────────────────▼────────────────────────────────┐           ║
  ║   │  5  AMI FINALIZE  ·  SBOM · EULA · EAR · scrub          │           ║
  ║   └────────────────────────────────────────────────────────┘           ║
  ║               ╔═══════════▼══════════════════════╗                      ║
  ║               ║  ◆  gpu-ds-ml-ubuntu-2204-base-<ts>  Role=dsml-gpu ║   ║
  ║               ╚══════════════════════════════════╝                      ║
  ╚══════════════════════════════════════════════════════════════════════════╝

                           │  source_ami = GPU base AMI (driver+CUDA+Nix+hardened)
                           │  no repeat of apt / CUDA / hardening / Nix work
                           ▼
  ╔══════════════════════════════════════════════════════════════════════════╗
  ║  ▶  PRO AMI   ·  -only=gpu-ds-ml-x86-pro   ·  on g4dn.xlarge (T4)       ║
  ╠══════════════════════════════════════════════════════════════════════════╣
  ║   ┌────────────────────────────────────────────────────────┐           ║
  ║   │  1  PARALLEL PIP INSTALLS  (build-gpu-envs.sh)         │           ║
  ║   │  py311/312/313 → venv (--system-site-packages)         │           ║
  ║   │  ├─ torch · torchvision · torchaudio   (cu128 index)   │           ║
  ║   │  ├─ tensorflow[and-cuda]  (x86)  /  tensorflow-cpu (arm)│           ║
  ║   │  ├─ transformers · datasets · tokenizers · accelerate  │           ║
  ║   │  └─ mlflow · xgboost · lightgbm                        │           ║
  ║   │  inherits base: numpy · pandas · pyspark · sklearn     │           ║
  ║   └────────────────────────────────────────────────────────┘           ║
  ║   ┌────────────────────────────────────────────────────────┐           ║
  ║   │  2  TUNING  ·  tune-pro.sh  then  tune-gpu.sh           │           ║
  ║   │  CPU/data tuning + persistence mode, expandable_segments│           ║
  ║   │  lazy CUDA module loading, TF allow-growth              │           ║
  ║   └────────────────────────────────────────────────────────┘           ║
  ║   ┌────────────────────────────────────────────────────────┐           ║
  ║   │  3  GPU SMOKE TESTS  (smoke-gpu.sh)                     │           ║
  ║   │  nvidia-smi · torch CUDA matmul+autograd ON GPU         │           ║
  ║   │  tf GPU matmul (x86) · xgboost GPU · pyspark · all 3 py │           ║
  ║   │  ASSERTS cuda is live — aborts build on CPU fallback    │           ║
  ║   └────────────────────────────────────────────────────────┘           ║
  ║   ┌────────────────────────────────────────────────────────┐           ║
  ║   │  4  AMI FINALIZE  ·  packages.txt · SBOM · scrub        │           ║
  ║   └────────────────────────────────────────────────────────┘           ║
  ║               ╔═══════════▼══════════════════════╗                      ║
  ║               ║  ◆  gpu-ds-ml-ubuntu-2204-pro-<ts>   Role=dsml-gpu ║   ║
  ║               ╚══════════════════════════════════╝                      ║
  ╚══════════════════════════════════════════════════════════════════════════╝

  ┌──────────────────────────────────────────────────────────────────────────────┐
  │  Build hosts (cheapest compatible — the AMI runs on any larger GPU instance)  │
  ├──────────────────────────┬────────────────────┬──────────────────────────────┤
  │  AMI                     │  Build instance    │  On-demand (us-east-1, approx)│
  ├──────────────────────────┼────────────────────┼──────────────────────────────┤
  │  x86 base / pro          │  g4dn.xlarge (T4)  │  ~$0.53/hr                    │
  │  ARM64 base / pro        │  g5g.xlarge (T4G)  │  ~$0.42/hr                    │
  ├──────────────────────────┴────────────────────┴──────────────────────────────┤
  │  Root volume bumped to 80 GB (CUDA toolkit + cuDNN + CUDA wheels are large)   │
  │  Use spot_price="auto" to cut build cost significantly                        │
  └──────────────────────────────────────────────────────────────────────────────┘
```

---

## CI/CD Pipeline (GitHub Actions)

Each architecture has its own workflow:
[`ami-build-gpu-x86.yml`](.github/workflows/ami-build-gpu-x86.yml) and
[`ami-build-gpu-arm64.yml`](.github/workflows/ami-build-gpu-arm64.yml).

The GitHub runner stays CPU (`ubuntu-22.04`) and only orchestrates — **Packer launches
a real GPU instance** as the build host, and `test-ami.sh` launches a real GPU instance
to test, so all GPU work happens on EC2, never on the runner.

```
  validate ─► build-base ─► guard-contract ─► test-base ─► build-pro ─► test-pro ─► tag-release
     │            (Packer on GPU instance)     (test-ami.sh on GPU instance, GPU_AMI=1)
     └────────────────────────────────────────────────────────────────► cleanup-orphans (always)
```

- **OIDC, no static keys** — assumes `AWS_ROLE_ARN`; logs scrub account/VPC/subnet/SG IDs (`sanitize-log.py`).
- **Test contract guard** — base AMI must carry the current `TestContractVersion` tag before pro builds on it.
- **GPU verification** — `test-ami.sh` (with `GPU_AMI=1`) runs `nvidia-smi` and, on pro, asserts `torch.cuda.is_available()` and a real GPU matmul on a freshly launched instance.
- **Cachix** — the Nix base layer reuses the existing `cpu-ds-ml.cachix.org` cache (Python envs + toolchains are identical to the CPU AMIs).

Trigger via CLI:
```bash
# x86 base, then base→pro
gh workflow run ami-build-gpu-x86.yml --ref main -f target=base
gh workflow run ami-build-gpu-x86.yml --ref main -f target=pro

# ARM64 (phase 2)
gh workflow run ami-build-gpu-arm64.yml --ref main -f target=pro
```

---

## Repository Structure

```
.
├── packer-gpu.pkr.hcl       GPU Packer template — base+pro for x86 and ARM64
├── packer.pkr.hcl           Shared CPU template (home of the reused variables)
├── gpu/
│   └── versions.env         ★ single source of truth: driver/CUDA/torch pins
├── harden.sh                CIS-aligned hardening controls (shared, unchanged)
├── nix/
│   └── flake.nix            Nix flake — Python envs + toolchains (shared)
├── scripts/
│   ├── install-cuda.sh      NVIDIA driver + CUDA toolkit (arch-aware) — GPU only
│   ├── build-gpu-envs.sh    CUDA torch/tf pip layering (GPU twin of build-pro-envs.sh)
│   ├── tune-gpu.sh          GPU tuning: persistence, allocator, lazy loading
│   ├── smoke-gpu.sh         GPU compute smoke tests (asserts CUDA is live)
│   ├── build-base-envs.sh   12 parallel Nix builds + /usr/local/bin wrappers (shared)
│   ├── tune-pro.sh          CPU/data-loading tuning (shared, runs before tune-gpu)
│   ├── test-ami.sh          launch/verify/teardown — GPU-aware via GPU_AMI + TEST_INSTANCE_TYPE
│   ├── ami-scan.sh          on-demand CVE (Trivy) + CIS (OpenSCAP) scanner (shared)
│   └── ami-finalize.sh      manifest, SBOM, EULA, EAR notice, GC, scrub (shared)
├── .github/workflows/
│   ├── ami-build-gpu-x86.yml    GPU x86 build/test/tag pipeline
│   └── ami-build-gpu-arm64.yml  GPU ARM64 build/test/tag pipeline
├── examples/ · legal/ · listing/ · tests/   (shared)
└── README.md
```

---

## Building

**Prerequisites:** Packer with the amazon plugin, AWS credentials, GPU instance quota.

```bash
packer init .
packer validate \
  -var gpu_base_ami_id=ami-00000000000000000 \
  -var gpu_base_ami_id_arm=ami-00000000000000000 .
```

**x86_64 (g4dn / NVIDIA T4):**
```bash
# Base first, then pro (pro layers on the base AMI)
packer build -only=gpu-ds-ml-x86-base.amazon-ebs.gpu_x86_base \
  -var "subnet_id=subnet-xxx" -var "root_volume_size=80" .

packer build -only=gpu-ds-ml-x86-pro.amazon-ebs.gpu_x86_pro \
  -var "gpu_base_ami_id=ami-xxx" -var "subnet_id=subnet-xxx" -var "root_volume_size=80" .
```

**ARM64/Graviton (g5g / NVIDIA T4G):**
```bash
packer build -only=gpu-ds-ml-arm64-base.amazon-ebs.gpu_arm_base \
  -var "subnet_id=subnet-xxx" -var "root_volume_size=80" .

packer build -only=gpu-ds-ml-arm64-pro.amazon-ebs.gpu_arm_pro \
  -var "gpu_base_ami_id_arm=ami-xxx" -var "subnet_id=subnet-xxx" -var "root_volume_size=80" .
```

**GPU variables** (reuses the shared `region`, `spot_price`, `subnet_id`, etc.):

| Variable | Default | Notes |
|---|---|---|
| `gpu_instance_type` | `g4dn.xlarge` | x86 GPU build host (NVIDIA T4) |
| `gpu_arm_instance_type` | `g5g.xlarge` | ARM64 GPU build host (NVIDIA T4G) |
| `gpu_base_ami_id` | `""` | x86 base AMI the pro build layers on |
| `gpu_base_ami_id_arm` | `""` | ARM64 base AMI the pro build layers on |
| `root_volume_size` | `24` | **set to 80** for GPU builds (CUDA + cuDNN + wheels) |
| `spot_price` | `""` | set `"auto"` to cut build cost |

**Upgrading CUDA later:** edit the four pins in [`gpu/versions.env`](gpu/versions.env)
(driver branch, CUDA series, torch index) and rebuild. No other file hard-codes a version.

---

## Runtime Usage

```bash
# GPU
nvidia-smi
nvcc --version

# Python + GPU PyTorch
py311 -c "import torch; print(torch.__version__, torch.cuda.is_available(), torch.cuda.get_device_name(0))"

# Other toolchains
julia -e 'println(VERSION)'; R --version; go version; node --version
spark-submit --version
```

**PySpark wrappers** (`pyspark311/312/313`, `pyspark`) embed `JAVA_HOME`, `SPARK_HOME`,
`SPARK_LOCAL_DIRS`, `PYSPARK_PYTHON` — they work in scripts, cron, SSH non-interactive,
and Jupyter kernels with no setup.

**On-demand security scan:**
```bash
sudo ami-scan              # CVE (Trivy) + CIS (OpenSCAP)
sudo ami-scan --cve        # CVE only
sudo ami-scan --cis-level2 # CIS Ubuntu 22.04 Level 2 profile
# Results: /var/log/ami-scan/
```

**Build artifacts on each instance:**
```bash
cat /usr/share/BUILD_INFO/version              # e.g. 1.0.0-GPU-PRO
cat /usr/share/BUILD_INFO/packages.txt         # all pip + dpkg packages
cat /usr/share/BUILD_INFO/sbom.cyclonedx.json  # CycloneDX SBOM
```

---

## Pro AMI — GPU Performance Profile

Applied by `tune-pro.sh` + `tune-gpu.sh` at build time; active on every boot:

| Area | Setting | Effect |
|---|---|---|
| GPU | `nvidia-persistenced` + persistence-mode service | no multi-second driver re-init between processes |
| GPU | `PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True` | less fragmentation / OOM on long runs |
| GPU | `CUDA_MODULE_LOADING=LAZY` | faster process start, lower GPU memory footprint |
| GPU | `TF_FORCE_GPU_ALLOW_GROWTH=true` | TF shares the GPU instead of grabbing all VRAM |
| Memory | `vm.swappiness=1`, THP `madvise` | tensors stay in RAM; TLB benefit without compaction spikes |
| Network | BBR + fq, 128 MB buffers | faster S3 dataset ingestion |
| Limits | `nofile=1M`, `memlock=unlimited` | DataLoader workers + pinned CUDA buffers |
| Storage | NVMe `scheduler=none` | no software queue overhead on Nitro NVMe |

---

## Notes & Caveats

- **TensorFlow on ARM64 is CPU-only** — no official aarch64 TF GPU wheel exists. PyTorch is GPU-enabled on both architectures.
- **nouveau** is blacklisted and the driver is `apt-mark hold`-ed so unattended upgrades can't break the driver↔CUDA↔torch chain.
- **torch + `tensorflow[and-cuda]`** share one venv (same pattern as the CPU AMIs); they each pull `nvidia-*-cu12` pip deps — the smoke test catches any version conflict at build time.
- GPU instances are billed by the hour; build on the cheapest compatible host — the resulting AMI runs on any larger GPU instance the customer chooses.

---

## Support

For AWS Marketplace product questions or reproducible issues affecting a clean,
unmodified deployment of this AMI, contact `bgajjela@gmail.com` with AWS account ID,
region, product/version, instance type, and reproduction steps. Support is limited to
the packaged AMI and documented runtime paths.

---

## License and Compliance

Licensed under the **AWS Standard Contract for AWS Marketplace**.
Open-source components (PyTorch, TensorFlow, CUDA runtime libraries, Spark, Ubuntu
packages, Nix derivations) remain under their respective upstream licenses. NVIDIA
driver and CUDA components are subject to the NVIDIA CUDA Toolkit EULA. See:
- `legal/ATTRIBUTIONS.tpl.md` — per-package license table
- `legal/EAR-classification.md` — ECCN 5D002.c.1 self-classification record

On each running instance: `/usr/share/BUILD_INFO/packages.txt`,
`/usr/share/BUILD_INFO/sbom.cyclonedx.json`, `/usr/share/OSS_NOTICES.md`.
