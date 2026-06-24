#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Bharath Kumar Gajjela
# build-gpu-envs.sh — GPU twin of build-pro-envs.sh. Creates the pro Python envs
# layered on the base Nix envs, but installs CUDA-enabled frameworks.
#
# Strategy (identical to the CPU pro build): venv --system-site-packages inherits
# the immutable Nix base packages, then pip installs the heavy DL frameworks via
# pre-built CUDA wheels. All three Python versions build in parallel.
#
# GPU specifics:
#   torch: installed from the cu128 wheel index (gpu/versions.env TORCH_CHANNEL).
#          This index is the ONLY source of aarch64 CUDA torch wheels (2.8+) and
#          also serves x86_64. The wheels bundle cuDNN/cuBLAS/CUDA-runtime as pip
#          deps, so the system CUDA toolkit is for nvcc/dev, not torch runtime.
#   tensorflow:
#          x86_64  -> tensorflow[and-cuda]  (official GPU build)
#          aarch64 -> tensorflow-cpu        (NO official aarch64 GPU wheel exists;
#                     shipping a community GPU wheel is a Marketplace liability)
set -euo pipefail

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
PIP_TMPDIR="/opt/pip-tmp"
PIP_CACHE_DIR="/opt/pip-cache"

sudo mkdir -p "${PIP_TMPDIR}" "${PIP_CACHE_DIR}"
sudo chmod 1777 "${PIP_TMPDIR}"
sudo chmod 755 "${PIP_CACHE_DIR}"

_pip_invoke() {
  sudo env \
    TMPDIR="${PIP_TMPDIR}" \
    TEMP="${PIP_TMPDIR}" \
    TMP="${PIP_TMPDIR}" \
    PIP_CACHE_DIR="${PIP_CACHE_DIR}" \
    "$@"
}

_runtime_lib_path() {
  find /nix/store \
    -type f \
    \( -name 'libstdc++.so.6*' -o -name 'libgomp.so.1*' \) \
    -exec dirname {} + 2>/dev/null \
    | awk 'NF' | sort -u | paste -sd: -
}

_write_python_wrapper() {
  local py_bin="$1" dst="$2" runtime_lib_path="$3"
  sudo tee "${dst}" >/dev/null <<WRAPPER
#!/bin/sh
RUNTIME_LIB_PATH="${runtime_lib_path}"
if [ -n "\${RUNTIME_LIB_PATH}" ]; then
  if [ -n "\${LD_LIBRARY_PATH:-}" ]; then
    export LD_LIBRARY_PATH="\${RUNTIME_LIB_PATH}:\${LD_LIBRARY_PATH}"
  else
    export LD_LIBRARY_PATH="\${RUNTIME_LIB_PATH}"
  fi
fi
exec "${py_bin}" "\$@"
WRAPPER
  sudo chmod 755 "${dst}"
}

# ── Per-version build function (runs in a subshell background job) ────────────
_build_gpu() {
  local label="$1" base_env="$2" pro_env="$3" wrapper_dst="$4"
  local runtime_lib_path smoke_wrapper pro_site base_site cache_site

  echo "=== [${label}] ${base_env} -> ${pro_env} (arch: ${ARCH}, ${TORCH_CUDA_INDEX}) ==="

  sudo "${base_env}/bin/python" -m venv --system-site-packages "${pro_env}"
  _pip_invoke "${pro_env}/bin/pip" install --upgrade pip --quiet
  sudo chmod -R a+rX "${pro_env}"

  pro_site="$("${pro_env}/bin/python" - <<'PY'
import site
print(site.getsitepackages()[0])
PY
)"
  base_site="$("${base_env}/bin/python" - <<'PY'
import site
print(site.getsitepackages()[0])
PY
)"
  cache_site="$("/opt/nix/cache-envs/${base_env##*/}/bin/python" - <<'PY'
import site
print(site.getsitepackages()[0])
PY
)"

  printf '%s\n' "${base_site}" | sudo tee "${pro_site}/_base_env_site.pth" >/dev/null
  printf '%s\n' "${cache_site}" | sudo tee "${pro_site}/_cache_env_site.pth" >/dev/null
  sudo chmod -R a+rX "${pro_env}"

  echo "  [${label}] torch (${TORCH_CUDA_INDEX} CUDA wheels)..."
  # cu128 index serves both x86_64 and aarch64. The wheels carry their own
  # CUDA runtime + cuDNN as nvidia-*-cu12 pip dependencies.
  _pip_invoke "${pro_env}/bin/pip" install \
    torch torchvision torchaudio \
    --index-url "${TORCH_CHANNEL}" \
    --quiet

  if [ "${ARCH}" = "x86_64" ]; then
    echo "  [${label}] tensorflow[and-cuda] + ecosystem..."
    _pip_invoke "${pro_env}/bin/pip" install \
      "tensorflow[and-cuda]" \
      transformers datasets tokenizers sentencepiece accelerate \
      --quiet
  else
    echo "  [${label}] tensorflow-cpu (no official aarch64 GPU wheel) + ecosystem..."
    _pip_invoke "${pro_env}/bin/pip" install \
      tensorflow-cpu \
      transformers datasets tokenizers sentencepiece accelerate \
      --quiet
  fi

  echo "  [${label}] mlflow, xgboost, lightgbm..."
  _pip_invoke "${pro_env}/bin/pip" install mlflow xgboost lightgbm --quiet

  echo "  [${label}] smoke test..."
  runtime_lib_path="$(_runtime_lib_path)"
  smoke_wrapper="${PIP_TMPDIR}/${label}-smoke-python"
  _write_python_wrapper "${pro_env}/bin/python" "${smoke_wrapper}" "${runtime_lib_path}"
  "${smoke_wrapper}" -c "
import numpy, pandas, pyspark, sklearn
import torch, tensorflow, transformers, mlflow, xgboost, lightgbm
assert torch.cuda.is_available(), 'torch CUDA not available during build'
print('  numpy=' + numpy.__version__ + ' torch=' + torch.__version__ + \
      ' cuda=' + str(torch.version.cuda) + ' tf=' + tensorflow.__version__)
print('  torch device: ' + torch.cuda.get_device_name(0))
"
  sudo rm -f "${smoke_wrapper}"
  sudo chmod -R a+rX "${pro_env}"
  _write_python_wrapper "${pro_env}/bin/python" "${wrapper_dst}" "${runtime_lib_path}"
  echo "  [${label}] wrapper: ${wrapper_dst} -> ${pro_env}/bin/python"
  echo "=== [${label}] DONE ==="
}

# ── Launch all three versions in parallel ─────────────────────────────────────
echo "=== Building GPU pro envs in parallel (py311 / py312 / py313) ==="

_build_gpu "py311" /opt/nix/envs/base       /opt/nix/envs/pro       /usr/local/bin/py311 \
  >"/tmp/gpu-py311.log" 2>&1 &
PID311=$!

_build_gpu "py312" /opt/nix/envs/base-py312 /opt/nix/envs/pro-py312 /usr/local/bin/py312 \
  >"/tmp/gpu-py312.log" 2>&1 &
PID312=$!

_build_gpu "py313" /opt/nix/envs/base-py313 /opt/nix/envs/pro-py313 /usr/local/bin/py313 \
  >"/tmp/gpu-py313.log" 2>&1 &
PID313=$!

echo "  py311 pid=${PID311}  py312 pid=${PID312}  py313 pid=${PID313}"
echo "  Waiting (mostly downloading CUDA wheels from pytorch.org / PyPI)..."
echo ""

# ── Collect results ───────────────────────────────────────────────────────────
FAILED=0

_wait_gpu() {
  local label="$1" pid="$2" log="$3"
  if wait "${pid}"; then
    echo "  [ok]   ${label}"
    cat "${log}"
  else
    echo "  [FAIL] ${label} — log below:"
    cat "${log}"
    FAILED=1
  fi
}

_wait_gpu "py311" "${PID311}" /tmp/gpu-py311.log
_wait_gpu "py312" "${PID312}" /tmp/gpu-py312.log
_wait_gpu "py313" "${PID313}" /tmp/gpu-py313.log

if [[ "${FAILED}" -ne 0 ]]; then
  echo ""
  echo "ERROR: One or more GPU pro env builds failed (see logs above)."
  exit 1
fi

echo ""
echo "=== Updating pyspark wrapper scripts to point to pro envs ==="

# Overwrite the base-env wrappers so pyspark311/312/313 use the GPU pro venvs.
for ver_env in "311:/opt/nix/envs/pro" "312:/opt/nix/envs/pro-py312" "313:/opt/nix/envs/pro-py313"; do
  ver="${ver_env%%:*}"
  env_path="${ver_env##*:}"
  sudo tee "/usr/local/bin/pyspark${ver}" >/dev/null <<WRAPPER
#!/bin/sh
JAVA_HOME=/opt/nix/langs/java
SPARK_HOME=/opt/nix/langs/spark
SPARK_LOCAL_DIRS=/opt/spark-local
PYSPARK_PYTHON=/usr/local/bin/py${ver}
export JAVA_HOME SPARK_HOME SPARK_LOCAL_DIRS PYSPARK_PYTHON
exec "\${SPARK_HOME}/bin/pyspark" "\$@"
WRAPPER
  sudo chmod 755 "/usr/local/bin/pyspark${ver}"
  echo "  /usr/local/bin/pyspark${ver} -> ${env_path}"
done

# Bare pyspark defaults to pro py311 env on the pro AMI
sudo tee /usr/local/bin/pyspark >/dev/null <<WRAPPER
#!/bin/sh
JAVA_HOME=/opt/nix/langs/java
SPARK_HOME=/opt/nix/langs/spark
SPARK_LOCAL_DIRS=/opt/spark-local
PYSPARK_PYTHON=\${PYSPARK_PYTHON:-/opt/nix/envs/pro/bin/python}
export JAVA_HOME SPARK_HOME SPARK_LOCAL_DIRS PYSPARK_PYTHON
exec "\${SPARK_HOME}/bin/pyspark" "\$@"
WRAPPER
sudo chmod 755 /usr/local/bin/pyspark
echo "  /usr/local/bin/pyspark (default -> pro py311)"

echo ""
echo "GPU pro envs built successfully."
