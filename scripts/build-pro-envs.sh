#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Bharath Kumar Gajjela
# build-pro-envs.sh — creates pro Python envs layered on top of the base Nix envs.
#
# Strategy: venv --system-site-packages inherits base packages (numpy, pandas,
# pyspark, scikit-learn, etc.) from the immutable Nix env, then pip installs
# the heavy DL packages via pre-built CPU wheels. This is 10-20x faster than
# Nix compiling torch/tensorflow from source.
#
# All three Python versions run in parallel: ~15-20 min total (was ~45-60 min
# sequential).
#
# x86_64: PyTorch CPU from the WHL index (~200 MB/version, no CUDA overhead).
# aarch64: PyPI directly — the WHL index has incomplete ARM64 coverage for
#   torchvision/torchaudio; --index-url would replace PyPI and silently fail.
#   PyPI hosts first-class aarch64 wheels for all packages since PyTorch 2.1+.
# tensorflow-cpu: PyPI on both arches (unified package since TF 2.16; the
#   -cpu suffix is a metapackage alias that works on both x86_64 and aarch64).
set -euo pipefail

TORCH_INDEX="https://download.pytorch.org/whl/cpu"
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
_build_pro() {
  local label="$1" base_env="$2" pro_env="$3" wrapper_dst="$4"
  local runtime_lib_path smoke_wrapper pro_site base_site cache_site

  echo "=== [${label}] ${base_env} -> ${pro_env} (arch: ${ARCH}) ==="

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

  echo "  [${label}] torch (CPU wheels)..."
  if [ "${ARCH}" = "x86_64" ]; then
    # WHL index: smaller download, no CUDA wheels pulled in
    _pip_invoke "${pro_env}/bin/pip" install \
      torch torchvision torchaudio \
      --index-url "${TORCH_INDEX}" \
      --quiet
  else
    # ARM64: PyPI has first-class aarch64 wheels; WHL index coverage is incomplete
    _pip_invoke "${pro_env}/bin/pip" install \
      torch torchvision torchaudio \
      --quiet
  fi

  echo "  [${label}] tensorflow-cpu + ecosystem..."
  _pip_invoke "${pro_env}/bin/pip" install \
    tensorflow-cpu \
    transformers datasets tokenizers sentencepiece accelerate \
    --quiet

  echo "  [${label}] mlflow, xgboost, lightgbm..."
  _pip_invoke "${pro_env}/bin/pip" install mlflow xgboost lightgbm --quiet

  echo "  [${label}] smoke test..."
  runtime_lib_path="$(_runtime_lib_path)"
  smoke_wrapper="${PIP_TMPDIR}/${label}-smoke-python"
  _write_python_wrapper "${pro_env}/bin/python" "${smoke_wrapper}" "${runtime_lib_path}"
  "${smoke_wrapper}" -c "
import numpy, pandas, pyspark, sklearn
import torch, tensorflow, transformers, mlflow, xgboost, lightgbm
print('  numpy=' + numpy.__version__ + ' torch=' + torch.__version__ + \
      ' tf=' + tensorflow.__version__ + ' mlflow=' + mlflow.__version__)
"
  sudo rm -f "${smoke_wrapper}"
  sudo chmod -R a+rX "${pro_env}"
  _write_python_wrapper "${pro_env}/bin/python" "${wrapper_dst}" "${runtime_lib_path}"
  echo "  [${label}] wrapper: ${wrapper_dst} -> ${pro_env}/bin/python"
  echo "=== [${label}] DONE ==="
}

# ── Launch all three versions in parallel ─────────────────────────────────────
echo "=== Building pro envs in parallel (py311 / py312 / py313) ==="

_build_pro "py311" /opt/nix/envs/base       /opt/nix/envs/pro       /usr/local/bin/py311 \
  >"/tmp/pro-py311.log" 2>&1 &
PID311=$!

_build_pro "py312" /opt/nix/envs/base-py312 /opt/nix/envs/pro-py312 /usr/local/bin/py312 \
  >"/tmp/pro-py312.log" 2>&1 &
PID312=$!

_build_pro "py313" /opt/nix/envs/base-py313 /opt/nix/envs/pro-py313 /usr/local/bin/py313 \
  >"/tmp/pro-py313.log" 2>&1 &
PID313=$!

echo "  py311 pid=${PID311}  py312 pid=${PID312}  py313 pid=${PID313}"
echo "  Waiting (mostly downloading wheels from PyPI / pytorch.org)..."
echo ""

# ── Collect results ───────────────────────────────────────────────────────────
FAILED=0

_wait_pro() {
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

_wait_pro "py311" "${PID311}" /tmp/pro-py311.log
_wait_pro "py312" "${PID312}" /tmp/pro-py312.log
_wait_pro "py313" "${PID313}" /tmp/pro-py313.log

if [[ "${FAILED}" -ne 0 ]]; then
  echo ""
  echo "ERROR: One or more pro env builds failed (see logs above)."
  exit 1
fi

echo ""
echo "=== Updating pyspark wrapper scripts to point to pro envs ==="

# Overwrite the base-env wrappers created by build-base-envs.sh so that
# pyspark311/312/313 use the pro venvs (torch/tf/transformers included).
# pyspark (bare) also updated to default to pro env.
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
echo "Pro envs built successfully."
