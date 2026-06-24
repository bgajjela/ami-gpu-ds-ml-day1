# Security Policy

## Reporting a Vulnerability

**Do not open a public GitHub issue for security vulnerabilities.**

Email: bgajjela@gmail.com
Subject line: `[SECURITY] GPU DS/ML AMI — <brief description>`

Include:
- CVE ID if one exists
- Affected AMI versions / build timestamps
- Description of the vulnerability and impact
- Steps to reproduce (if applicable)

We aim to acknowledge reports within **2 business days** and provide a
remediation timeline within **7 business days**.

---

## Supported Versions

| AMI | Status |
|---|---|
| Latest published version | Actively maintained |
| Previous version (n-1) | Security patches only |
| Older versions | End of life — upgrade recommended |

AMI builds are timestamped in the name: `gpu-ds-ml-ubuntu-2204-{base|pro}-<timestamp>`
(and `gpu-ds-ml-ubuntu-2204-arm64-{base|pro}-<timestamp>` for Graviton).
Check `/usr/share/BUILD_INFO/version` on a running instance for the exact build.

---

## Security Advisories

### CVE-2026-31431 — Copy Fail (local privilege escalation)

| Field | Detail |
|---|---|
| **CVE** | CVE-2026-31431 |
| **Severity** | High |
| **Component** | `algif_aead` Linux kernel module (AF_ALG AEAD socket) |
| **Affected kernels** | 4.14 – 6.19.12 |
| **Ubuntu 22.04 kernel** | 5.15.x — within affected range |
| **Impact** | Local privilege escalation to root for any active user session |
| **Remediated in AMI build** | Applied 2026-05-17 |
| **Reference** | https://cisecurity.atlassian.net/wiki/spaces/CSKB/pages/5164630160/ |

**What was done in the AMI build (applied 2026-05-17):**

1. `algif_aead` blacklisted in `/etc/modprobe.d/cis-blacklist.conf` — module
   cannot load on any instance launched from this AMI. Takes effect immediately
   at boot; no workload on this AMI requires the AF_ALG kernel socket
   (PyTorch, TensorFlow, OpenSSL all use userspace crypto).

2. Packer base build now reboots into the patched kernel before snapshotting
   the AMI — ensures the kernel patch is *running*, not just installed.

**If you are running instances launched from an older AMI build:**

The kernel patch is delivered automatically by `unattended-upgrades` (enabled
on all AMI builds). To complete remediation on running instances:

```bash
# 1. Verify the patch is installed (look for linux-image version >= patched version)
apt list --installed 2>/dev/null | grep linux-image

# 2. Reboot to activate the patched kernel
sudo reboot

# 3. After reboot — verify algif_aead cannot load (should print "install /bin/true")
grep algif_aead /etc/modprobe.d/cis-blacklist.conf || echo "NOT PRESENT — upgrade AMI"

# 4. Confirm module is not loaded
lsmod | grep algif_aead || echo "algif_aead not loaded — expected"
```

If `/etc/modprobe.d/cis-blacklist.conf` does not contain `algif_aead`, your
instance was launched from a pre-remediation AMI. Apply the interim mitigation
manually:

```bash
sudo tee -a /etc/modprobe.d/cis-blacklist.conf <<'EOF'
# CVE-2026-31431 interim mitigation
install algif_aead /bin/true
EOF
sudo rmmod algif_aead 2>/dev/null || true
sudo update-initramfs -u
```

Then reboot to activate the patched kernel.

---

## General Security Posture

Every AMI build applies the following before publishing:

- **CIS Ubuntu 22.04 LTS Benchmark L1+L2**: 114 controls, 0 failures
- **`apt-get upgrade`** at build time: all Ubuntu security patches applied
- **Kernel reboot** at build time: patched kernel confirmed running in snapshot
- **`unattended-upgrades`** enabled: running instances receive security patches automatically
- **On-demand CVE scan**: `sudo ami-scan` (Trivy + OpenSCAP) — run anytime
- **EBS encryption** at rest; **IMDSv2** enforced; **SSH** key-only, no root login

For the full control list see `SECURITY_REPORT.md`.

---

## Verifying release signatures

All releases are GPG-signed. To verify:

```bash
# 1. Import the maintainer's public key
gpg --keyserver keyserver.ubuntu.com --recv-keys 32BCD1C307771BAD

# 2. Verify the signed tag
git fetch --tags
git tag -v 1.0.0
```

Expected output includes: `Good signature from "Bharath Kumar Gajjela <bgajjela@gmail.com>"`

The public key fingerprint is: `C06D 6AF1 DA1E E331 3768 2DF0 32BC D1C3 0777 1BAD`

---

## Assurance case

### Threat model

| Threat | Mitigations |
|--------|-------------|
| Local privilege escalation | ASLR enabled, core dumps restricted, kernel module blacklist (algif_aead), sudo timestamp_timeout, CIS L2 controls |
| Lateral movement via SSH | SSHv2 only, key-based auth, root login disabled, HostKeyAlgorithms restricted, SSM-only recommended |
| Supply chain compromise | AWS CLI verified via PGP, Trivy installed via pinned commit SHA, all CI actions pinned by commit SHA, CycloneDX SBOM |
| SSRF / metadata abuse | IMDSv2 enforced — token-required, no v1 fallback |
| Credential exposure | ami-finalize.sh wipes SSH host keys, bash history, and cloud-init state before snapshot |
| Vulnerable packages | Trivy CVE scan in CI (HIGH/CRITICAL exit-code 1), unattended-upgrades on running instances |
| Misconfigured infrastructure | Checkov Packer IaC scan in CI |

### Trust boundaries

- **Outside trust boundary**: the AWS hypervisor, EC2 network, upstream Ubuntu package mirrors, external Nix package cache
- **Inside trust boundary**: AMI build process, provisioner scripts, Nix environments, hardening controls

### Secure design principles applied

- **Least privilege**: no root SSH, sudo timestamp_timeout, restricted kernel modules, IMDSv2 token-required
- **Defense in depth**: CIS L1+L2 + STIG-aligned additions + Trivy + unattended-upgrades — multiple independent layers
- **Fail secure**: Trivy HIGH/CRITICAL findings fail CI hard; Packer build fails on provisioner errors
- **Minimal attack surface**: SSM-only access (no open port 22), unnecessary kernel modules blacklisted, unused services disabled

### Common implementation weaknesses countered

- **Injection**: ShellCheck enforces proper quoting and variable expansion in all scripts
- **Insecure defaults**: All hardening applied at build time — instances launch hardened, not hardened later
- **Broken cryptography**: SHA-1, MD5, RC4, CBC mode SSH disabled; TLS 1.2 minimum enforced
- **Exposed credentials**: Trivy secret scanning on every CI push; ami-finalize.sh wipes credentials before snapshot

---

## Disclaimer

THIS AMI IS PROVIDED "AS IS" AND "AS AVAILABLE" WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE, TITLE, OR NON-INFRINGEMENT.

**Shared responsibility.** Security for workloads launched from this AMI is a
shared responsibility. This AMI provides build-time hardening, package
selection, and scan support, but you remain responsible for determining whether
the AMI is appropriate for your environment, validating any security or
compliance controls against your own requirements, and securely configuring,
operating, patching, monitoring, networking, and controlling access to any
deployed instances.

**Support scope.** Support, if any, is limited to the support terms and contact
methods provided with the listing. No managed security service, legal advice,
compliance certification, incident response obligation, or guaranteed response
time is provided unless explicitly stated in the applicable listing terms.

**Limitation of liability.** To the maximum extent permitted by applicable law,
the maintainer will not be liable for any indirect, incidental, special,
consequential, exemplary, or punitive damages, or for any loss of profits,
revenue, data, business, goodwill, or anticipated savings, arising out of or
related to this AMI, even if advised of the possibility of such damages. To the
maximum extent permitted by applicable law, any liability relating to this AMI
will be limited to the amount you paid for the AMI during the 12 months
preceding the event giving rise to the claim.

**No compliance guarantee.** References to CIS, hardening, scanning, or similar
security controls describe technical measures included in the build and do not
constitute a representation or warranty that your use of this AMI satisfies any
legal, regulatory, contractual, or audit requirement, including SOC 2, HIPAA,
PCI DSS, FedRAMP, or ISO 27001. Formal compliance determinations require your
own review and, where appropriate, qualified professional advice or independent
audit.

**AWS terms govern.** Your use of this AMI through AWS Marketplace remains
subject to the AWS Customer Agreement, the AWS Marketplace Standard Contract,
and any listing-specific terms. If those terms conflict with this document, the
applicable AWS Marketplace terms control.
