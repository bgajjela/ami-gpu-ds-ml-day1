# GPU DS/ML AMI — Usage Guide

Everything is pre-installed and pre-configured. No manual `export JAVA_HOME`, no Nix
profile sourcing, no PATH changes — just run the commands below.

NVIDIA driver + CUDA 12.8 are installed on **both** base and pro AMIs. The pro AMI
adds GPU-enabled PyTorch (and GPU TensorFlow on x86; CPU TensorFlow on ARM64).

---

## Quick Start

```bash
# GPU
nvidia-smi        # driver + GPU status
nvcc --version    # CUDA 12.8 toolkit

# Python versions
py311 -V          # Python 3.11 (base env)
py312 -V          # Python 3.12 (base env)
py313 -V          # Python 3.13 (base env)

# Other languages
julia -e 'println(VERSION)'
R --version
go version
java -version     # Java 21 (OpenJDK)

# Spark
spark-submit --version
pyspark           # interactive shell (Python 3.11 default)
```

---

## Python Environments

### Base AMI — pre-installed packages

Each Python version has its own isolated Nix environment with a curated DS/ML package
set (NumPy, Pandas, scikit-learn, PySpark, Matplotlib, Jupyter, etc.).

| Command | Python | Environment path |
|---------|--------|-----------------|
| `py311` | 3.11   | `/opt/nix/envs/base` |
| `py312` | 3.12   | `/opt/nix/envs/base-py312` |
| `py313` | 3.13   | `/opt/nix/envs/base-py313` |

```bash
py311 -c "import numpy, pandas, sklearn; print('ok')"
py312 -c "import numpy, pandas, sklearn; print('ok')"
py313 -c "import numpy, pandas, sklearn; print('ok')"
```

### Pro AMI — adds full GPU DL stack

Pro environments layer **CUDA PyTorch** (`cu128` wheels), TensorFlow, Transformers,
XGBoost, and LightGBM on top of the base environments.

| Command | Python | Environment path |
|---------|--------|-----------------|
| `py311` | 3.11   | `/opt/nix/envs/pro` |
| `py312` | 3.12   | `/opt/nix/envs/pro-py312` |
| `py313` | 3.13   | `/opt/nix/envs/pro-py313` |

```bash
# Confirm PyTorch sees the GPU (both x86 and ARM64)
py311 -c "import torch; print(torch.__version__, torch.cuda.is_available(), torch.cuda.get_device_name(0))"
py312 -c "import torch; print(torch.cuda.is_available())"
py313 -c "from transformers import AutoTokenizer; print('ok')"
```

**TensorFlow:** GPU-enabled on x86_64 (`tensorflow[and-cuda]`); CPU-only on
ARM64/Graviton — there is no official aarch64 TensorFlow GPU wheel.

```bash
# x86: expect a non-empty GPU list; ARM64: expect [] (CPU TensorFlow)
py311 -c "import tensorflow as tf; print(tf.config.list_physical_devices('GPU'))"
```

---

## Installing Additional Packages

The Nix environments are immutable (system-owned). Use `newenv` to create a
user-owned virtual environment that inherits all pre-installed packages and lets
you `pip install` freely.

```bash
# Create a venv layered on the py311 base (inherits all base packages)
newenv py311 ~/my-project

# Or choose a different base
newenv py312 ~/analysis
newenv py313 ./venv

# On Pro AMI — layer on the pro env (gets torch/tf/transformers too)
newenv pro311 ~/dl-project
newenv pro312 ~/dl-analysis

# Activate and install
source ~/my-project/bin/activate
pip install my-custom-package
```

Available base options: `py311`, `py312`, `py313`, `pro311`, `pro312`, `pro313`.

---

## Apache Spark and PySpark

Java and Spark environment variables are set automatically — no manual exports needed.

### Interactive PySpark shell

```bash
pyspark           # Python 3.11 (default)
pyspark311        # Python 3.11 explicitly
pyspark312        # Python 3.12
pyspark313        # Python 3.13
```

### Submit a job

```bash
spark-submit my_job.py
spark-submit --master local[4] my_job.py

# Pin Python version
pyspark311 my_script.py   # not standard spark-submit usage; use env var below
PYSPARK_PYTHON=/opt/nix/envs/base-py312/bin/python spark-submit my_job.py
```

### Run bundled examples

```bash
spark-submit /usr/share/examples/spark/pyspark_basic.py
spark-submit /usr/share/examples/spark/pyspark_pi.py
```

### Use PySpark from a script or cron job

The wrappers (`pyspark`, `spark-submit`, `pyspark311`, etc.) set `JAVA_HOME`,
`SPARK_HOME`, and `SPARK_LOCAL_DIRS` internally — they work in scripts, cron,
SSH non-interactive sessions, Jupyter kernels, and systemd services without any
additional configuration.

```bash
#!/bin/bash
# This just works — no exports needed
spark-submit /opt/myapp/etl.py
```

---

## Other Languages

### Julia

```bash
julia                                    # REPL
julia my_script.jl                       # run a script
julia -e 'using Pkg; Pkg.add("DataFrames")'  # install a package
```

### R

```bash
R                                        # interactive console
Rscript my_analysis.R                    # run a script
Rscript -e 'install.packages("ggplot2")' # install a package
```

### Go

```bash
go version
go run main.go
go build -o my-app main.go
```

### Java (21)

```bash
java -version                            # OpenJDK 21
javac --version
```

### Rust

```bash
rustc --version
cargo --version
cargo new my-project && cd my-project && cargo build
```

### Node.js

```bash
node --version
npm --version
node my-script.js
```

---

## Security Scanning

Run an on-demand CVE and CIS compliance scan at any time:

```bash
# Full scan (CVE + CIS, saves to /var/log/ami-scan/)
sudo ami-scan

# CVE only
sudo ami-scan --cve

# CIS benchmark only
sudo ami-scan --cis

# Save results to a custom directory
sudo ami-scan --out /tmp/scan-results

# JSON output (for automation)
sudo ami-scan --json
```

Results are saved under `/var/log/ami-scan/` with `latest-cve.txt` and
`latest-cis.txt` symlinks for easy access.

---

## Build Information

```bash
# AMI variant and build timestamp
cat /usr/share/BUILD_INFO

# Full installed package list (all three Python versions + dpkg)
cat /usr/share/BUILD_INFO/packages.txt

# CycloneDX SBOM (JSON)
cat /usr/share/BUILD_INFO/sbom.cyclonedx.json

# License and legal notices
cat /usr/share/BUILD_INFO/EULA.txt
cat /usr/share/BUILD_INFO/EAR-classification.txt

# Security advisories
cat /usr/share/BUILD_INFO/SECURITY.md
```

---

## Environment Layout

```
/opt/nix/
  envs/
    base/           Python 3.11 base env
    base-py312/     Python 3.12 base env
    base-py313/     Python 3.13 base env
    pro/            Python 3.11 pro env  (Pro AMI only)
    pro-py312/      Python 3.12 pro env  (Pro AMI only)
    pro-py313/      Python 3.13 pro env  (Pro AMI only)
  langs/
    java/           OpenJDK 21
    spark/          Apache Spark
    julia/          Julia
    R/              R + Rscript
    go/             Go toolchain
    python313/      Python 3.13 interpreter (standalone)
    rustc/          Rust compiler
    cargo/          Cargo package manager
    nodejs/         Node.js + npm
  flake/
    flake.nix       Nix flake (pinned package versions)

/usr/local/bin/
  py311 py312 py313           Python version shortcuts
  julia R Rscript go java     Language shortcuts
  rustc cargo node npm        More language shortcuts
  spark-submit pyspark        Spark wrappers (set JAVA_HOME etc. automatically)
  pyspark311 pyspark312 pyspark313  Version-pinned PySpark wrappers
  newenv                      Create a user-owned pip-installable venv
  ami-scan                    On-demand CVE + CIS security scanner

/usr/share/examples/spark/
  pyspark_basic.py
  pyspark_pi.py

/usr/share/BUILD_INFO/
  packages.txt                Full package manifest
  sbom.cyclonedx.json         CycloneDX SBOM
  EULA.txt                    License terms
  EAR-classification.txt      Export control classification
  SECURITY.md                 Security advisories
```

---

## Troubleshooting

**`command not found: py311`**
Verify `/usr/local/bin` is in PATH: `echo $PATH`. It should be there by default.
If not: `export PATH="/usr/local/bin:$PATH"` and add it to `~/.bashrc`.

**`import torch` fails on Base AMI**
PyTorch, TensorFlow, and Transformers are only in the Pro AMI. Check which AMI
you launched: `cat /usr/share/BUILD_INFO/version`.

**`torch.cuda.is_available()` returns `False`**
Confirm the driver is up: `nvidia-smi`. If it errors, the instance may not be a
GPU type — launch on `g4dn.xlarge` (x86) or `g5g.xlarge` (ARM64) or larger. The
nvidia modules load at boot via `/etc/modules-load.d/nvidia.conf`.

**`nvidia-smi: command not found` or driver/library version mismatch**
The driver is `apt-mark hold`-ed to stay in lockstep with CUDA 12.8. Do not
`apt upgrade` the `cuda-drivers-570` / `cuda-toolkit-12-8` packages — that breaks
the driver↔CUDA↔PyTorch chain. To change versions, rebuild from `gpu/versions.env`.

**TensorFlow shows no GPU on ARM64**
Expected — aarch64 TensorFlow is CPU-only (no official GPU wheel). Use PyTorch for
GPU work on Graviton, or run the x86 pro AMI for GPU TensorFlow.

**`pip install` fails with permission error**
The Nix environments are system-owned. Use `newenv` to create a personal venv:
`newenv py311 ~/myenv && source ~/myenv/bin/activate && pip install your-package`.

**PySpark exits with `JAVA_HOME not set`**
This should not happen — `JAVA_HOME` is set in `/etc/environment` which is read
for all session types. Verify: `echo $JAVA_HOME`. If empty, run
`source /etc/environment` or re-login.

**Spark shuffle fills disk**
Shuffle data goes to `/opt/spark-local` (EBS-backed). Increase the EBS volume
or set `spark.local.dir` in your SparkConf to a larger attached volume.

**R package install fails**
R packages are user-installed. Try: `Rscript -e 'install.packages("pkg", lib="~/R/library")'`
and add `~/R/library` to `.libPaths()` in `~/.Rprofile`.

**Julia package install hangs**
Julia downloads packages on first `add`. Ensure outbound HTTPS is open in your
security group. Behind a proxy, set `JULIA_PKG_SERVER` or configure `~/.julia/config/startup.jl`.
