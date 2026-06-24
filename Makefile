.DEFAULT_GOAL := help
SHELL         := bash -euo pipefail

# ── Packer vars file (optional) ────────────────────────────────────────────────
PKVARS := $(wildcard *.pkrvars.hcl)
PKFLAGS := $(if $(PKVARS),-var-file=$(PKVARS))

.PHONY: help init validate fmt test build-base build-pro build-all \
        build-arm-base build-arm-pro build-arm-all clean

help:
	@echo "CPU DS/ML AMI — available targets"
	@echo ""
	@echo "  init              packer init (download amazon plugin)"
	@echo "  validate          packer validate"
	@echo "  fmt               packer fmt (format HCL in-place)"
	@echo "  test              shellcheck + CIS compliance + trivy CVE scan"
	@echo "  build-base        build the hardened x86 base AMI"
	@echo "  build-pro         build the x86 pro AMI (requires x86 base in same region)"
	@echo "  build-all         build-base then build-pro (x86)"
	@echo "  build-arm-base    build the hardened ARM64/Graviton base AMI"
	@echo "  build-arm-pro     build the ARM64 pro AMI (requires arm64 base in same region)"
	@echo "  build-arm-all     build-arm-base then build-arm-pro"
	@echo "  clean             remove local trivy cache and temp artefacts"
	@echo ""
	@echo "Override vars:  make build-base PKFLAGS='-var spot_price=auto'"

init:
	packer init .

validate: init
	packer validate $(PKFLAGS) .

fmt:
	packer fmt .

test:
	@echo "── shellcheck ─────────────────────────────────────────────────────────"
	shellcheck -S warning harden.sh scripts/ami-finalize.sh scripts/ami-scan.sh \
	           scripts/build-base-envs.sh scripts/build-pro-envs.sh scripts/tune-pro.sh \
	           scripts/smoke-pro.sh scripts/spark-java.sh docker-sim/run-provision.sh
	@echo "── CIS compliance ─────────────────────────────────────────────────────"
	bash tests/cis-check.sh
	@echo "── trivy (HIGH/CRITICAL) ──────────────────────────────────────────────"
	trivy fs --scanners vuln,secret,misconfig --severity HIGH,CRITICAL \
	         --exit-code 1 .

build-base: validate
	packer build $(PKFLAGS) -only=cpu-ds-ml-base.amazon-ebs.ubuntu_base .

build-pro:
	packer build $(PKFLAGS) -only=cpu-ds-ml-pro.amazon-ebs.ubuntu_pro .

build-all: build-base build-pro

build-arm-base: validate
	packer build $(PKFLAGS) -only=cpu-ds-ml-arm64-base.amazon-ebs.ubuntu_arm_base .

build-arm-pro:
	packer build $(PKFLAGS) -only=cpu-ds-ml-arm64-pro.amazon-ebs.ubuntu_arm_pro .

build-arm-all: build-arm-base build-arm-pro

clean:
	rm -rf ~/.cache/trivy /tmp/packer-* /tmp/awscliv2*
