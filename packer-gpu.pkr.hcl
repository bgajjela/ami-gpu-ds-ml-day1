# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Bharath Kumar Gajjela
#
# packer-gpu.pkr.hcl — GPU AMI builds (x86 + ARM64), layered on the same Nix +
# CIS-hardening foundation as packer.pkr.hcl. Lives in the same directory and
# REUSES the shared variables declared there (region, spot_price, subnet_id,
# security_group_id, associate_public_ip, additional_regions, root_volume_size).
# Only GPU-specific variables are declared below.
#
# Build order vs. the CPU AMIs is identical except two GPU-only steps inserted
# into the base build, both BEFORE harden.sh:
#   install-cuda.sh  (driver + CUDA toolkit + nouveau blacklist)
#   reboot           (nouveau unload + nvidia module load via fresh initramfs)
#
# Select builds with -only, e.g.:
#   packer build -only=gpu-ds-ml-x86-base.amazon-ebs.gpu_x86_base \
#     -var "subnet_id=subnet-xxx" .
#   packer build -only=gpu-ds-ml-x86-pro.amazon-ebs.gpu_x86_pro \
#     -var "gpu_base_ami_id=ami-xxx" .

# -------- GPU-specific variables --------
# g4dn.xlarge: NVIDIA T4, cheapest x86 GPU instance (~$0.53/hr) — fine as a build
# host; the resulting AMI runs on any compatible GPU instance the customer picks.
variable "gpu_instance_type" { default = "g4dn.xlarge" }
# g5g.xlarge: NVIDIA T4G on Graviton — effectively the only ARM GPU option.
variable "gpu_arm_instance_type" { default = "g5g.xlarge" }

# Pro builds layer on the already-built GPU base AMI (same pattern as the CPU
# pro builds with base_ami_id). Pipeline sets these from the base build output.
variable "gpu_base_ami_id" { default = "" }
variable "gpu_base_ami_id_arm" { default = "" }

locals {
  gpu_base_name     = "gpu-ds-ml-ubuntu-2204"
  gpu_arm_base_name = "gpu-ds-ml-ubuntu-2204-arm64"
}

# ==========================================================================
# SOURCES
# ==========================================================================
source "amazon-ebs" "gpu_x86_base" {
  region                      = var.region
  ssh_username                = "ubuntu"
  instance_type               = var.gpu_instance_type
  spot_price                  = var.spot_price
  subnet_id                   = var.subnet_id != "" ? var.subnet_id : null
  security_group_id           = var.security_group_id != "" ? var.security_group_id : null
  associate_public_ip_address = var.associate_public_ip
  ami_regions                 = var.additional_regions

  metadata_options {
    http_tokens                 = "required"
    http_endpoint               = "enabled"
    http_put_response_hop_limit = 1
  }

  source_ami_filter {
    owners      = ["099720109477"] # Canonical — same stock Ubuntu image; GPU stack layered on top
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

  ami_name        = "${local.gpu_base_name}-base-{{timestamp}}"
  ami_description = "GPU DS/ML AMI (Base) - Ubuntu 22.04, NVIDIA driver + CUDA 12.8, CIS-style hardened"
  tags            = { Name = "${local.gpu_base_name}-base", Role = "dsml-gpu" }
}

source "amazon-ebs" "gpu_x86_pro" {
  region                      = var.region
  ssh_username                = "ubuntu"
  instance_type               = var.gpu_instance_type
  spot_price                  = var.spot_price
  subnet_id                   = var.subnet_id != "" ? var.subnet_id : null
  security_group_id           = var.security_group_id != "" ? var.security_group_id : null
  associate_public_ip_address = var.associate_public_ip
  ami_regions                 = var.additional_regions

  # Layer on the already-hardened GPU base AMI — skips apt/hardening/Nix/CUDA work.
  source_ami = var.gpu_base_ami_id

  metadata_options {
    http_tokens                 = "required"
    http_endpoint               = "enabled"
    http_put_response_hop_limit = 1
  }

  launch_block_device_mappings {
    device_name           = "/dev/sda1"
    volume_size           = var.root_volume_size
    volume_type           = "gp3"
    delete_on_termination = true
  }

  ami_name        = "${local.gpu_base_name}-pro-{{timestamp}}"
  ami_description = "GPU DS/ML AMI (Pro) - Ubuntu 22.04, CUDA 12.8 + PyTorch/TensorFlow GPU, CIS-hardened"
  tags            = { Name = "${local.gpu_base_name}-pro", Role = "dsml-gpu" }
}

source "amazon-ebs" "gpu_arm_base" {
  region                      = var.region
  ssh_username                = "ubuntu"
  instance_type               = var.gpu_arm_instance_type
  spot_price                  = var.spot_price
  subnet_id                   = var.subnet_id != "" ? var.subnet_id : null
  security_group_id           = var.security_group_id != "" ? var.security_group_id : null
  associate_public_ip_address = var.associate_public_ip
  ami_regions                 = var.additional_regions

  metadata_options {
    http_tokens                 = "required"
    http_endpoint               = "enabled"
    http_put_response_hop_limit = 1
  }

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

  ami_name        = "${local.gpu_arm_base_name}-base-{{timestamp}}"
  ami_description = "GPU DS/ML AMI (Base, ARM64/Graviton) - Ubuntu 22.04, NVIDIA driver + CUDA 12.8, CIS-style hardened"
  tags            = { Name = "${local.gpu_arm_base_name}-base", Role = "dsml-gpu" }
}

source "amazon-ebs" "gpu_arm_pro" {
  region                      = var.region
  ssh_username                = "ubuntu"
  instance_type               = var.gpu_arm_instance_type
  spot_price                  = var.spot_price
  subnet_id                   = var.subnet_id != "" ? var.subnet_id : null
  security_group_id           = var.security_group_id != "" ? var.security_group_id : null
  associate_public_ip_address = var.associate_public_ip
  ami_regions                 = var.additional_regions

  source_ami = var.gpu_base_ami_id_arm

  metadata_options {
    http_tokens                 = "required"
    http_endpoint               = "enabled"
    http_put_response_hop_limit = 1
  }

  launch_block_device_mappings {
    device_name           = "/dev/sda1"
    volume_size           = var.root_volume_size
    volume_type           = "gp3"
    delete_on_termination = true
  }

  ami_name        = "${local.gpu_arm_base_name}-pro-{{timestamp}}"
  ami_description = "GPU DS/ML AMI (Pro, ARM64/Graviton) - Ubuntu 22.04, CUDA 12.8 + PyTorch GPU (TF CPU), CIS-hardened"
  tags            = { Name = "${local.gpu_arm_base_name}-pro", Role = "dsml-gpu" }
}

# ==========================================================================
# GPU x86 BASE
# ==========================================================================
build {
  name    = "gpu-ds-ml-x86-base"
  sources = ["source.amazon-ebs.gpu_x86_base"]

  # 1. Patch + reboot into the final kernel so the NVIDIA DKMS module builds
  #    against the kernel that will actually run in the AMI.
  provisioner "shell" {
    execute_command   = "chmod +x {{ .Path }}; {{ .Vars }} bash {{ .Path }}"
    expect_disconnect = true
    inline = [
      "sudo apt-get update",
      "sudo DEBIAN_FRONTEND=noninteractive apt-get upgrade -y",
      "sudo reboot || true",
    ]
  }

  # 2. Core packages + AWS CLI v2 + Nix (identical to the CPU base build).
  provisioner "shell" {
    execute_command = "chmod +x {{ .Path }}; {{ .Vars }} bash {{ .Path }}"
    pause_before    = "30s"
    inline = [
      "echo 'Resumed after reboot — kernel: $(uname -r)'",
      "sudo apt-get update",
      "sudo apt-get -y install curl jq git-lfs unzip gnupg build-essential python3-venv ca-certificates xz-utils libstdc++6 libgomp1 software-properties-common",
      "sudo apt-get -y install ufw auditd fail2ban unattended-upgrades logrotate chrony",
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
      "sudo systemctl enable amazon-ssm-agent 2>/dev/null || true",
      "sudo sed -i 's/^#PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config",
      "sudo sed -i 's/^#PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config",
      "sudo sshd -t && sudo systemctl reload ssh || true",
      "sudo mkdir -p /opt/venvs /usr/share",
      "mkdir -p /home/ubuntu/packer-assets",
      "sudo chown -R ubuntu:ubuntu /opt/venvs",
      "python3 -m venv /opt/venvs/py311",
      "sudo chmod 755 /opt/venvs/py311",
      "curl -fsSL 'https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip' -o /tmp/awscliv2.zip",
      "curl -fsSL 'https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip.sig' -o /tmp/awscliv2.sig",
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

  # 3. Upload + run install-cuda.sh (driver + CUDA toolkit + nouveau blacklist),
  #    then reboot so nouveau unloads and the nvidia module binds the GPU.
  provisioner "file" {
    source      = "scripts/install-cuda.sh"
    destination = "/home/ubuntu/packer-assets/install-cuda.sh"
  }
  provisioner "file" {
    source      = "gpu/versions.env"
    destination = "/home/ubuntu/packer-assets/versions.env"
  }
  provisioner "shell" {
    execute_command   = "chmod +x {{ .Path }}; {{ .Vars }} bash {{ .Path }}"
    expect_disconnect = true
    inline = [
      "sudo bash /home/ubuntu/packer-assets/install-cuda.sh",
      "sudo reboot || true",
    ]
  }

  # 4. Verify the GPU is live before doing any more work. Use the absolute nvcc
  #    path — this is a non-login shell so /etc/profile.d/cuda.sh is not sourced.
  provisioner "shell" {
    execute_command = "chmod +x {{ .Path }}; {{ .Vars }} bash {{ .Path }}"
    pause_before    = "45s"
    inline = [
      "echo 'Resumed after CUDA reboot — kernel: $(uname -r)'",
      "nvidia-smi",
      "/usr/local/cuda/bin/nvcc --version",
    ]
  }

  # 5. Nix flake + base envs (identical to the CPU base build).
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
  provisioner "shell" {
    execute_command = "chmod +x {{ .Path }}; {{ .Vars }} bash {{ .Path }}"
    inline = [
      "sudo mkdir -p /opt/nix/flake",
      "sudo mv /home/ubuntu/packer-assets/flake.nix /opt/nix/flake/flake.nix",
      "sudo bash -lc 'source /etc/profile.d/nix.sh && nix --extra-experimental-features nix-command --extra-experimental-features flakes flake lock /opt/nix/flake'",
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
      "java -version",
      "spark-submit --version",
      "julia -e 'println(VERSION)'",
      "R --version",
      "go version",
      "rustc --version",
      "node --version",
      "sudo mkdir -p /usr/share/BUILD_INFO && echo VERSION=1.0.0-GPU-BASE | sudo tee /usr/share/BUILD_INFO/version",
    ]
  }

  # 6. CIS hardening — AFTER both Nix and the CUDA install (driver modules are
  #    already loaded; harden.sh's module blacklist does not touch nvidia).
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
      "test -f /home/ubuntu/packer-assets/spark-java.sh && sudo install -m 0644 /home/ubuntu/packer-assets/spark-java.sh /etc/profile.d/spark-java.sh || echo 'spark-java.sh not found'",
      "test -f /home/ubuntu/packer-assets/ami-scan.sh && sudo install -m 0755 /home/ubuntu/packer-assets/ami-scan.sh /usr/local/bin/ami-scan || echo 'ami-scan.sh not found'",
      "sudo mkdir -p /opt/spark-local && sudo chmod 1777 /opt/spark-local",
      # Re-verify the GPU survived hardening (module loading + sysctl lockdown).
      "nvidia-smi",
    ]
  }

  # 7. Manifest + legal + scrub — must be last.
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
    inline          = ["sudo bash /tmp/ami-finalize.sh base"]
  }
}

# ==========================================================================
# GPU x86 PRO (layers on GPU base)
# ==========================================================================
build {
  name    = "gpu-ds-ml-x86-pro"
  sources = ["source.amazon-ebs.gpu_x86_pro"]

  provisioner "file" {
    source      = "scripts/build-gpu-envs.sh"
    destination = "/tmp/build-gpu-envs.sh"
  }
  provisioner "file" {
    source      = "gpu/versions.env"
    destination = "/tmp/versions.env"
  }
  provisioner "file" {
    source      = "scripts/tune-pro.sh"
    destination = "/tmp/tune-pro.sh"
  }
  provisioner "file" {
    source      = "scripts/tune-gpu.sh"
    destination = "/tmp/tune-gpu.sh"
  }
  provisioner "file" {
    source      = "scripts/smoke-gpu.sh"
    destination = "/tmp/smoke-gpu.sh"
  }
  provisioner "file" {
    source      = "scripts/fix-level2-addon.sh"
    destination = "/tmp/fix-level2-addon.sh"
  }

  provisioner "shell" {
    execute_command = "chmod +x {{ .Path }}; {{ .Vars }} bash {{ .Path }}"
    inline = [
      "sudo chmod +x /tmp/build-gpu-envs.sh /tmp/tune-pro.sh /tmp/tune-gpu.sh /tmp/smoke-gpu.sh /tmp/fix-level2-addon.sh",
      # CUDA torch/tf wheels layered on the base Nix envs (~20-30 min).
      "sudo bash /tmp/build-gpu-envs.sh",
      # Shared ML tuning (sysctl/THP/NVMe/threads) then GPU-specific tuning.
      "sudo bash /tmp/tune-pro.sh",
      "sudo bash /tmp/tune-gpu.sh",
      "sudo bash /tmp/fix-level2-addon.sh",
      # GPU compute smoke test — asserts CUDA is live, not a CPU fallback.
      "/tmp/smoke-gpu.sh",
      "/usr/local/bin/py311 -V",
      "java -version",
      "spark-submit --version",
      "sudo mkdir -p /usr/share/BUILD_INFO && echo VERSION=1.0.0-GPU-PRO | sudo tee /usr/share/BUILD_INFO/version",
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
    inline          = ["sudo bash /tmp/ami-finalize.sh pro"]
  }
}

# ==========================================================================
# GPU ARM64 BASE  (phase 2 — TF stays CPU-only on aarch64; see build-gpu-envs.sh)
# ==========================================================================
build {
  name    = "gpu-ds-ml-arm64-base"
  sources = ["source.amazon-ebs.gpu_arm_base"]

  provisioner "shell" {
    execute_command   = "chmod +x {{ .Path }}; {{ .Vars }} bash {{ .Path }}"
    expect_disconnect = true
    inline = [
      "sudo apt-get update",
      "sudo DEBIAN_FRONTEND=noninteractive apt-get upgrade -y",
      "sudo reboot || true",
    ]
  }

  provisioner "shell" {
    execute_command = "chmod +x {{ .Path }}; {{ .Vars }} bash {{ .Path }}"
    pause_before    = "30s"
    inline = [
      "echo 'Resumed after reboot — kernel: $(uname -r)'",
      "sudo apt-get update",
      "sudo apt-get -y install curl jq git-lfs unzip gnupg build-essential python3-venv ca-certificates xz-utils libstdc++6 libgomp1 software-properties-common",
      "sudo apt-get -y install ufw auditd fail2ban unattended-upgrades logrotate chrony",
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
      "sudo systemctl enable amazon-ssm-agent 2>/dev/null || true",
      "sudo sed -i 's/^#PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config",
      "sudo sed -i 's/^#PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config",
      "sudo sshd -t && sudo systemctl reload ssh || true",
      "sudo mkdir -p /opt/venvs /usr/share",
      "mkdir -p /home/ubuntu/packer-assets",
      "sudo chown -R ubuntu:ubuntu /opt/venvs",
      "python3 -m venv /opt/venvs/py311",
      "sudo chmod 755 /opt/venvs/py311",
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
    source      = "scripts/install-cuda.sh"
    destination = "/home/ubuntu/packer-assets/install-cuda.sh"
  }
  provisioner "file" {
    source      = "gpu/versions.env"
    destination = "/home/ubuntu/packer-assets/versions.env"
  }
  provisioner "shell" {
    execute_command   = "chmod +x {{ .Path }}; {{ .Vars }} bash {{ .Path }}"
    expect_disconnect = true
    inline = [
      "sudo bash /home/ubuntu/packer-assets/install-cuda.sh",
      "sudo reboot || true",
    ]
  }
  provisioner "shell" {
    execute_command = "chmod +x {{ .Path }}; {{ .Vars }} bash {{ .Path }}"
    pause_before    = "45s"
    inline = [
      "echo 'Resumed after CUDA reboot — kernel: $(uname -r)'",
      "nvidia-smi",
      "/usr/local/cuda/bin/nvcc --version",
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
  provisioner "shell" {
    execute_command = "chmod +x {{ .Path }}; {{ .Vars }} bash {{ .Path }}"
    inline = [
      "sudo mkdir -p /opt/nix/flake",
      "sudo mv /home/ubuntu/packer-assets/flake.nix /opt/nix/flake/flake.nix",
      "sudo bash -lc 'source /etc/profile.d/nix.sh && nix --extra-experimental-features nix-command --extra-experimental-features flakes flake lock /opt/nix/flake'",
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
      "/usr/local/bin/py311 -c 'import pyspark; print(pyspark.__version__)'",
      "java -version",
      "spark-submit --version",
      "sudo mkdir -p /usr/share/BUILD_INFO && echo VERSION=1.0.0-GPU-BASE-ARM64 | sudo tee /usr/share/BUILD_INFO/version",
    ]
  }

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
      "nvidia-smi",
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
    inline          = ["sudo bash /tmp/ami-finalize.sh base"]
  }
}

# ==========================================================================
# GPU ARM64 PRO (layers on GPU ARM base)
# ==========================================================================
build {
  name    = "gpu-ds-ml-arm64-pro"
  sources = ["source.amazon-ebs.gpu_arm_pro"]

  provisioner "file" {
    source      = "scripts/build-gpu-envs.sh"
    destination = "/tmp/build-gpu-envs.sh"
  }
  provisioner "file" {
    source      = "gpu/versions.env"
    destination = "/tmp/versions.env"
  }
  provisioner "file" {
    source      = "scripts/tune-pro.sh"
    destination = "/tmp/tune-pro.sh"
  }
  provisioner "file" {
    source      = "scripts/tune-gpu.sh"
    destination = "/tmp/tune-gpu.sh"
  }
  provisioner "file" {
    source      = "scripts/smoke-gpu.sh"
    destination = "/tmp/smoke-gpu.sh"
  }
  provisioner "file" {
    source      = "scripts/fix-level2-addon.sh"
    destination = "/tmp/fix-level2-addon.sh"
  }

  provisioner "shell" {
    execute_command = "chmod +x {{ .Path }}; {{ .Vars }} bash {{ .Path }}"
    inline = [
      "sudo chmod +x /tmp/build-gpu-envs.sh /tmp/tune-pro.sh /tmp/tune-gpu.sh /tmp/smoke-gpu.sh /tmp/fix-level2-addon.sh",
      "sudo bash /tmp/build-gpu-envs.sh",
      "sudo bash /tmp/tune-pro.sh",
      "sudo bash /tmp/tune-gpu.sh",
      "sudo bash /tmp/fix-level2-addon.sh",
      "/tmp/smoke-gpu.sh",
      "/usr/local/bin/py311 -V",
      "java -version",
      "spark-submit --version",
      "sudo mkdir -p /usr/share/BUILD_INFO && echo VERSION=1.0.0-GPU-PRO-ARM64 | sudo tee /usr/share/BUILD_INFO/version",
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
    inline          = ["sudo bash /tmp/ami-finalize.sh pro"]
  }
}
