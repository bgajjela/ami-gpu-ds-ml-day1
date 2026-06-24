# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Bharath Kumar Gajjela
packer {
  required_plugins {
    amazon = { source = "github.com/hashicorp/amazon", version = "~> 1.7.0" }
  }
}

variable "region" { default = "us-east-1" }
# Pro builds layer on top of the base AMI. Pass the base AMI ID explicitly
# rather than using a data source — Packer evaluates all data sources at
# startup regardless of -only, which causes failures on first run when no
# base AMI exists yet.
# Pipeline sets this automatically from the base build job output.
# Manual usage: packer build -only=cpu-ds-ml-pro -var "base_ami_id=ami-xxx" .
variable "base_ami_id"     { default = "" }
variable "base_ami_id_arm" { default = "" }

locals {
  base_name     = "cpu-ds-ml-ubuntu-2204"
  arm_base_name = "cpu-ds-ml-ubuntu-2204-arm64"
}

# -------- Sources (one per AMI so we can set names/descriptions) --------
source "amazon-ebs" "ubuntu_base" {
  region                      = var.region
  ssh_username                = "ubuntu"
  instance_type               = var.instance_type
  spot_price                  = var.spot_price
  subnet_id                   = var.subnet_id != "" ? var.subnet_id : null  # Auto-select if not provided
  security_group_id           = var.security_group_id != "" ? var.security_group_id : null
  associate_public_ip_address = var.associate_public_ip
  ami_regions                 = var.additional_regions

  # Enforce IMDSv2: prevents SSRF attacks from stealing EC2 role credentials via IMDSv1
  metadata_options {
    http_tokens                 = "required"
    http_endpoint               = "enabled"
    http_put_response_hop_limit = 1
  }

  # Wire EBS encryption variables declared at the bottom of this file
  # Marketplace AMIs must not be encrypted at the AMI level — AWS cannot copy
  # account-specific KMS keys across accounts or regions for distribution.
  # Customers can encrypt their own EBS volumes at launch if required.

  source_ami_filter {
    owners      = ["099720109477"] # Canonical
    most_recent = true
    filters = {
      name                = "ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"
      virtualization-type = "hvm"
      root-device-type    = "ebs"
    }
  }

  launch_block_device_mappings {
    device_name           = "/dev/sda1"
    volume_size           = var.root_volume_size
    volume_type           = "gp3"
    delete_on_termination = true
  }

  ami_name        = "${local.base_name}-base-{{timestamp}}"
  ami_description = "CPU DS/ML AMI (Base) - Ubuntu 22.04, pinned minimal stack, CIS-style hardened"
  tags = { Name = "${local.base_name}-base", Role = "dsml" }
}

source "amazon-ebs" "ubuntu_pro" {
  region                      = var.region
  ssh_username                = "ubuntu"
  instance_type               = var.instance_type
  spot_price                  = var.spot_price
  subnet_id                   = var.subnet_id != "" ? var.subnet_id : null  # Auto-select if not provided
  security_group_id           = var.security_group_id != "" ? var.security_group_id : null
  associate_public_ip_address = var.associate_public_ip
  ami_regions                 = var.additional_regions

  # Start from the already-hardened base AMI — avoids repeating ~1.5h of work
  # (apt upgrade, hardening, Nix setup, Julia/R/Go/Java/Spark, base Python envs).
  source_ami = var.base_ami_id

  # Enforce IMDSv2: prevents SSRF attacks from stealing EC2 role credentials via IMDSv1
  metadata_options {
    http_tokens                 = "required"
    http_endpoint               = "enabled"
    http_put_response_hop_limit = 1
  }

  # Marketplace AMIs must not be encrypted at the AMI level — AWS cannot copy
  # account-specific KMS keys across accounts or regions for distribution.
  # Customers can encrypt their own EBS volumes at launch if required.

  launch_block_device_mappings {
    device_name           = "/dev/sda1"
    volume_size           = var.root_volume_size
    volume_type           = "gp3"
    delete_on_termination = true
  }

  ami_name        = "${local.base_name}-pro-{{timestamp}}"
  ami_description = "CPU DS/ML AMI (Pro) - Ubuntu 22.04, full DL stack (torch/tf/transformers), CIS-hardened"
  tags = { Name = "${local.base_name}-pro", Role = "dsml" }
}

# -------- ARM64 / Graviton sources --------

source "amazon-ebs" "ubuntu_arm_base" {
  region                      = var.region
  ssh_username                = "ubuntu"
  instance_type               = var.arm_instance_type
  spot_price                  = var.spot_price
  subnet_id                   = var.subnet_id != "" ? var.subnet_id : null  # Auto-select if not provided
  security_group_id           = var.security_group_id != "" ? var.security_group_id : null
  associate_public_ip_address = var.associate_public_ip
  ami_regions                 = var.additional_regions

  # Enforce IMDSv2
  metadata_options {
    http_tokens                 = "required"
    http_endpoint               = "enabled"
    http_put_response_hop_limit = 1
  }

  # Marketplace AMIs must not be encrypted at the AMI level — AWS cannot copy
  # account-specific KMS keys across accounts or regions for distribution.
  # Customers can encrypt their own EBS volumes at launch if required.

  source_ami_filter {
    owners      = ["099720109477"] # Canonical
    most_recent = true
    filters = {
      name                = "ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-arm64-server-*"
      virtualization-type = "hvm"
      root-device-type    = "ebs"
    }
  }

  launch_block_device_mappings {
    device_name           = "/dev/sda1"
    volume_size           = var.root_volume_size
    volume_type           = "gp3"
    delete_on_termination = true
  }

  ami_name        = "${local.arm_base_name}-base-{{timestamp}}"
  ami_description = "CPU DS/ML AMI (Base, ARM64/Graviton) - Ubuntu 22.04, pinned minimal stack, CIS-style hardened"
  tags = { Name = "${local.arm_base_name}-base", Role = "dsml" }
}

source "amazon-ebs" "ubuntu_arm_pro" {
  region                      = var.region
  ssh_username                = "ubuntu"
  instance_type               = var.arm_instance_type
  spot_price                  = var.spot_price
  subnet_id                   = var.subnet_id != "" ? var.subnet_id : null  # Auto-select if not provided
  security_group_id           = var.security_group_id != "" ? var.security_group_id : null
  associate_public_ip_address = var.associate_public_ip
  ami_regions                 = var.additional_regions

  # Start from the already-hardened ARM base AMI
  source_ami = var.base_ami_id_arm

  # Enforce IMDSv2
  metadata_options {
    http_tokens                 = "required"
    http_endpoint               = "enabled"
    http_put_response_hop_limit = 1
  }

  # Marketplace AMIs must not be encrypted at the AMI level — AWS cannot copy
  # account-specific KMS keys across accounts or regions for distribution.
  # Customers can encrypt their own EBS volumes at launch if required.

  launch_block_device_mappings {
    device_name           = "/dev/sda1"
    volume_size           = var.root_volume_size
    volume_type           = "gp3"
    delete_on_termination = true
  }

  ami_name        = "${local.arm_base_name}-pro-{{timestamp}}"
  ami_description = "CPU DS/ML AMI (Pro, ARM64/Graviton) - Ubuntu 22.04, full DL stack (torch/tf/transformers), CIS-hardened"
  tags = { Name = "${local.arm_base_name}-pro", Role = "dsml" }
}

# =======================
# BASE IMAGE (minimal)
# =======================
build {
  name    = "cpu-ds-ml-base"
  sources = ["source.amazon-ebs.ubuntu_base"]

  # Reboot after kernel upgrade so the patched kernel is running when the AMI
  # is snapshotted. Without this, apt-get upgrade installs a new kernel package
  # but the old kernel remains active — CVE patches that require a new kernel
  # (e.g. CVE-2026-31431) are installed but not yet effective in the AMI.
  provisioner "shell" {
    # Hardened /tmp is noexec after the kernel reboot; run the wrapper via
    # bash so the interpreter reads it (no exec() on the noexec file).
    execute_command = "chmod +x {{ .Path }}; {{ .Vars }} bash {{ .Path }}"
    inline = [
      "sudo apt-get update",
      # Apply all Ubuntu security patches (OpenSSL, curl, glibc, systemd, etc.) before installing anything
      "sudo DEBIAN_FRONTEND=noninteractive apt-get upgrade -y",
      # Reboot into the patched kernel before continuing — ensures kernel-level CVE
      # fixes (e.g. CVE-2026-31431 algif_aead) are active in the final AMI snapshot
      "sudo reboot || true",
    ]
    expect_disconnect = true
  }

  provisioner "shell" {
    # Hardened /tmp is noexec after the kernel reboot; run the wrapper via
    # bash so the interpreter reads it (no exec() on the noexec file).
    execute_command = "chmod +x {{ .Path }}; {{ .Vars }} bash {{ .Path }}"
    pause_before = "30s"
    inline = [
      "echo 'Resumed after reboot — kernel: $(uname -r)'",
      "sudo apt-get update",
      # unzip + gnupg needed for AWS CLI v2 download and PGP verification; awscli (v1, EOL) replaced by v2 below
      "sudo apt-get -y install curl jq git-lfs unzip gnupg build-essential python3-venv ca-certificates xz-utils libstdc++6 libgomp1 software-properties-common",
      "sudo apt-get -y install ufw auditd fail2ban unattended-upgrades logrotate chrony",
      # OpenSCAP scanner comes from Ubuntu repos once universe is enabled.
      # Ubuntu 22.04 SSG content is installed from .deb packages because the
      # current target-image repos do not expose ssg-debderived reliably.
      # amazon-ssm-agent is not in Ubuntu 22.04 apt repos — download .deb directly from AWS
      # amazon-ssm-agent is pre-installed via snap in the base Ubuntu image — no need to install
      # Trivy — pinned version, installed to /usr/local/bin so ami-scan can call it
      "curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sudo sh -s -- -b /usr/local/bin v0.70.0",
      "sudo add-apt-repository main",
      "sudo add-apt-repository universe",
      "sudo apt-get update",
      "sudo apt-get -y install libopenscap8",
      "curl -fsSL -o /tmp/ssg-base.deb http://ftp.sjtu.edu.cn/ubuntu/pool/universe/s/scap-security-guide/ssg-base_0.1.80-1_all.deb",
      "curl -fsSL -o /tmp/ssg-debderived.deb http://ftp.sjtu.edu.cn/ubuntu/pool/universe/s/scap-security-guide/ssg-debderived_0.1.80-1_all.deb",
      "sudo dpkg -i /tmp/ssg-base.deb /tmp/ssg-debderived.deb",
      "rm -f /tmp/ssg-base.deb /tmp/ssg-debderived.deb",
      "command -v oscap >/dev/null",
      "test -f /usr/share/xml/scap/ssg/content/ssg-ubuntu2204-ds.xml",
      "sudo systemctl enable auditd chrony unattended-upgrades",
      "sudo systemctl enable amazon-ssm-agent 2>/dev/null || true",  # Optional, may not have installed
      "sudo sed -i 's/^#PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config",
      "sudo sed -i 's/^#PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config",
      "sudo sshd -t && sudo systemctl reload ssh || true",
      "sudo mkdir -p /opt/venvs /usr/share",
      "mkdir -p /home/ubuntu/packer-assets",
      "sudo chown -R ubuntu:ubuntu /opt/venvs",
      "python3 -m venv /opt/venvs/py311",
      "sudo chmod 755 /opt/venvs/py311",
      # Install AWS CLI v2 with optional PGP signature verification (key: FB5DB77FD5C118B80511ADA8A6310ACC4672475C)
      "curl -fsSL 'https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip' -o /tmp/awscliv2.zip",
      "curl -fsSL 'https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip.sig' -o /tmp/awscliv2.sig",
      "set +e; gpg --keyserver hkps://keys.openpgp.org --recv-keys FB5DB77FD5C118B80511ADA8A6310ACC4672475C 2>/dev/null; gpg --verify /tmp/awscliv2.sig /tmp/awscliv2.zip 2>/dev/null; set -e",
      "unzip -q /tmp/awscliv2.zip -d /tmp",
      "sudo /tmp/aws/install",
      "rm -rf /tmp/awscliv2.zip /tmp/awscliv2.sig /tmp/aws",
      # Pin Nix installer to a specific version to prevent supply-chain risk from unversioned curl|sh
      # Update this pin periodically: https://releases.nixos.org/nix/
      "curl -fsSL -o /tmp/install-nix.sh https://releases.nixos.org/nix/nix-2.24.9/install",
      "yes | sudo -E sh /tmp/install-nix.sh --daemon || true",
      "echo '. /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh' | sudo tee /etc/profile.d/nix.sh",
      "echo '. /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh' | sudo tee -a /home/ubuntu/.profile",
      "sudo chown ubuntu:ubuntu /home/ubuntu/.profile || true",
      "sudo systemctl enable nix-daemon || true",
      "sudo systemctl start nix-daemon || true",
    ]
  }

  # Nix flake for reproducible Python envs (base/pro defined inside flake)
  provisioner "file" {
    source      = "nix/flake.nix"
    destination = "/home/ubuntu/packer-assets/flake.nix"
  }
  provisioner "file" {
    source      = "scripts/spark-java.sh"
    destination = "/home/ubuntu/packer-assets/spark-java.sh"
  }
  provisioner "file" {
    source      = "scripts/build-base-envs.sh"
    destination = "/home/ubuntu/packer-assets/build-base-envs.sh"
  }
  provisioner "file" {
    source      = "scripts/ami-scan.sh"
    destination = "/home/ubuntu/packer-assets/ami-scan.sh"
  }
  provisioner "file" {
    source      = "scripts/fix-level1-base.sh"
    destination = "/home/ubuntu/packer-assets/fix-level1-base.sh"
  }
  provisioner "file" {
    source      = "examples/pyspark_basic.py"
    destination = "/home/ubuntu/packer-assets/pyspark_basic.py"
  }
  provisioner "file" {
    source      = "examples/pyspark_pi.py"
    destination = "/home/ubuntu/packer-assets/pyspark_pi.py"
  }
  # Build all Nix envs + language toolchains BEFORE hardening so /tmp is still
  # exec-able for Nix sandbox operations. Harden runs after to lock down the image.
  provisioner "shell" {
    execute_command = "chmod +x {{ .Path }}; {{ .Vars }} bash {{ .Path }}"
    inline = [
      "sudo mkdir -p /opt/nix/flake",
      "sudo mv /home/ubuntu/packer-assets/flake.nix /opt/nix/flake/flake.nix",
      "sudo bash -lc 'source /etc/profile.d/nix.sh && nix --extra-experimental-features nix-command --extra-experimental-features flakes flake lock /opt/nix/flake'",
      # Configure Cachix binary cache — add substituters + trusted public keys so
      # Nix actually fetches from cache instead of rebuilding from source.
      "echo 'extra-substituters = https://cpu-ds-ml.cachix.org https://nix-community.cachix.org' | sudo tee -a /etc/nix/nix.conf",
      "echo 'trusted-public-keys = cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY= cpu-ds-ml.cachix.org-1:RQU8R11xfczT+AV5+UOJIBinRTQIbFhpn9qmk7f/QbY= nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCUSeBc=' | sudo tee -a /etc/nix/nix.conf",
      "sudo systemctl restart nix-daemon",
      "sudo bash /home/ubuntu/packer-assets/build-base-envs.sh",
      "sudo install -d -m 0755 /usr/share/examples/spark",
      "sudo mv /home/ubuntu/packer-assets/pyspark_basic.py /usr/share/examples/spark/pyspark_basic.py",
      "sudo mv /home/ubuntu/packer-assets/pyspark_pi.py /usr/share/examples/spark/pyspark_pi.py",
      "sudo chmod 0644 /usr/share/examples/spark/pyspark_*.py",
      # Smoke tests: fail fast if any runtime is missing
      "nix --version",
      "/usr/local/bin/py311 -V",
      "/usr/local/bin/py312 -V",
      "/usr/local/bin/py313 -V",
      "/usr/local/bin/py311 -c 'import pyspark; print(pyspark.__version__)'",
      "/usr/local/bin/py312 -c 'import pyspark; print(pyspark.__version__)'",
      "/usr/local/bin/py313 -c 'import pyspark; print(pyspark.__version__)'",
      "java -version",
      "spark-submit --version",
      "julia -e 'println(VERSION)'",
      "R --version",
      "go version",
      "rustc --version",
      "cargo --version",
      "node --version",
      "sudo mkdir -p /usr/share/BUILD_INFO && echo VERSION=1.0.0-BASE | sudo tee /usr/share/BUILD_INFO/version",
    ]
  }

  # CIS hardening — runs AFTER Nix builds so /tmp noexec does not block Nix sandbox.
  # The tmp.mount unit is enabled here (not started); it activates on the next boot,
  # so every instance launched from this AMI runs with a hardened /tmp.
  provisioner "file" {
    source      = "harden.sh"
    destination = "/tmp/harden.sh"
  }
  provisioner "shell" {
    execute_command = "chmod +x {{ .Path }}; {{ .Vars }} bash {{ .Path }}"
    inline = [
      "sudo systemctl daemon-reload",
      "sudo bash /tmp/harden.sh",
      "test -f /home/ubuntu/packer-assets/fix-level1-base.sh && sudo bash /home/ubuntu/packer-assets/fix-level1-base.sh || echo 'fix-level1-base.sh not found'",
      "test -f /home/ubuntu/packer-assets/spark-java.sh && sudo install -m 0644 /home/ubuntu/packer-assets/spark-java.sh /etc/profile.d/spark-java.sh || echo 'spark-java.sh not found, will use defaults'",
      "test -f /home/ubuntu/packer-assets/ami-scan.sh && sudo install -m 0755 /home/ubuntu/packer-assets/ami-scan.sh /usr/local/bin/ami-scan || echo 'ami-scan.sh not found'",
      # Spark local dir on EBS — keeps shuffle data off tmpfs (/tmp is noexec + size-capped)
      "sudo mkdir -p /opt/spark-local && sudo chmod 1777 /opt/spark-local",
    ]
  }

  # Package manifest + legal notices + AMI scrub — MUST be the last provisioner
  provisioner "file" {
    source      = "scripts/ami-finalize.sh"
    destination = "/tmp/ami-finalize.sh"
  }
  provisioner "file" {
    source      = "SECURITY.md"
    destination = "/tmp/SECURITY.md"
  }
  provisioner "shell" {
    # Hardened /tmp is noexec after the kernel reboot; run the wrapper via
    # bash so the interpreter reads it (no exec() on the noexec file).
    execute_command = "chmod +x {{ .Path }}; {{ .Vars }} bash {{ .Path }}"
    inline = ["sudo bash /tmp/ami-finalize.sh base"]
  }

  provisioner "shell" {
    execute_command = "chmod +x {{ .Path }}; {{ .Vars }} bash {{ .Path }}"
    inline = [
      "/usr/local/bin/py311 -c 'import pyspark; print(pyspark.__version__)'",
      "/usr/local/bin/py312 -c 'import pyspark; print(pyspark.__version__)'",
      "/usr/local/bin/py313 -c 'import pyspark; print(pyspark.__version__)'",
      "/usr/local/bin/py311 -c 'import jupyterlab, onnxruntime, cv2, skimage; print(\"py311 final runtime OK\")'",
      "/usr/local/bin/py312 -c 'import jupyterlab, onnxruntime, cv2, skimage; print(\"py312 final runtime OK\")'",
      "/usr/local/bin/py313 -c 'import jupyterlab, onnxruntime, cv2, skimage; print(\"py313 final runtime OK\")'",
    ]
  }
}

# =======================
# PRO IMAGE (layers on base)
# =======================
# Builds from the already-hardened base AMI — no repeated apt-get, hardening,
# Nix setup, Julia/R/Go/Java/Spark, or base Python env work (~1.5h saved).
# Only adds the pro Python venvs (torch/tf/transformers via pip CPU wheels).
build {
  name    = "cpu-ds-ml-pro"
  sources = ["source.amazon-ebs.ubuntu_pro"]

  # Upload pro build scripts
  provisioner "file" {
    source      = "scripts/build-pro-envs.sh"
    destination = "/tmp/build-pro-envs.sh"
  }
  provisioner "file" {
    source      = "scripts/tune-pro.sh"
    destination = "/tmp/tune-pro.sh"
  }
  provisioner "file" {
    source      = "scripts/smoke-pro.sh"
    destination = "/tmp/smoke-pro.sh"
  }
  provisioner "file" {
    source      = "scripts/fix-level2-addon.sh"
    destination = "/tmp/fix-level2-addon.sh"
  }

  provisioner "shell" {
    # Hardened /tmp is noexec after the kernel reboot; run the wrapper via
    # bash so the interpreter reads it (no exec() on the noexec file).
    execute_command = "chmod +x {{ .Path }}; {{ .Vars }} bash {{ .Path }}"
    inline = [
      "sudo chmod +x /tmp/build-pro-envs.sh /tmp/tune-pro.sh /tmp/smoke-pro.sh /tmp/fix-level2-addon.sh",
      # build-pro-envs.sh: venv --system-site-packages on base Nix envs,
      # then pip install torch/tf/transformers CPU wheels (~15-20 min total)
      "sudo bash /tmp/build-pro-envs.sh",
      # tune-pro.sh: ML-specific kernel + THP + limits tuning (run after envs are built)
      "sudo bash /tmp/tune-pro.sh",
      "sudo bash /tmp/fix-level2-addon.sh",
      # Compute smoke tests: torch matmul+autograd, TF matmul, XGBoost/LightGBM fit,
      # PySpark session — verifies BLAS linkage and framework compute, not just imports.
      # Runs all three Python versions. Aborts the build if any check fails.
      "/tmp/smoke-pro.sh",
      # Sanity: symlinks, JVM, Spark still intact after pro layer
      "/usr/local/bin/py311 -V",
      "/usr/local/bin/py312 -V",
      "/usr/local/bin/py313 -V",
      "java -version",
      "spark-submit --version",
      "sudo mkdir -p /usr/share/BUILD_INFO && echo VERSION=1.0.0-PRO | sudo tee /usr/share/BUILD_INFO/version",
    ]
  }

  # Package manifest + legal notices + AMI scrub — MUST be the last provisioner
  provisioner "file" {
    source      = "scripts/ami-finalize.sh"
    destination = "/tmp/ami-finalize.sh"
  }
  provisioner "file" {
    source      = "SECURITY.md"
    destination = "/tmp/SECURITY.md"
  }
  provisioner "shell" {
    # Hardened /tmp is noexec after the kernel reboot; run the wrapper via
    # bash so the interpreter reads it (no exec() on the noexec file).
    execute_command = "chmod +x {{ .Path }}; {{ .Vars }} bash {{ .Path }}"
    inline = ["sudo bash /tmp/ami-finalize.sh pro"]
  }
}

# =======================
# ARM64 BASE IMAGE (minimal)
# =======================
# Identical to the x86 base build; only the source and AWS CLI download differ.
# All scripts (harden.sh, build-base-envs.sh, ami-finalize.sh) are arch-agnostic.
# Nix detects aarch64-linux automatically; the flake supports both architectures.
build {
  name    = "cpu-ds-ml-arm64-base"
  sources = ["source.amazon-ebs.ubuntu_arm_base"]

  provisioner "shell" {
    # Hardened /tmp is noexec after the kernel reboot; run the wrapper via
    # bash so the interpreter reads it (no exec() on the noexec file).
    execute_command = "chmod +x {{ .Path }}; {{ .Vars }} bash {{ .Path }}"
    inline = [
      "sudo apt-get update",
      "sudo DEBIAN_FRONTEND=noninteractive apt-get upgrade -y",
      "sudo reboot || true",
    ]
    expect_disconnect = true
  }

  provisioner "shell" {
    # Hardened /tmp is noexec after the kernel reboot; run the wrapper via
    # bash so the interpreter reads it (no exec() on the noexec file).
    execute_command = "chmod +x {{ .Path }}; {{ .Vars }} bash {{ .Path }}"
    pause_before = "30s"
    inline = [
      "echo 'Resumed after reboot — kernel: $(uname -r)'",
      "sudo apt-get update",
      "sudo apt-get -y install curl jq git-lfs unzip gnupg build-essential python3-venv ca-certificates xz-utils libstdc++6 libgomp1 software-properties-common",
      "sudo apt-get -y install ufw auditd fail2ban unattended-upgrades logrotate chrony",
      # OpenSCAP scanner comes from Ubuntu repos once universe is enabled.
      # Ubuntu 22.04 SSG content is installed from .deb packages because the
      # current target-image repos do not expose ssg-debderived reliably.
      # amazon-ssm-agent is pre-installed via snap in the base Ubuntu image — no need to install
      "curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sudo sh -s -- -b /usr/local/bin v0.70.0",
      "sudo add-apt-repository main",
      "sudo add-apt-repository universe",
      "sudo apt-get update",
      "sudo apt-get -y install libopenscap8",
      "curl -fsSL -o /tmp/ssg-base.deb http://ftp.sjtu.edu.cn/ubuntu/pool/universe/s/scap-security-guide/ssg-base_0.1.80-1_all.deb",
      "curl -fsSL -o /tmp/ssg-debderived.deb http://ftp.sjtu.edu.cn/ubuntu/pool/universe/s/scap-security-guide/ssg-debderived_0.1.80-1_all.deb",
      "sudo dpkg -i /tmp/ssg-base.deb /tmp/ssg-debderived.deb",
      "rm -f /tmp/ssg-base.deb /tmp/ssg-debderived.deb",
      "command -v oscap >/dev/null",
      "test -f /usr/share/xml/scap/ssg/content/ssg-ubuntu2204-ds.xml",
      "sudo systemctl enable auditd chrony unattended-upgrades",
      "sudo systemctl enable amazon-ssm-agent 2>/dev/null || true",  # Optional, may not have installed
      "sudo sed -i 's/^#PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config",
      "sudo sed -i 's/^#PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config",
      "sudo sshd -t && sudo systemctl reload ssh || true",
      "sudo mkdir -p /opt/venvs /usr/share",
      "mkdir -p /home/ubuntu/packer-assets",
      "sudo chown -R ubuntu:ubuntu /opt/venvs",
      "python3 -m venv /opt/venvs/py311",
      "sudo chmod 755 /opt/venvs/py311",
      # AWS CLI v2 — aarch64 build with optional PGP verification (key is the same as x86)
      "curl -fsSL 'https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip' -o /tmp/awscliv2.zip",
      "curl -fsSL 'https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip.sig' -o /tmp/awscliv2.sig",
      "set +e; gpg --keyserver hkps://keys.openpgp.org --recv-keys FB5DB77FD5C118B80511ADA8A6310ACC4672475C 2>/dev/null; gpg --verify /tmp/awscliv2.sig /tmp/awscliv2.zip 2>/dev/null; set -e",
      "unzip -q /tmp/awscliv2.zip -d /tmp",
      "sudo /tmp/aws/install",
      "rm -rf /tmp/awscliv2.zip /tmp/awscliv2.sig /tmp/aws",
      "curl -fsSL -o /tmp/install-nix.sh https://releases.nixos.org/nix/nix-2.24.9/install",
      "yes | sudo -E sh /tmp/install-nix.sh --daemon || true",
      "echo '. /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh' | sudo tee /etc/profile.d/nix.sh",
      "echo '. /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh' | sudo tee -a /home/ubuntu/.profile",
      "sudo chown ubuntu:ubuntu /home/ubuntu/.profile || true",
      "sudo systemctl enable nix-daemon || true",
      "sudo systemctl start nix-daemon || true",
    ]
  }

  provisioner "file" {
    source      = "nix/flake.nix"
    destination = "/home/ubuntu/packer-assets/flake.nix"
  }
  provisioner "file" {
    source      = "scripts/spark-java.sh"
    destination = "/home/ubuntu/packer-assets/spark-java.sh"
  }
  provisioner "file" {
    source      = "scripts/build-base-envs.sh"
    destination = "/home/ubuntu/packer-assets/build-base-envs.sh"
  }
  provisioner "file" {
    source      = "scripts/ami-scan.sh"
    destination = "/home/ubuntu/packer-assets/ami-scan.sh"
  }
  provisioner "file" {
    source      = "scripts/fix-level1-base.sh"
    destination = "/home/ubuntu/packer-assets/fix-level1-base.sh"
  }
  provisioner "file" {
    source      = "examples/pyspark_basic.py"
    destination = "/home/ubuntu/packer-assets/pyspark_basic.py"
  }
  provisioner "file" {
    source      = "examples/pyspark_pi.py"
    destination = "/home/ubuntu/packer-assets/pyspark_pi.py"
  }
  # Build Nix envs BEFORE hardening — same rationale as x86 base build.
  provisioner "shell" {
    execute_command = "chmod +x {{ .Path }}; {{ .Vars }} bash {{ .Path }}"
    inline = [
      "sudo mkdir -p /opt/nix/flake",
      "sudo mv /home/ubuntu/packer-assets/flake.nix /opt/nix/flake/flake.nix",
      "sudo bash -lc 'source /etc/profile.d/nix.sh && nix --extra-experimental-features nix-command --extra-experimental-features flakes flake lock /opt/nix/flake'",
      # Configure Cachix binary cache — add substituters + trusted public keys so
      # Nix actually fetches from cache instead of rebuilding from source.
      "echo 'extra-substituters = https://cpu-ds-ml.cachix.org https://nix-community.cachix.org' | sudo tee -a /etc/nix/nix.conf",
      "echo 'trusted-public-keys = cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY= cpu-ds-ml.cachix.org-1:RQU8R11xfczT+AV5+UOJIBinRTQIbFhpn9qmk7f/QbY= nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCUSeBc=' | sudo tee -a /etc/nix/nix.conf",
      "sudo systemctl restart nix-daemon",
      "sudo bash /home/ubuntu/packer-assets/build-base-envs.sh",
      "sudo install -d -m 0755 /usr/share/examples/spark",
      "sudo mv /home/ubuntu/packer-assets/pyspark_basic.py /usr/share/examples/spark/pyspark_basic.py",
      "sudo mv /home/ubuntu/packer-assets/pyspark_pi.py /usr/share/examples/spark/pyspark_pi.py",
      "sudo chmod 0644 /usr/share/examples/spark/pyspark_*.py",
      "nix --version",
      "/usr/local/bin/py311 -V",
      "/usr/local/bin/py312 -V",
      "/usr/local/bin/py313 -V",
      "/usr/local/bin/py311 -c 'import pyspark; print(pyspark.__version__)'",
      "/usr/local/bin/py312 -c 'import pyspark; print(pyspark.__version__)'",
      "/usr/local/bin/py313 -c 'import pyspark; print(pyspark.__version__)'",
      "java -version",
      "spark-submit --version",
      "julia -e 'println(VERSION)'",
      "R --version",
      "go version",
      "rustc --version",
      "cargo --version",
      "node --version",
      "sudo mkdir -p /usr/share/BUILD_INFO && echo VERSION=1.0.0-BASE-ARM64 | sudo tee /usr/share/BUILD_INFO/version",
    ]
  }

  # CIS hardening — runs AFTER Nix builds so /tmp noexec does not block Nix sandbox.
  provisioner "file" {
    source      = "harden.sh"
    destination = "/tmp/harden.sh"
  }
  provisioner "shell" {
    execute_command = "chmod +x {{ .Path }}; {{ .Vars }} bash {{ .Path }}"
    inline = [
      "sudo systemctl daemon-reload",
      "sudo bash /tmp/harden.sh",
      "sudo bash /home/ubuntu/packer-assets/fix-level1-base.sh",
      "sudo install -m 0644 /home/ubuntu/packer-assets/spark-java.sh /etc/profile.d/spark-java.sh",
      "sudo install -m 0755 /home/ubuntu/packer-assets/ami-scan.sh /usr/local/bin/ami-scan",
      "sudo mkdir -p /opt/spark-local && sudo chmod 1777 /opt/spark-local",
    ]
  }

  provisioner "file" {
    source      = "scripts/ami-finalize.sh"
    destination = "/tmp/ami-finalize.sh"
  }
  provisioner "file" {
    source      = "SECURITY.md"
    destination = "/tmp/SECURITY.md"
  }
  provisioner "shell" {
    execute_command = "chmod +x {{ .Path }}; {{ .Vars }} bash {{ .Path }}"
    inline = ["sudo bash /tmp/ami-finalize.sh base"]
  }

  provisioner "shell" {
    execute_command = "chmod +x {{ .Path }}; {{ .Vars }} bash {{ .Path }}"
    inline = [
      "/usr/local/bin/py311 -c 'import pyspark; print(pyspark.__version__)'",
      "/usr/local/bin/py312 -c 'import pyspark; print(pyspark.__version__)'",
      "/usr/local/bin/py313 -c 'import pyspark; print(pyspark.__version__)'",
      "/usr/local/bin/py311 -c 'import jupyterlab, onnxruntime, cv2, skimage; print(\"py311 final runtime OK\")'",
      "/usr/local/bin/py312 -c 'import jupyterlab, onnxruntime, cv2, skimage; print(\"py312 final runtime OK\")'",
      "/usr/local/bin/py313 -c 'import jupyterlab, onnxruntime, cv2, skimage; print(\"py313 final runtime OK\")'",
    ]
  }
}

# =======================
# ARM64 PRO IMAGE (layers on ARM base)
# =======================
build {
  name    = "cpu-ds-ml-arm64-pro"
  sources = ["source.amazon-ebs.ubuntu_arm_pro"]

  provisioner "file" {
    source      = "scripts/build-pro-envs.sh"
    destination = "/tmp/build-pro-envs.sh"
  }
  provisioner "file" {
    source      = "scripts/tune-pro.sh"
    destination = "/tmp/tune-pro.sh"
  }
  provisioner "file" {
    source      = "scripts/smoke-pro.sh"
    destination = "/tmp/smoke-pro.sh"
  }
  provisioner "file" {
    source      = "scripts/fix-level2-addon.sh"
    destination = "/tmp/fix-level2-addon.sh"
  }

  provisioner "shell" {
    # Hardened /tmp is noexec after the kernel reboot; run the wrapper via
    # bash so the interpreter reads it (no exec() on the noexec file).
    execute_command = "chmod +x {{ .Path }}; {{ .Vars }} bash {{ .Path }}"
    inline = [
      "sudo chmod +x /tmp/build-pro-envs.sh /tmp/tune-pro.sh /tmp/smoke-pro.sh /tmp/fix-level2-addon.sh",
      "sudo bash /tmp/build-pro-envs.sh",
      "sudo bash /tmp/tune-pro.sh",
      "sudo bash /tmp/fix-level2-addon.sh",
      "/tmp/smoke-pro.sh",
      "/usr/local/bin/py311 -V",
      "/usr/local/bin/py312 -V",
      "/usr/local/bin/py313 -V",
      "java -version",
      "spark-submit --version",
      "sudo mkdir -p /usr/share/BUILD_INFO && echo VERSION=1.0.0-PRO-ARM64 | sudo tee /usr/share/BUILD_INFO/version",
    ]
  }

  provisioner "file" {
    source      = "scripts/ami-finalize.sh"
    destination = "/tmp/ami-finalize.sh"
  }
  provisioner "file" {
    source      = "SECURITY.md"
    destination = "/tmp/SECURITY.md"
  }
  provisioner "shell" {
    # Hardened /tmp is noexec after the kernel reboot; run the wrapper via
    # bash so the interpreter reads it (no exec() on the noexec file).
    execute_command = "chmod +x {{ .Path }}; {{ .Vars }} bash {{ .Path }}"
    inline = ["sudo bash /tmp/ami-finalize.sh pro"]
  }
}

# c6i.xlarge: 4 vCPU / 8 GB — 2x faster Nix builds vs m6i.large at similar cost.
# Use spot_price="auto" in vars to cut build cost by ~70% with Spot pricing.
variable "instance_type"    { default = "c6i.xlarge" }
variable "spot_price"       { default = "" }          # set "auto" to use Spot
variable "root_volume_size" { default = 24 }          # extra headroom for Nix store + pip wheels
variable "subnet_id"           { default = "" }
variable "security_group_id"   { default = "" }
variable "associate_public_ip" {
  type    = bool
  default = true
}
# Comma-separated list of additional regions to copy the AMI into after build.
# Example: ["us-west-2","eu-west-1","ap-southeast-1"]
variable "additional_regions" {
  type    = list(string)
  default = []
}
# c7g.xlarge: Graviton3, 4 vCPU / 8 GB — same spec class as c6i.xlarge used for x86.
variable "arm_instance_type" { default = "c7g.xlarge" }
