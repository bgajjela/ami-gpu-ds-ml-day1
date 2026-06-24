#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Bharath Kumar Gajjela

import pathlib
import re
import sys


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: sanitize-log.py <src> <dst>", file=sys.stderr)
        return 2

    src = pathlib.Path(sys.argv[1])
    dst = pathlib.Path(sys.argv[2])
    text = src.read_text(encoding="utf-8", errors="replace")

    patterns = [
        # Auth tokens and credentials
        (r"github\.com=[^\s\"']+",                      "github.com=***"),
        (r"AUTHORIZATION:\s*basic\s+\S+",               "AUTHORIZATION: basic ***"),
        (r"(?i)(authToken:\s*)(.+)",                    r"\1***"),
        (r"(?i)(token[:=]\s*)(\S+)",                    r"\1***"),
        (r"\b(AKIA|ASIA)[0-9A-Z]{16}\b",                "***AWS_ACCESS_KEY_ID***"),
        (r"(?i)aws_secret_access_key\s*=\s*\S+",        "aws_secret_access_key=***"),

        # AWS ARNs (must come before account ID pattern)
        (r"arn:aws:[^\s\"']+",                          "***AWS_ARN***"),

        # AWS account ID (12-digit standalone number)
        (r"\b([0-9]{12})\b",                            "***AWS_ACCOUNT_ID***"),

        # EC2 resource identifiers
        (r"\bi-[0-9a-f]{8,17}\b",                       "***EC2_INSTANCE_ID***"),
        (r"\bami-[0-9a-f]{8,17}\b",                     "***AMI_ID***"),
        (r"\bvol-[0-9a-f]{8,17}\b",                     "***EBS_VOLUME_ID***"),
        (r"\bsnap-[0-9a-f]{8,17}\b",                    "***EBS_SNAPSHOT_ID***"),
        (r"\bvpc-[0-9a-f]{8,17}\b",                     "***VPC_ID***"),
        (r"\bsubnet-[0-9a-f]{8,17}\b",                  "***SUBNET_ID***"),
        (r"\bsg-[0-9a-f]{8,17}\b",                      "***SECURITY_GROUP_ID***"),
        (r"\bkp-[0-9a-f]{8,17}\b",                      "***KEYPAIR_ID***"),

        # Packer temporary keypair names (packer_XXXXXXXXXX pattern)
        (r"\bpacker_[0-9a-zA-Z]{8,}\b",                 "***PACKER_KEYPAIR***"),

        # EC2 private / public IP addresses
        # Exclude loopback (127.x), link-local (169.254.x), and metadata (169.254.169.254)
        (r"\b(?!127\.|169\.254\.)(?:10\.|172\.(?:1[6-9]|2[0-9]|3[01])\.|192\.168\.)"
         r"[0-9]{1,3}\.[0-9]{1,3}\b",                  "***PRIVATE_IP***"),

        # Packer temp security group names
        (r"packer\s+[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}",
                                                         "***PACKER_SG***"),

        # SSH key fingerprints
        (r"[0-9a-f]{2}(?::[0-9a-f]{2}){15,}",          "***SSH_FINGERPRINT***"),

        # EC2 DNS hostnames  e.g. ec2-1-2-3-4.compute-1.amazonaws.com
        (r"ec2-[0-9]+-[0-9]+-[0-9]+-[0-9]+\.[^\s\"']+","***EC2_HOSTNAME***"),
    ]

    for pattern, repl in patterns:
        text = re.sub(pattern, repl, text)

    dst.write_text(text, encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
