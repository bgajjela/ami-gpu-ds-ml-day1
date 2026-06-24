#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Bharath Kumar Gajjela
# smoke-pro.sh — compute-level validation for the pro AMI.
#
# Runs after tune-pro.sh. Tests that each framework can actually execute
# numerical computation, not just import — catches broken BLAS/OpenBLAS
# linkage, bad wheel builds, and regressions from kernel tuning.
#
# Covers: torch (CPU matmul + autograd), tensorflow (CPU matmul),
#         xgboost (fit/predict), lightgbm (fit/predict), pyspark (session + df).
#
# Usage: sudo /tmp/smoke-pro.sh [/usr/local/bin/py311]
#        If no argument, runs all three versions sequentially.
set -euo pipefail

PYTHONS="${1:-/usr/local/bin/py311 /usr/local/bin/py312 /usr/local/bin/py313}"

# ── Python smoke program ───────────────────────────────────────────────────────
# Written to a temp file to avoid shell-quoting hell and keep it readable.
SMOKE_PY="$(mktemp /tmp/smoke_pro_XXXXXX.py)"
cat > "${SMOKE_PY}" <<'PYEOF'
import sys, time

print(f"Python {sys.version.split()[0]}")

# ── torch CPU ──────────────────────────────────────────────────────────────────
t0 = time.monotonic()
import torch
assert torch.cuda.is_available() is False, "expected CPU-only build"
a = torch.randn(512, 512)
b = torch.mm(a, a.t())
assert b.shape == (512, 512), f"bad shape {b.shape}"

# autograd: verify gradient flows through a simple linear layer
x = torch.randn(64, 128, requires_grad=True)
w = torch.randn(128, 64, requires_grad=True)
loss = torch.mm(x, w).sum()
loss.backward()
assert x.grad is not None and w.grad is not None, "autograd failed"
print(f"  torch {torch.__version__}  matmul+autograd OK  ({time.monotonic()-t0:.1f}s)")

# ── tensorflow CPU ─────────────────────────────────────────────────────────────
t0 = time.monotonic()
import os
os.environ.setdefault("TF_CPP_MIN_LOG_LEVEL", "3")   # suppress TF info spam
import tensorflow as tf
assert not tf.test.is_gpu_available(), "expected CPU-only build"  # type: ignore[attr-defined]
a = tf.random.normal([512, 512])
b = tf.linalg.matmul(a, tf.transpose(a))
assert b.shape == (512, 512), f"bad shape {b.shape}"
print(f"  tensorflow {tf.__version__}  matmul OK  ({time.monotonic()-t0:.1f}s)")

# ── transformers tokenizer round-trip ─────────────────────────────────────────
t0 = time.monotonic()
from tokenizers import Tokenizer, models, pre_tokenizers, trainers
tok = Tokenizer(models.BPE(unk_token="[UNK]"))
tok.pre_tokenizer = pre_tokenizers.ByteLevel(add_prefix_space=False)
trainer = trainers.BpeTrainer(vocab_size=256, special_tokens=["[UNK]"])
tok.train_from_iterator(["hello world", "tokenizer smoke test"], trainer=trainer)
out = tok.encode("hello world")
assert len(out.ids) > 0, "tokenizer produced empty output"
import transformers
print(f"  transformers {transformers.__version__}  tokenizer OK  ({time.monotonic()-t0:.1f}s)")

# ── xgboost ───────────────────────────────────────────────────────────────────
t0 = time.monotonic()
import xgboost as xgb
import numpy as np
rng = np.random.default_rng(42)
X = rng.standard_normal((200, 10))
y = (X[:, 0] > 0).astype(float)
clf = xgb.XGBClassifier(n_estimators=10, max_depth=3, device="cpu", verbosity=0)
clf.fit(X, y)
preds = clf.predict(X)
assert preds.shape == (200,), f"bad pred shape {preds.shape}"
print(f"  xgboost {xgb.__version__}  fit/predict OK  ({time.monotonic()-t0:.1f}s)")

# ── lightgbm ──────────────────────────────────────────────────────────────────
t0 = time.monotonic()
import lightgbm as lgb
ds = lgb.Dataset(X, label=y, free_raw_data=False)
params = {"objective": "binary", "num_leaves": 8, "verbose": -1, "device": "cpu"}
booster = lgb.train(params, ds, num_boost_round=10)
preds_lgb = booster.predict(X)
assert preds_lgb.shape == (200,), f"bad pred shape {preds_lgb.shape}"
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
         .appName("smoke-pro")
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
  echo "=== smoke-pro: ${PY} ==="
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
  echo "ERROR: smoke-pro failed — AMI build aborted."
  exit 1
fi

echo ""
echo "smoke-pro: all versions passed."
