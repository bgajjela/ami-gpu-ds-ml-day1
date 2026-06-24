# vars.example.pkrvars.hcl — copy to build.pkrvars.hcl and customise.
# Usage: packer build -var-file=build.pkrvars.hcl -only=cpu-ds-ml-base .
# Or simply: make build-base   (Makefile auto-detects *.pkrvars.hcl)

# ── Region ──────────────────────────────────────────────────────────────────
region = "us-east-1"

# ── Additional regions to copy the AMI into after build ─────────────────────
# additional_regions = ["us-west-2", "eu-west-1", "ap-southeast-1", "ap-northeast-1"]

# ── Build instance ──────────────────────────────────────────────────────────
# x86 (default): c6i.xlarge (4 vCPU / 8 GB)
# c6i.2xlarge (8 vCPU / 16 GB) for faster Nix builds if budget allows.
instance_type = "c6i.xlarge"

# ARM64/Graviton (default): c7g.xlarge (Graviton3, 4 vCPU / 8 GB)
# c7g.2xlarge (8 vCPU / 16 GB) for faster Nix builds on ARM.
# arm_instance_type = "c7g.xlarge"

# ── Spot pricing (set "auto" to bid on-demand price — saves ~70%) ───────────
spot_price = "auto"

# ── Networking ───────────────────────────────────────────────────────────────
# subnet_id         = "subnet-xxxxxxxxxxxxxxxxx"
# security_group_id = "sg-xxxxxxxxxxxxxxxxx"
associate_public_ip = true

# ── EBS encryption ───────────────────────────────────────────────────────────
encrypt_ebs      = true
root_volume_size = 24
# kms_key_id = "arn:aws:kms:us-east-1:123456789012:key/mrk-xxxxxxxx"
