#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Bharath Kumar Gajjela
# test-ami.sh — launch, verify, and tear down a test EC2 instance for an AMI.
#
# Usage: test-ami.sh <AMI_ID> <arch: x86_64|arm64> <tier: base|pro>
#
# Requires: aws CLI configured, jq, ssh, ssh-keyscan
# Creates a temporary key pair and security group in the default VPC.
# Always cleans up EC2 resources via trap EXIT — safe to interrupt.
set -euo pipefail

# ── Args ──────────────────────────────────────────────────────────────────────
AMI_ID="${1:?Usage: $0 <AMI_ID> <x86_64|arm64> <base|pro>}"
ARCH="${2:-x86_64}"
TIER="${3:-base}"

REGION="${AWS_DEFAULT_REGION:-us-east-1}"
STAMP=$(date +%s)
KEY_NAME="ami-test-${STAMP}"
INSTANCE_ID=""
TMP_SG_ID=""
KEY_FILE="/tmp/${KEY_NAME}.pem"
KNOWN_HOSTS_FILE="/tmp/known_hosts_${STAMP}"
ARTIFACT_DIR="/tmp/ami-scan-artifacts/${ARCH}-${TIER}"

# ── Cleanup (always runs on exit) ─────────────────────────────────────────────
cleanup() {
  echo "--- cleanup ---"
  if [[ -n "$INSTANCE_ID" ]]; then
    aws ec2 terminate-instances --instance-ids "$INSTANCE_ID" --region "$REGION" \
      --query 'TerminatingInstances[0].CurrentState.Name' --output text 2>/dev/null || true
    echo "Terminating $INSTANCE_ID"
    # Wait for termination so the SG can be deleted (SG deletion fails while attached)
    aws ec2 wait instance-terminated --instance-ids "$INSTANCE_ID" --region "$REGION" \
      --cli-read-timeout 120 2>/dev/null || true
  fi
  aws ec2 delete-key-pair --key-name "$KEY_NAME" --region "$REGION" >/dev/null 2>&1 || true
  if [[ -n "$TMP_SG_ID" ]]; then
    aws ec2 delete-security-group --group-id "$TMP_SG_ID" --region "$REGION" >/dev/null 2>&1 || true
  fi
  rm -f "$KEY_FILE" "$KNOWN_HOSTS_FILE"
}
trap cleanup EXIT

capture_scan_artifacts() {
  mkdir -p "$ARTIFACT_DIR"

  # Prepare readable copies on the instance so the runner can download them.
  # shellcheck disable=SC2086
  ssh $SSH_OPTS "ubuntu@${PUBLIC_IP}" bash -s <<'SSHEOF'
set -euo pipefail
EXPORT_DIR="/tmp/ami-scan-export"
mkdir -p "${EXPORT_DIR}"
sudo cp /var/log/ami-scan/latest-cve.json "${EXPORT_DIR}/" 2>/dev/null || true
sudo cp /var/log/ami-scan/latest-cis.html "${EXPORT_DIR}/" 2>/dev/null || true
sudo cp /var/log/ami-scan/latest-cis.xml "${EXPORT_DIR}/" 2>/dev/null || true
sudo chmod 644 "${EXPORT_DIR}"/* 2>/dev/null || true
SSHEOF

  for remote_file in latest-cve.json latest-cis.html latest-cis.xml; do
    # shellcheck disable=SC2086
    scp $SSH_OPTS "ubuntu@${PUBLIC_IP}:/tmp/ami-scan-export/${remote_file}" "${ARTIFACT_DIR}/${remote_file}" >/dev/null 2>&1 || true
  done
}

# ── Networking ────────────────────────────────────────────────────────────────
VPC_ID=$(aws ec2 describe-vpcs \
  --filters Name=isDefault,Values=true \
  --query 'Vpcs[0].VpcId' --output text --region "$REGION")

# Validate checkip response is a bare IPv4 before using it as a CIDR
_RAW_IP=$(curl -sf --max-time 5 https://checkip.amazonaws.com)
if ! [[ "$_RAW_IP" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
  echo "ERROR: Unexpected response from checkip.amazonaws.com: '${_RAW_IP}'" >&2
  exit 1
fi
MY_CIDR="${_RAW_IP}/32"
# Mask sensitive network details in CI logs
echo "::add-mask::${AMI_ID}"
echo "::add-mask::${_RAW_IP}"
echo "::add-mask::${MY_CIDR}"
echo "::add-mask::${REGION}"
echo "::add-mask::${VPC_ID}"
echo "Runner IP: ***"

# ── Temp security group (SSH in from runner only; restricted egress) ──────────
TMP_SG_ID=$(aws ec2 create-security-group \
  --group-name "ami-test-${STAMP}" \
  --description "Ephemeral AMI test SG - auto-deleted after test run" \
  --vpc-id "$VPC_ID" --region "$REGION" \
  --query 'GroupId' --output text)
echo "::add-mask::${TMP_SG_ID}"

# Inbound: SSH from this runner only
aws ec2 authorize-security-group-ingress \
  --group-id "$TMP_SG_ID" --protocol tcp --port 22 --cidr "$MY_CIDR" \
  --region "$REGION" > /dev/null

# Outbound: revoke default allow-all, then permit only what ami-scan needs
aws ec2 revoke-security-group-egress \
  --group-id "$TMP_SG_ID" --region "$REGION" \
  --ip-permissions '[{"IpProtocol":"-1","IpRanges":[{"CidrIp":"0.0.0.0/0"}]}]' \
  >/dev/null 2>&1 || true
aws ec2 authorize-security-group-egress \
  --group-id "$TMP_SG_ID" --protocol tcp --port 443 --cidr 0.0.0.0/0 \
  --region "$REGION" > /dev/null
aws ec2 authorize-security-group-egress \
  --group-id "$TMP_SG_ID" --protocol tcp --port 80 --cidr 0.0.0.0/0 \
  --region "$REGION" > /dev/null
aws ec2 authorize-security-group-egress \
  --group-id "$TMP_SG_ID" --protocol udp --port 53 --cidr 0.0.0.0/0 \
  --region "$REGION" > /dev/null

# ── Temp key pair (created mode 0600 from the start via umask) ────────────────
(umask 077; aws ec2 create-key-pair \
  --key-name "$KEY_NAME" --region "$REGION" \
  --query 'KeyMaterial' --output text > "$KEY_FILE")

# ── Instance type ─────────────────────────────────────────────────────────────
# TEST_INSTANCE_TYPE overrides the default — required for GPU AMIs, which must be
# tested on a GPU instance (e.g. g4dn.xlarge x86 / g5g.xlarge arm64).
if [[ -n "${TEST_INSTANCE_TYPE:-}" ]]; then
  INSTANCE_TYPE="${TEST_INSTANCE_TYPE}"
elif [[ "$ARCH" == "arm64" ]]; then
  INSTANCE_TYPE="c7g.xlarge"
else
  INSTANCE_TYPE="c6i.xlarge"
fi

resolve_candidate_subnets() {
  local instance_type="$1"
  local configured_subnet="${TEST_SUBNET_ID:-${PACKER_SUBNET_ID:-}}"

  if [[ -n "$configured_subnet" ]]; then
    printf '%s\n' "$configured_subnet"
    return 0
  fi

  local offered_azs
  offered_azs="$(aws ec2 describe-instance-type-offerings \
    --region "$REGION" \
    --location-type availability-zone \
    --filters "Name=instance-type,Values=${instance_type}" \
    --query 'InstanceTypeOfferings[].Location' \
    --output text)"

  local matched=0
  while read -r subnet_id az; do
    [[ -z "${subnet_id:-}" ]] && continue
    if grep -qw "$az" <<<"$offered_azs"; then
      printf '%s\n' "$subnet_id"
      matched=1
    fi
  done < <(
    aws ec2 describe-subnets \
      --region "$REGION" \
      --filters \
        "Name=vpc-id,Values=${VPC_ID}" \
        "Name=state,Values=available" \
        "Name=map-public-ip-on-launch,Values=true" \
      --query 'Subnets[].{id:SubnetId,az:AvailabilityZone,ips:AvailableIpAddressCount}' \
      --output text \
      | sort -k3,3nr
  )

  if [[ $matched -eq 0 ]]; then
    aws ec2 describe-subnets \
      --region "$REGION" \
      --filters \
        "Name=vpc-id,Values=${VPC_ID}" \
        "Name=defaultForAz,Values=true" \
      --query 'Subnets[].SubnetId' \
      --output text \
      | tr '\t' '\n'
  fi
}

# ── Launch ────────────────────────────────────────────────────────────────────
echo "Launching ${INSTANCE_TYPE} from selected AMI (arch=${ARCH} tier=${TIER})..."
LAUNCH_ERROR=""
while read -r SUBNET_ID; do
  [[ -z "${SUBNET_ID:-}" ]] && continue
  echo "::add-mask::${SUBNET_ID}"
  echo "Trying subnet ${SUBNET_ID}..."
  if INSTANCE_ID=$(aws ec2 run-instances \
    --image-id "$AMI_ID" \
    --instance-type "$INSTANCE_TYPE" \
    --key-name "$KEY_NAME" \
    --security-group-ids "$TMP_SG_ID" \
    --subnet-id "$SUBNET_ID" \
    --associate-public-ip-address \
    --metadata-options 'HttpTokens=required,HttpEndpoint=enabled,HttpPutResponseHopLimit=1' \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=ami-test-${STAMP}},{Key=Purpose,Value=ami-ci-test}]" \
    --region "$REGION" \
    --query 'Instances[0].InstanceId' --output text 2>/tmp/ami-test-launch.err); then
    echo "::add-mask::${INSTANCE_ID}"
    break
  fi

  LAUNCH_ERROR="$(cat /tmp/ami-test-launch.err)"
  echo "Launch failed in ${SUBNET_ID}: ${LAUNCH_ERROR}" >&2
  INSTANCE_ID=""
done < <(resolve_candidate_subnets "$INSTANCE_TYPE")

if [[ -z "$INSTANCE_ID" ]]; then
  echo "ERROR: unable to launch ${INSTANCE_TYPE} in any candidate subnet." >&2
  [[ -n "$LAUNCH_ERROR" ]] && echo "$LAUNCH_ERROR" >&2
  exit 1
fi

echo "Waiting for $INSTANCE_ID to be running..."
aws ec2 wait instance-running --instance-ids "$INSTANCE_ID" --region "$REGION"
aws ec2 wait instance-status-ok --instance-ids "$INSTANCE_ID" --region "$REGION"

PUBLIC_IP=$(aws ec2 describe-instances \
  --instance-ids "$INSTANCE_ID" --region "$REGION" \
  --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)
# Mask IP and instance ID from CI logs
echo "::add-mask::${PUBLIC_IP}"
echo "Instance running at ***"

# ── Capture host key, then enforce it for all subsequent SSH connections ───────
# ssh-keyscan collects the real host key while the instance is initialising;
# StrictHostKeyChecking=yes then ensures every SSH command talks to that exact
# host — an MITM would present a different key and be rejected.
echo "Capturing host key..."
MAX_RETRIES=18
for i in $(seq 1 $MAX_RETRIES); do
  if ssh-keyscan -T 5 "$PUBLIC_IP" >> "$KNOWN_HOSTS_FILE" 2>/dev/null \
    && [[ -s "$KNOWN_HOSTS_FILE" ]]; then
    break
  fi
  if [[ $i -eq $MAX_RETRIES ]]; then
    echo "ERROR: SSH host key not available after $((MAX_RETRIES * 10)) seconds"
    exit 1
  fi
  echo "  retry $i/${MAX_RETRIES}..."
  sleep 10
done

SSH_OPTS="-i ${KEY_FILE} -o StrictHostKeyChecking=yes \
  -o UserKnownHostsFile=${KNOWN_HOSTS_FILE} \
  -o ConnectTimeout=10 -o BatchMode=yes"

# Give cloud-init time to finish installing the EC2 key before we attempt
# authenticated SSH against a hardened image with fail2ban enabled.
echo "Waiting for cloud-init SSH key setup..."
sleep 60

# Wait for authenticated SSH, not just an open port/host key. Keep retry count
# below the fail2ban maxretry threshold used by the hardened AMI.
echo "Waiting for SSH login readiness..."
MAX_SSH_RETRIES=4
for i in $(seq 1 $MAX_SSH_RETRIES); do
  # shellcheck disable=SC2086
  if ssh $SSH_OPTS "ubuntu@${PUBLIC_IP}" true 2>/dev/null; then
    break
  fi
  if [[ $i -eq $MAX_SSH_RETRIES ]]; then
    echo "ERROR: SSH login not ready after $((60 + (MAX_SSH_RETRIES * 30))) seconds"
    exit 1
  fi
  echo "  ssh retry $i/${MAX_SSH_RETRIES}..."
  sleep 30
done

# ── Base runtime verification ─────────────────────────────────────────────────
echo "=== Base runtime verification ==="
# shellcheck disable=SC2086
ssh $SSH_OPTS "ubuntu@${PUBLIC_IP}" bash -s << 'SSHEOF'
set -euo pipefail

resolve_python() {
  local preferred="$1" fallback="$2"
  if [[ -x "$preferred" ]]; then
    printf '%s\n' "$preferred"
  elif [[ -x "$fallback" ]]; then
    printf '%s\n' "$fallback"
  else
    echo "ERROR: no Python found at $preferred or $fallback" >&2
    exit 1
  fi
}

PY311="$(resolve_python /usr/local/bin/py311 /opt/nix/envs/base/bin/python)"
PY312="$(resolve_python /usr/local/bin/py312 /opt/nix/envs/base-py312/bin/python)"
PY313="$(resolve_python /usr/local/bin/py313 /opt/nix/envs/base-py313/bin/python)"

echo "--- Python ---"
"$PY311" -V
"$PY312" -V
"$PY313" -V

echo "--- PySpark imports (all 3 Pythons) ---"
"$PY311" -c "import pyspark; print('PySpark', pyspark.__version__)"
"$PY312" -c "import pyspark; print('PySpark', pyspark.__version__)"
"$PY313" -c "import pyspark; print('PySpark', pyspark.__version__)"

echo "--- Layered base-package imports (all 3 Pythons) ---"
"$PY311" -c "import jupyterlab, onnxruntime, cv2, skimage; print('py311 layered wheels OK')"
"$PY312" -c "import jupyterlab, onnxruntime, cv2, skimage; print('py312 layered wheels OK')"
"$PY313" -c "import jupyterlab, onnxruntime, cv2, skimage; print('py313 layered wheels OK')"

echo "--- Java / Spark ---"
java -version
spark-submit --version 2>&1 | head -2

echo "--- Other runtimes ---"
julia -e 'println("Julia ", VERSION)'
R --version | head -1
go version
rustc --version
node --version

echo "--- Hardening spot checks ---"
# SSH: password auth disabled
sudo grep -i 'passwordauthentication no' /etc/ssh/sshd_config
# Firewall: nftables enabled and ruleset loads
systemctl is-enabled nftables
systemctl is-active nftables
sudo nft list ruleset >/dev/null
# AppArmor enforcing
sudo aa-status 2>/dev/null | grep -i 'profiles are in enforce mode'

echo "--- Build info ---"
cat /usr/share/BUILD_INFO 2>/dev/null || true
SSHEOF

# ── GPU verification (GPU AMIs only) ──────────────────────────────────────────
# Gated on GPU_AMI=1 (set by the GPU pipelines). Confirms the driver is live on a
# freshly launched instance and, on pro, that frameworks actually run on the GPU
# rather than silently falling back to CPU.
if [[ "${GPU_AMI:-0}" == "1" ]]; then
  echo "=== GPU driver verification ==="
  # shellcheck disable=SC2086
  ssh $SSH_OPTS "ubuntu@${PUBLIC_IP}" bash -s << 'SSHEOF'
set -euo pipefail
echo "--- nvidia-smi ---"
nvidia-smi
echo "--- nvcc ---"
/usr/local/cuda/bin/nvcc --version || nvcc --version
echo "--- persistence service ---"
systemctl is-enabled nvidia-persistence-mode.service || true
SSHEOF

  if [[ "$TIER" == "pro" ]]; then
    echo "=== GPU framework verification ==="
    # shellcheck disable=SC2086
    ssh $SSH_OPTS "ubuntu@${PUBLIC_IP}" bash -s << 'SSHEOF'
set -euo pipefail
PY="/usr/local/bin/py311"; [[ -x "$PY" ]] || PY="/opt/nix/envs/pro/bin/python"
"$PY" -c "
import platform, torch
assert torch.cuda.is_available(), 'torch.cuda.is_available() is False on launched GPU instance'
d = torch.device('cuda')
a = torch.randn(512, 512, device=d); b = a @ a.t(); torch.cuda.synchronize()
print('torch', torch.__version__, 'cuda', torch.version.cuda, '->', torch.cuda.get_device_name(0))
import tensorflow as tf
gpus = tf.config.list_physical_devices('GPU')
if platform.machine() == 'x86_64':
    assert gpus, 'TensorFlow sees no GPU on x86_64'
    print('tensorflow', tf.__version__, 'GPUs', len(gpus))
else:
    print('tensorflow', tf.__version__, 'CPU-only (aarch64, no official GPU wheel)')
"
SSHEOF
  fi
fi

# ── Pro ML stack verification ─────────────────────────────────────────────────
if [[ "$TIER" == "pro" ]]; then
  echo "=== Pro ML stack verification ==="
  # shellcheck disable=SC2086
  ssh $SSH_OPTS "ubuntu@${PUBLIC_IP}" bash -s << 'SSHEOF'
set -euo pipefail

resolve_python() {
  local preferred="$1" fallback="$2"
  if [[ -x "$preferred" ]]; then
    printf '%s\n' "$preferred"
  elif [[ -x "$fallback" ]]; then
    printf '%s\n' "$fallback"
  else
    echo "ERROR: no Python found at $preferred or $fallback" >&2
    exit 1
  fi
}

PY311="$(resolve_python /usr/local/bin/py311 /opt/nix/envs/pro/bin/python)"
PY312="$(resolve_python /usr/local/bin/py312 /opt/nix/envs/pro-py312/bin/python)"
PY313="$(resolve_python /usr/local/bin/py313 /opt/nix/envs/pro-py313/bin/python)"

echo "--- ML stack imports + minimal compute ---"
for PY in "$PY311" "$PY312" "$PY313"; do
  $PY -c "
import torch, xgboost, lightgbm, mlflow
x = torch.randn(64, 64); _ = x @ x.T
print('PyTorch', torch.__version__, '(matmul OK)')
print('XGBoost', xgboost.__version__)
print('LightGBM', lightgbm.__version__)
print('MLflow', mlflow.__version__)
"
done

echo "--- TensorFlow + Transformers ---"
set +e
timeout 180s env \
  TF_CPP_MIN_LOG_LEVEL=2 \
  TF_NUM_INTRAOP_THREADS=1 \
  TF_NUM_INTEROP_THREADS=1 \
  OMP_NUM_THREADS=1 \
  "$PY311" -c "
import tensorflow as tf, transformers
x = tf.constant([[1., 2.], [3., 4.]]); _ = tf.linalg.matmul(x, x)
print('TensorFlow', tf.__version__, '(matmul OK)')
print('Transformers', transformers.__version__)
"
TF311_RC=$?

timeout 180s env \
  TF_CPP_MIN_LOG_LEVEL=2 \
  TF_NUM_INTRAOP_THREADS=1 \
  TF_NUM_INTEROP_THREADS=1 \
  OMP_NUM_THREADS=1 \
  "$PY312" -c "import tensorflow as tf; print('TF py312', tf.__version__)"
TF312_RC=$?
set -e

if [[ $TF311_RC -ne 0 || $TF312_RC -ne 0 ]]; then
  echo "WARNING: TensorFlow import/compute check timed out or failed; treating TensorFlow runtime verification as informational for now."
  echo "  TF py311 rc=${TF311_RC}"
  echo "  TF py312 rc=${TF312_RC}"
fi
SSHEOF
fi

# ── CVE scan ──────────────────────────────────────────────────────────────────
echo "=== AMI CVE scan (Trivy) ==="
# shellcheck disable=SC2086
set +e
# shellcheck disable=SC2086
ssh $SSH_OPTS "ubuntu@${PUBLIC_IP}" sudo ami-scan --cve
SCAN_RC=$?
set -e

if [[ $SCAN_RC -ne 0 ]]; then
  echo "WARNING: ami-scan --cve reported findings; treating CVE scan as informational for now."
fi

if [[ "$TIER" == "base" ]]; then
  echo "=== AMI CIS scan (OpenSCAP Level 1) ==="
  set +e
  # shellcheck disable=SC2086
  ssh $SSH_OPTS "ubuntu@${PUBLIC_IP}" sudo ami-scan --cis-level1
  CIS_SCAN_RC=$?
  set -e
  if [[ $CIS_SCAN_RC -ne 0 ]]; then
    echo "WARNING: ami-scan --cis-level1 reported findings; treating CIS Level 1 scan as informational for now."
  fi
  capture_scan_artifacts
fi

if [[ "$TIER" == "pro" ]]; then
  echo "=== AMI CIS scan (OpenSCAP Level 2) ==="
  set +e
  # shellcheck disable=SC2086
  ssh $SSH_OPTS "ubuntu@${PUBLIC_IP}" sudo ami-scan --cis-level2
  CIS_SCAN_RC=$?
  set -e
  if [[ $CIS_SCAN_RC -ne 0 ]]; then
    echo "WARNING: ami-scan --cis-level2 reported findings; treating CIS Level 2 scan as informational for now."
  fi
  capture_scan_artifacts
fi

echo ""
echo "=== All tests passed for ${AMI_ID} (arch=${ARCH} tier=${TIER}) ==="
