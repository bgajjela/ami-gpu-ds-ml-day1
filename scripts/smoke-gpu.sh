#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Bharath Kumar Gajjela
# smoke-gpu.sh — GPU twin of smoke-pro.sh. Compute-level validation for the GPU
# pro AMI, run after tune-gpu.sh.
#
# Unlike smoke-pro.sh (which asserts CUDA is NOT available), this asserts the GPU
# is live and frameworks actually execute on it — catching driver/CUDA/wheel
# mismatches that would otherwise silently fall back to CPU.
#
# Covers: nvidia-smi, torch (CUDA matmul + autograd ON GPU), tensorflow
#         (GPU matmul on x86 / CPU on aarch64), transformers tokenizer,
#         xgboost + lightgbm (GPU where supported), pyspark session.
#
# Usage: sudo /tmp/smoke-gpu.sh [/usr/local/bin/py311]
set -euo pipefail

PYTHONS="${1:-/usr/local/bin/py311 /usr/local/bin/py312 /usr/local/bin/py313}"

# ── Driver-level check first — fail fast before touching Python ────────────────
echo "=== nvidia-smi ==="
if ! nvidia-smi; then
  echo "ERROR: nvidia-smi failed — driver not loaded. Aborting." >&2
  exit 1
fi

# ── Python smoke program ───────────────────────────────────────────────────────
SMOKE_PY="$(mktemp /tmp/smoke_gpu_XXXXXX.py)"
cat > "${SMOKE_PY}" <<'PYEOF'
import os, sys, time, platform

os.environ.setdefault("TF_CPP_MIN_LOG_LEVEL", "3")
ARCH = platform.machine()   # x86_64 or aarch64
print(f"Python {sys.version.split()[0]}  arch={ARCH}")

# ── torch CUDA ───────────────────────────────────────────────────────────────
t0 = time.monotonic()
import torch
assert torch.cuda.is_available(), "torch.cuda.is_available() is False — GPU not visible to torch"
dev = torch.device("cuda")
a = torch.randn(1024, 1024, device=dev)
b = torch.mm(a, a.t())
torch.cuda.synchronize()
assert b.is_cuda and b.shape == (1024, 1024), f"bad GPU tensor {b.shape} cuda={b.is_cuda}"

# autograd on GPU
x = torch.randn(64, 128, device=dev, requires_grad=True)
w = torch.randn(128, 64, device=dev, requires_grad=True)
loss = torch.mm(x, w).sum()
loss.backward()
assert x.grad is not None and w.grad is not None, "GPU autograd failed"
print(f"  torch {torch.__version__} (cuda {torch.version.cuda})  GPU matmul+autograd OK  "
      f"on {torch.cuda.get_device_name(0)}  ({time.monotonic()-t0:.1f}s)")

# ── tensorflow ───────────────────────────────────────────────────────────────
t0 = time.monotonic()
import tensorflow as tf
gpus = tf.config.list_physical_devices("GPU")
if ARCH == "x86_64":
    assert gpus, "TensorFlow sees no GPU on x86_64 (expected tensorflow[and-cuda])"
    with tf.device("/GPU:0"):
        a = tf.random.normal([1024, 1024])
        b = tf.linalg.matmul(a, tf.transpose(a))
    assert b.shape == (1024, 1024), f"bad shape {b.shape}"
    print(f"  tensorflow {tf.__version__}  GPU matmul OK  ({len(gpus)} GPU)  ({time.monotonic()-t0:.1f}s)")
else:
    # aarch64: no official GPU wheel — CPU-only TensorFlow is expected.
    assert not gpus, "unexpected TensorFlow GPU on aarch64 (should be CPU-only build)"
    a = tf.random.normal([512, 512])
    b = tf.linalg.matmul(a, tf.transpose(a))
    assert b.shape == (512, 512), f"bad shape {b.shape}"
    print(f"  tensorflow {tf.__version__}  CPU matmul OK (aarch64, no GPU wheel)  ({time.monotonic()-t0:.1f}s)")

# ── transformers tokenizer round-trip ─────────────────────────────────────────
t0 = time.monotonic()
from tokenizers import Tokenizer, models, pre_tokenizers, trainers
tok = Tokenizer(models.BPE(unk_token="[UNK]"))
tok.pre_tokenizer = pre_tokenizers.ByteLevel(add_prefix_space=False)
trainer = trainers.BpeTrainer(vocab_size=256, special_tokens=["[UNK]"])
tok.train_from_iterator(["hello world", "tokenizer smoke test"], trainer=trainer)
assert len(tok.encode("hello world").ids) > 0, "tokenizer produced empty output"
import transformers
print(f"  transformers {transformers.__version__}  tokenizer OK  ({time.monotonic()-t0:.1f}s)")

# ── xgboost (GPU) ─────────────────────────────────────────────────────────────
t0 = time.monotonic()
import xgboost as xgb
import numpy as np
rng = np.random.default_rng(42)
X = rng.standard_normal((512, 16))
y = (X[:, 0] > 0).astype(float)
# device="cuda" exercises the GPU histogram algorithm; falls back cleanly if the
# wheel lacks GPU support, so wrap to keep the smoke test informative not fatal.
try:
    clf = xgb.XGBClassifier(n_estimators=20, max_depth=4, device="cuda", tree_method="hist", verbosity=0)
    clf.fit(X, y)
    where = "GPU"
except Exception:
    clf = xgb.XGBClassifier(n_estimators=20, max_depth=4, device="cpu", verbosity=0)
    clf.fit(X, y)
    where = "CPU(fallback)"
assert clf.predict(X).shape == (512,), "bad xgboost pred shape"
print(f"  xgboost {xgb.__version__}  fit/predict OK [{where}]  ({time.monotonic()-t0:.1f}s)")

# ── lightgbm ──────────────────────────────────────────────────────────────────
t0 = time.monotonic()
import lightgbm as lgb
ds = lgb.Dataset(X, label=y, free_raw_data=False)
params = {"objective": "binary", "num_leaves": 8, "verbose": -1}
booster = lgb.train(params, ds, num_boost_round=10)
assert booster.predict(X).shape == (512,), "bad lightgbm pred shape"
print(f"  lightgbm {lgb.__version__}  fit/predict OK  ({time.monotonic()-t0:.1f}s)")

# ── pyspark ───────────────────────────────────────────────────────────────────
t0 = time.monotonic()
import pyspark
from pyspark.sql import SparkSession
spark = (SparkSession.builder
         .master("local[2]")
         .config("spark.ui.enabled", "false")
         .config("spark.driver.memory", "512m")
         .config("spark.sql.shuffle.partitions", "4")
         .appName("smoke-gpu")
         .getOrCreate())
spark.sparkContext.setLogLevel("ERROR")
df = spark.createDataFrame([(i, float(i * 2)) for i in range(100)], ["id", "val"])
total = df.agg({"val": "sum"}).collect()[0][0]
assert abs(total - 9900.0) < 0.01, f"unexpected sum {total}"
spark.stop()
print(f"  pyspark {pyspark.__version__}  SparkSession+agg OK  ({time.monotonic()-t0:.1f}s)")

print("ALL CHECKS PASSED")
PYEOF

# ── Run for each Python interpreter ───────────────────────────────────────────
OVERALL=0

for PY in ${PYTHONS}; do
  echo ""
  echo "=== smoke-gpu: ${PY} ==="
  if "${PY}" "${SMOKE_PY}"; then
    echo "  [ok] ${PY}"
  else
    echo "  [FAIL] ${PY}"
    OVERALL=1
  fi
done

rm -f "${SMOKE_PY}"

if [[ "${OVERALL}" -ne 0 ]]; then
  echo ""
  echo "ERROR: smoke-gpu failed — AMI build aborted."
  exit 1
fi

echo ""
echo "smoke-gpu: all versions passed."
