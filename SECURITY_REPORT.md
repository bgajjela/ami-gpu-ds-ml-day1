# Security Hardening Summary (CIS-aligned Ubuntu 22.04 LTS hardening)

**Result: CIS-aligned hardening controls applied; validate the current AMI with `sudo ami-scan` for current OpenSCAP and Trivy results**

Applied by: `install-cuda.sh` (GPU driver/CUDA), `harden.sh` (base AMI),
`tune-pro.sh` + `tune-gpu.sh` (Pro AMI additional tuning)  
Verified by: `sudo ami-scan` (Trivy + OpenSCAP, available on every instance)

## Architectures Covered

This report applies equally to both published GPU AMI families:

| Architecture | Instance family | GPU | AMI name pattern |
|---|---|---|---|
| x86\_64 (Intel/AMD) | g4dn | NVIDIA T4 | `gpu-ds-ml-ubuntu-2204-{base\|pro}-<timestamp>` |
| ARM64 / Graviton | g5g | NVIDIA T4G | `gpu-ds-ml-ubuntu-2204-arm64-{base\|pro}-<timestamp>` |

Both architectures are built from **the same hardening and environment scripts**:
`install-cuda.sh`, `harden.sh`, `tune-pro.sh`, `tune-gpu.sh`, `build-base-envs.sh`,
`build-gpu-envs.sh`, `smoke-gpu.sh`, and `ami-finalize.sh`. The build-time
differences are the AWS CLI download URL (`aarch64` vs `x86_64`), the Ubuntu source
AMI filter (`arm64-server` vs `amd64-server`), the CUDA repo arch (`sbsa` vs
`x86_64`), and TensorFlow GPU vs CPU (x86 vs ARM64). All hardening controls, sysctl
settings, service masking, audit rules, and AMI scrub steps are identical across
both architectures.

---

## GPU Driver / Hardening Ordering

The GPU stack is installed **before** CIS hardening, by design:

- `install-cuda.sh` runs after the kernel-upgrade reboot (so the NVIDIA DKMS
  module builds against the final running kernel) and **before** `harden.sh`, so
  CIS module/sysctl lockdown never interferes with driver module loading.
- `nouveau` (the open-source driver) is blacklisted via
  `/etc/modprobe.d/blacklist-nouveau.conf`; the build reboots once more so nouveau
  unloads and the proprietary `nvidia` module binds the GPU.
- The `nvidia`, `nvidia_uvm`, `nvidia_modeset`, and `nvidia_drm` modules load at
  boot via `/etc/modules-load.d/nvidia.conf`.
- The driver and toolkit are `apt-mark hold`-ed so `unattended-upgrades` cannot
  bump them out of lockstep with the CUDA/PyTorch chain.
- The build verifies `nvidia-smi` both immediately after the driver reboot **and**
  again after `harden.sh`, confirming hardening did not disturb the GPU.

- Verify on a running instance:
  ```
  nvidia-smi
  lsmod | grep -E 'nvidia|nouveau'   # expect nvidia loaded, nouveau absent
  apt-mark showhold                   # expect cuda-drivers-570, cuda-toolkit-12-8
  ```

---

## SSH Hardening

Password and keyboard-interactive auth disabled; public-key only. Root login
disabled. Safer ciphers, MACs, and key exchange algorithms enforced.

- Config: `/etc/ssh/sshd_config`
- Verify:
  ```
  sshd -T | egrep 'passwordauthentication|kbdinteractiveauthentication|permitrootlogin|challengeresponseauthentication|x11forwarding|usedns|printlastlog|banner'
  ```
  Expect: `passwordauthentication no`, `kbdinteractiveauthentication no`,
  `permitrootlogin no`, `usedns no`, `x11forwarding no`, `banner /etc/issue.net`

---

## Login Banners

Legal notice at `/etc/issue` (local TTY) and `/etc/issue.net` (SSH pre-auth).

- Verify: `sshd -T | grep banner` and `cat /etc/issue /etc/issue.net`
- Permissions: `stat -c '%a %U:%G %n' /etc/issue /etc/issue.net` (expect `644 root:root`)

---

## Firewall / Network Controls

The AMI enables `nftables` and applies additional SSH protection with fail2ban.
The exact runtime network policy remains part of the customer's deployment and VPC design.

- Verify:
  ```
  systemctl is-enabled nftables
  systemctl is-active nftables
  sudo nft list ruleset
  ```
  Expect: `enabled`, `active`, and a valid ruleset.

---

## System Updates and Core Services

`unattended-upgrades` enabled — running instances receive security patches
automatically. `systemd-timesyncd` and `auditd` are enabled at boot in the
current hardening path.

- Verify: `systemctl is-enabled systemd-timesyncd auditd unattended-upgrades` (expect `enabled`)

---

## Boot Service Hardening

Unnecessary services are disabled or masked at AMI build time to reduce the
attack surface and boot footprint.

| Service | Action | Reason |
|---------|--------|--------|
| `fwupd` / `fwupd-refresh.timer` | masked | no firmware updates on cloud VMs |
| `apport` / `whoopsie` | masked | crash reporting not needed, leaks system info |
| `multipathd` / `multipathd.socket` | masked | single EBS root volume, no multipath |
| `iscsid` | masked | no iSCSI block storage |
| `motd-news.timer` | masked | prevents outbound calls to motd.ubuntu.com |
| `systemd-timesyncd` | enabled in current build | baseline time synchronization |
| `atd` | disabled | at-job scheduler unused; crond restricted to root |
| `snapd` (all units) | disabled | Snap not supported in this environment |
| `pollinate` | disabled | entropy seeding not needed post-boot |

- Verify: `systemctl is-enabled fwupd apport multipathd` (each should be `masked` or `disabled`)

---

## File System and Directory Hardening

`/tmp` and `/var/tmp` mounted as tmpfs (`nodev,nosuid,noexec,mode=1777`) via
systemd mount units. `/dev/shm` hardened via fstab. World-writable directories
have sticky bit. Home directories: `0750` (root `0700`). umask `027`.

- Verify:
  ```
  systemctl status tmp.mount var-tmp.mount
  mount | egrep '/tmp|/var/tmp|/dev/shm'
  stat -c '%a' /home/* /root
  umask   # in a new login shell — expect 0027
  ```

---

## Sysctl Hardening

Applied via `/etc/sysctl.d/99-cis-net.conf` and `99-cis-fs.conf`.

Key controls: IP redirects/source routing disabled, `rp_filter` on, SYN cookies
on, IPv6 RA/redirects off, ASLR on, `protected_{symlinks,hardlinks,fifos,regular}`
enabled, `kptr_restrict`, `dmesg_restrict`, `perf_event_paranoid`, `ptrace_scope`.

- Verify:
  ```
  sysctl -a | egrep 'accept_redirects|accept_source_route|send_redirects|rp_filter|tcp_syncookies|randomize_va_space|suid_dumpable|protected_(hardlinks|symlinks|fifos|regular)|kptr_restrict|dmesg_restrict|perf_event_paranoid|ptrace_scope'
  ```

---

## Resource Limits (ulimits)

### Base AMI (`/etc/security/limits.d/99-ulimits.conf`)

| Limit | Soft | Hard |
|-------|------|------|
| nofile (open files) | 65535 | 65535 |
| nproc (processes) | 16384 | 16384 |
| core | 0 | 0 |
| memlock | 65536 KB | 65536 KB |

Systemd defaults mirror PAM limits via `/etc/systemd/system.conf.d/99-limits.conf`.

### Pro AMI (overrides by `tune-pro.sh`)

| Limit | Soft | Hard |
|-------|------|------|
| nofile | 1,048,576 | 1,048,576 |
| nproc | 65536 | 65536 |
| memlock | unlimited | unlimited |

- Verify:
  ```
  ulimit -n          # in a new login shell
  systemctl show --property DefaultLimitNOFILE
  ```

---

## Auditd

Watch rules: identity files, sudoers, `sshd_config`, sysctl, audit config, time
changes, kernel module loads. Rules set immutable at boot. GRUB `audit=1` enables
kernel-level syscall auditing from the earliest boot stage.

All syscall rules use both `arch=b64` and `arch=b32` filters — on x86\_64 this
covers 64-bit and 32-bit compat syscalls; on ARM64 (aarch64) `arch=b64` maps to
native 64-bit syscalls and `arch=b32` covers AArch32 compat. Both architectures
produce equivalent audit coverage.

- Verify:
  ```
  auditctl -s          # expect enabled=2 (immutable)
  auditctl -l | head
  grep audit=1 /proc/cmdline   # after reboot
  ```

---

## AppArmor, AIDE, PAM

- **AppArmor**: installed and enabled; verify enforcement state on the current instance.
- **AIDE**: package and configuration included; validate database state on the current instance if you rely on it operationally.
- **Password quality**: minlen=14, character class requirements, history=5.
- **faillock**: deny after 5 failures, 900-second unlock.
- **su**: restricted to `sudo` group via `pam_wheel`.

- Verify:
  ```
  aa-status
  grep -E 'minlen|dcredit|ucredit|lcredit|ocredit|remember' /etc/security/pwquality.conf
  grep faillock /etc/pam.d/common-*
  grep pam_wheel /etc/pam.d/su
  test -f /var/lib/aide/aide.db && echo "AIDE DB present"
  ```

---

## Kernel Module Blacklist

Unused and dangerous kernel modules are blacklisted in
`/etc/modprobe.d/cis-blacklist.conf` using `install <module> /bin/true` which
prevents loading even with `modprobe`.

| Module | Reason |
|--------|--------|
| `cramfs`, `freevxfs`, `jffs2`, `hfs`, `hfsplus`, `squashfs`, `udf` | Unused filesystems |
| `dccp`, `sctp`, `rds`, `tipc` | Unused protocols |
| `algif_aead` | **CVE-2026-31431** local privilege escalation via AF_ALG socket |
| `nouveau` | Open-source NVIDIA driver — blacklisted so the proprietary `nvidia` driver binds the GPU (`/etc/modprobe.d/blacklist-nouveau.conf`) |

> The `nvidia`/`nvidia_uvm`/`nvidia_modeset`/`nvidia_drm` modules are **not**
> blacklisted — they are explicitly loaded at boot. `harden.sh`'s CIS blacklist
> touches only the modules above.

- Verify:
  ```
  grep algif_aead /etc/modprobe.d/cis-blacklist.conf
  lsmod | grep algif_aead || echo "algif_aead not loaded — expected"
  ```

---

## CVE-2026-31431 (Copy Fail) Remediation

| Field | Detail |
|-------|--------|
| CVE | CVE-2026-31431 |
| Severity | High |
| Component | `algif_aead` Linux kernel module |
| Impact | Local privilege escalation to root |
| AMI remediation | Applied 2026-05-17 |

Two-layer fix applied at build time:

1. `algif_aead` blacklisted (`install algif_aead /bin/true`) — module cannot load
2. Packer build reboots into the patched kernel before snapshotting the AMI

See `SECURITY.md` for the full advisory and manual remediation steps for older instances.

---

## Log Management

`logrotate`: weekly, rotate 14, compress + delaycompress, dateext. `journald`: persistent, compressed, size-capped (500 MB system,
200 MB runtime), `Seal=yes`.

- Verify:
  ```
  grep -E 'weekly|rotate|compress|dateext' /etc/logrotate.conf
  journalctl --disk-usage
  grep -R '\[Journal\]' /etc/systemd/journald.conf.d/
  ```

---

## Cron / At Restrictions

Only root allowed for cron and at jobs; deny files removed.

- Verify:
  ```
  ls -l /etc/cron.allow /etc/at.allow
  test ! -f /etc/cron.deny && echo ok
  ```

---

## AMI Build Scrub

Before AMI snapshot, `ami-finalize.sh` removes build artefacts and resets
instance state so each customer instance starts clean:

- SSH host keys removed (regenerated on first boot)
- `cloud-init clean --logs` — re-runs keypair injection on first boot
- Shell history truncated for all users
- Log files truncated (logrotate config preserved)
- Machine ID reset (new unique ID generated at first boot)
- Build temp files, pip wheel cache, APT cache, Trivy DB removed

---

## On-Demand Scanning

`sudo ami-scan` runs Trivy (CVE) + OpenSCAP (CIS) and saves results to
`/var/log/ami-scan/`. Use this to verify the posture of a running instance at
any time. See `USAGE.md` for flag reference.
