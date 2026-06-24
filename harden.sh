#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Bharath Kumar Gajjela
set -euo pipefail

# SSH hardening
conf="/etc/ssh/sshd_config"
sudo sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' "$conf"
sudo sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' "$conf"
sudo sed -i 's/^#\?PubkeyAuthentication.*/PubkeyAuthentication yes/' "$conf"
sudo sed -i 's/^#\?ChallengeResponseAuthentication.*/ChallengeResponseAuthentication no/' "$conf"
sudo sed -i 's/^#\?KbdInteractiveAuthentication.*/KbdInteractiveAuthentication no/' "$conf" || true
sudo sed -i 's/^#\?X11Forwarding.*/X11Forwarding no/' "$conf"
sudo sed -i 's/^#\?UseDNS.*/UseDNS no/' "$conf"
sudo sed -i 's/^#\?PrintLastLog.*/PrintLastLog yes/' "$conf"
sudo sed -i 's|^#\?Banner\s\+.*|Banner /etc/issue.net|' "$conf" || echo 'Banner /etc/issue.net' | sudo tee -a "$conf" >/dev/null
sudo sed -i 's/^#\?LoginGraceTime.*/LoginGraceTime 30/' "$conf" || echo 'LoginGraceTime 30' | sudo tee -a "$conf" >/dev/null
sudo sed -i 's/^#\?MaxAuthTries.*/MaxAuthTries 3/' "$conf" || echo 'MaxAuthTries 3' | sudo tee -a "$conf" >/dev/null
sudo sed -i 's/^#\?MaxSessions.*/MaxSessions 4/' "$conf" || echo 'MaxSessions 4' | sudo tee -a "$conf" >/dev/null
sudo sed -i 's/^#\?ClientAliveInterval.*/ClientAliveInterval 300/' "$conf" || echo 'ClientAliveInterval 300' | sudo tee -a "$conf" >/dev/null
sudo sed -i 's/^#\?ClientAliveCountMax.*/ClientAliveCountMax 2/' "$conf" || echo 'ClientAliveCountMax 2' | sudo tee -a "$conf" >/dev/null

# Crypto suites — ordered strongest-first; STIG-required algorithms included
# Ciphers: AEAD ciphers first (chacha20, aes256-gcm), then CTR modes for STIG compliance
sudo grep -q '^Ciphers ' "$conf" || \
  echo 'Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes256-ctr,aes192-ctr' \
  | sudo tee -a "$conf" >/dev/null
# MACs: ETM (encrypt-then-MAC) variants first — prevent padding oracle attacks.
# Non-ETM sha2 variants included for STIG UBTU-22-255030 and legacy client compatibility.
sudo grep -q '^MACs ' "$conf" || \
  echo 'MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com,hmac-sha2-512,hmac-sha2-256' \
  | sudo tee -a "$conf" >/dev/null
# KexAlgorithms: curve25519 (strongest) first; NIST ECDH curves added for STIG UBTU-22-255025
# and enterprise client compatibility (Windows OpenSSH, HSMs, PuTTY require NIST curves).
# diffie-hellman-group14-sha256 excluded: deprecated per NIST SP 800-131A Rev 2.
sudo grep -q '^KexAlgorithms ' "$conf" || \
  echo 'KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org,ecdh-sha2-nistp521,ecdh-sha2-nistp384,ecdh-sha2-nistp256' \
  | sudo tee -a "$conf" >/dev/null
# HostKeyAlgorithms: exclude ssh-rsa (SHA-1) and ssh-dss (DSA); ed25519 and ECDSA only
sudo grep -q '^HostKeyAlgorithms ' "$conf" || \
  echo 'HostKeyAlgorithms ssh-ed25519,ecdsa-sha2-nistp256,ecdsa-sha2-nistp384,rsa-sha2-512,rsa-sha2-256' \
  | sudo tee -a "$conf" >/dev/null
# PubkeyAcceptedAlgorithms: match HostKeyAlgorithms — reject SHA-1 RSA client keys
sudo grep -q '^PubkeyAcceptedAlgorithms ' "$conf" || \
  echo 'PubkeyAcceptedAlgorithms ssh-ed25519,ecdsa-sha2-nistp256,ecdsa-sha2-nistp384,rsa-sha2-512,rsa-sha2-256' \
  | sudo tee -a "$conf" >/dev/null
# STIG UBTU-22-255055: limit rekeying to 1 GB or 1 hour to bound plaintext exposure
sudo grep -q '^RekeyLimit ' "$conf" || echo 'RekeyLimit 1G 1h' | sudo tee -a "$conf" >/dev/null

# Additional SSH controls — CIS 5.2.x
sudo grep -q '^AllowTcpForwarding '     "$conf" || echo 'AllowTcpForwarding no'     | sudo tee -a "$conf" >/dev/null
sudo grep -q '^AllowAgentForwarding '   "$conf" || echo 'AllowAgentForwarding no'   | sudo tee -a "$conf" >/dev/null
sudo grep -q '^PermitUserEnvironment '  "$conf" || echo 'PermitUserEnvironment no'  | sudo tee -a "$conf" >/dev/null
sudo grep -q '^MaxStartups '            "$conf" || echo 'MaxStartups 10:30:60'       | sudo tee -a "$conf" >/dev/null
sudo grep -q '^LogLevel '               "$conf" || echo 'LogLevel INFO'              | sudo tee -a "$conf" >/dev/null
sudo grep -q '^TCPKeepAlive '           "$conf" || echo 'TCPKeepAlive no'            | sudo tee -a "$conf" >/dev/null
sudo grep -q '^PermitEmptyPasswords '   "$conf" || echo 'PermitEmptyPasswords no'   | sudo tee -a "$conf" >/dev/null
sudo grep -q '^IgnoreRhosts '           "$conf" || echo 'IgnoreRhosts yes'           | sudo tee -a "$conf" >/dev/null
sudo grep -q '^HostbasedAuthentication '"$conf" || echo 'HostbasedAuthentication no' | sudo tee -a "$conf" >/dev/null

# CIS 5.2.17 (L2): Restrict SSH access to a dedicated group
sudo groupadd sshusers 2>/dev/null || true
sudo usermod -aG sshusers ubuntu 2>/dev/null || true
sudo grep -q '^AllowGroups ' "$conf" || echo 'AllowGroups sshusers' | sudo tee -a "$conf" >/dev/null

# Validate and reload SSH without dropping the session
sudo sshd -t || { echo 'sshd config test failed'; exit 1; }
sudo systemctl reload ssh || true

# Login banners — STIG UBTU-22-271040: must include consent-to-monitor language
# Enterprise-appropriate wording aligned with STIG intent (non-USG deployment).
sudo tee /etc/issue >/dev/null <<'EOF'
WARNING: This system is for authorized use only. By using this system, you expressly consent to monitoring and recording of all activities. Unauthorized access or use is prohibited and may be subject to criminal prosecution. There is no expectation of privacy on this system. Evidence of unauthorized use may be reported to law enforcement authorities.
EOF
sudo tee /etc/issue.net >/dev/null <<'EOF'
WARNING: This system is for authorized use only. By using this system, you expressly consent to monitoring and recording of all activities. Unauthorized access or use is prohibited and may be subject to criminal prosecution. There is no expectation of privacy on this system. Evidence of unauthorized use may be reported to law enforcement authorities.
EOF
sudo chown root:root /etc/issue /etc/issue.net
sudo chmod 0644 /etc/issue /etc/issue.net

# ==============================
# Remove Insecure & Unnecessary Packages (CIS 2.x / 3.x)
# ==============================
# Server daemons that should not be present on a DS/ML workload AMI
sudo DEBIAN_FRONTEND=noninteractive apt-get -y purge \
  xinetd inetutils-inetd openbsd-inetd \
  xserver-xorg-core xserver-xorg \
  avahi-daemon \
  cups \
  isc-dhcp-server \
  slapd \
  nfs-kernel-server \
  rpcbind \
  samba \
  vsftpd \
  dovecot-core \
  bind9 \
  apache2 \
  nginx \
  squid \
  snmpd \
  tftpd-hpa \
  atftpd \
  telnetd \
  autofs 2>/dev/null || true

# Insecure client tools
sudo DEBIAN_FRONTEND=noninteractive apt-get -y purge \
  telnet \
  rsh-client \
  rsh-redone-client \
  talk \
  ldap-utils \
  nis 2>/dev/null || true

# CIS 1.5.4: Ensure prelink is not installed (can compromise binary integrity checks)
sudo DEBIAN_FRONTEND=noninteractive apt-get -y purge prelink 2>/dev/null || true

sudo apt-get -y autoremove 2>/dev/null || true

# Keep system updated and monitored; upgrade applies all OS security patches (OpenSSL, curl, glibc, etc.)
sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get upgrade -y
sudo apt-get -y install unattended-upgrades chrony auditd ufw
sudo dpkg-reconfigure -f noninteractive unattended-upgrades || true
sudo systemctl enable chrony auditd
sudo systemctl start chrony auditd

# fail2ban: Ubuntu 22.04 ships with all jails disabled; explicitly enable SSH jail
sudo tee /etc/fail2ban/jail.local >/dev/null <<'EOF'
[DEFAULT]
bantime  = 3600
findtime = 300
maxretry = 5

[sshd]
enabled  = true
port     = ssh
filter   = sshd
logpath  = /var/log/auth.log
maxretry = 5
bantime  = 3600
EOF
sudo systemctl enable fail2ban || true
sudo systemctl start fail2ban || true

# UFW: default deny inbound, allow outbound, rate‑limit SSH, enable logging
sudo ufw default deny incoming || true
sudo ufw default allow outgoing || true
sudo ufw allow OpenSSH || true
sudo ufw limit OpenSSH || true
sudo ufw logging low || true
sudo ufw --force enable || true

# System-wide recommended ulimits (apply on new login sessions)
sudo tee /etc/security/limits.d/99-ulimits.conf >/dev/null <<'EOF'
# Increase open files and process limits for all users
* soft nofile 65535
* hard nofile 65535
* soft nproc  16384
* hard nproc  16384
# Disable core dumps by default (set to unlimited for debugging if needed)
* soft core   0
* hard core   0
# Allow some memory locking (in kB); set to unlimited only if required
* soft memlock 65536
* hard memlock 65536

# Ensure the ubuntu user inherits the same
ubuntu soft nofile 65535
ubuntu hard nofile 65535
ubuntu soft nproc  16384
ubuntu hard nproc  16384
EOF

# Kernel file descriptor ceiling (system-wide)
sudo tee /etc/sysctl.d/99-ulimits.conf >/dev/null <<'EOF'
fs.file-max = 2097152
EOF
sudo sysctl --system >/dev/null 2>&1 || true

# systemd default limits so non-login services inherit higher ulimits
sudo install -d -m 0755 /etc/systemd/system.conf.d
sudo tee /etc/systemd/system.conf.d/99-default-limits.conf >/dev/null <<'EOF'
[Manager]
# Match limits from /etc/security/limits.d/99-ulimits.conf
DefaultLimitNOFILE=65535
DefaultLimitNPROC=16384
DefaultLimitCORE=0
DefaultLimitMEMLOCK=65536
EOF
sudo systemctl daemon-reload || true
sudo systemctl daemon-reexec || true

# ==============================
# Global Environment Variables (/etc/environment)
# ==============================
# /etc/environment is read by PAM (pam_env) for ALL sessions — interactive login,
# non-interactive SSH (ssh host 'cmd'), sudo, and cron. Unlike /etc/profile.d/,
# it does not require a login shell, so JAVA_HOME is available everywhere.
#
# JAVA_HOME: needed by any script that references $JAVA_HOME/bin/java directly
#   (Gradle wrapper, Maven, Ant, custom build scripts). The /usr/local/bin/java
#   symlink covers the 'java' command but not $JAVA_HOME references.
# SPARK_HOME / SPARK_LOCAL_DIRS: set here so systemd services (Jupyter, MLflow)
#   that spawn spark-submit inherit the correct paths without a profile.d source.
sudo tee /etc/environment >/dev/null <<'EOF'
JAVA_HOME=/opt/nix/langs/java
SPARK_HOME=/opt/nix/langs/spark
SPARK_LOCAL_DIRS=/opt/spark-local
EOF
# Note: /etc/environment uses KEY=VALUE syntax (no 'export', no shell expansion).
# PATH is intentionally omitted — PAM merges /etc/environment into the session
# environment but PATH is managed separately by /etc/profile and /etc/profile.d/.

# ==============================
# Filesystem & Directory Hardening (CIS L2)
# ==============================

# Ensure sticky bit on world-writable dirs (e.g., /tmp, /var/tmp)
sudo chmod 1777 /tmp /var/tmp || true
sudo find / -xdev -type d -perm -0002 -exec chmod a+t {} + 2>/dev/null || true

# Configure /tmp as tmpfs with secure mount options (applies on next boot)
sudo tee /etc/systemd/system/tmp.mount >/dev/null <<'EOF'
[Unit]
Description=Temporary Directory (/tmp)
Documentation=man:hier(7) man:systemd-tmpfiles(8)
Before=local-fs.target
ConditionPathIsSymbolicLink=!/tmp

[Mount]
What=tmpfs
Where=/tmp
Type=tmpfs
# size=2G: without an explicit cap, tmpfs defaults to 50% of RAM (4 GB on 8 GB
# instances). Spark shuffle, pip downloads, and Nix builds all write to /tmp;
# an unbounded tmpfs can exhaust RAM under concurrent workloads.
Options=mode=1777,strictatime,nosuid,nodev,noexec,size=25%
# size=25%: percentage of physical RAM, not disk. Scales automatically:
#   c6i.xlarge  ( 8 GB RAM) → 2 GB   c6i.2xlarge (16 GB) → 4 GB
#   c6i.4xlarge (32 GB RAM) → 8 GB   c6i.8xlarge (64 GB) → 16 GB
# Fixed size=2G would prevent Spark shuffle on larger instances and is
# unnecessarily restrictive. Spark local dirs are on EBS — see spark-java.sh.

[Install]
WantedBy=multi-user.target
EOF
sudo systemctl enable tmp.mount || true

# Configure /var/tmp as tmpfs with secure mount options (applies on next boot)
sudo tee /etc/systemd/system/var-tmp.mount >/dev/null <<'EOF'
[Unit]
Description=Temporary Directory (/var/tmp)
Documentation=man:hier(7) man:systemd-tmpfiles(8)
Before=local-fs.target
ConditionPathIsSymbolicLink=!/var/tmp

[Mount]
What=tmpfs
Where=/var/tmp
Type=tmpfs
Options=mode=1777,strictatime,nosuid,nodev,noexec,size=10%

[Install]
WantedBy=multi-user.target
EOF
sudo systemctl enable var-tmp.mount || true

# Harden /dev/shm via fstab to use nodev,nosuid,noexec
if ! grep -qE '^\s*tmpfs\s+/dev/shm\s+' /etc/fstab; then
  echo 'tmpfs /dev/shm tmpfs defaults,nosuid,nodev,noexec,mode=1777 0 0' | sudo tee -a /etc/fstab >/dev/null
fi

# Protect symlinks/hardlinks and disable SUID core dumps; ensure ASLR is fully enabled
sudo tee /etc/sysctl.d/99-cis-fs.conf >/dev/null <<'EOF'
fs.protected_hardlinks = 1
fs.protected_symlinks = 1
fs.suid_dumpable = 0
kernel.randomize_va_space = 2
EOF
sudo sysctl --system >/dev/null 2>&1 || true

# Tighten default umask for new shells and logins
sudo tee /etc/profile.d/99-umask.sh >/dev/null <<'EOF'
umask 027
EOF
sudo sed -i 's/^\s*UMASK\s\+.*/UMASK 027/' /etc/login.defs || echo 'UMASK 027' | sudo tee -a /etc/login.defs >/dev/null

# Home directory permissions (CIS L2): 0750 for users under /home, 0700 for root
for dir in /home/*; do
  [ -d "$dir" ] || continue
  user="$(basename "$dir")"
  if id "$user" >/dev/null 2>&1; then
    sudo chown "$user":"$user" "$dir" || true
    sudo chmod 0750 "$dir" || true
    # Remove group/world write within home
    sudo find "$dir" -xdev -type d -perm /022 -exec chmod go-w {} + 2>/dev/null || true
    sudo find "$dir" -xdev -type f -perm /022 -exec chmod go-w {} + 2>/dev/null || true
  fi
done
sudo chmod 0700 /root 2>/dev/null || true

# ==============================
# Kernel Module Blacklisting (CIS 1.1.1.x / 3.5.x)
# ==============================
sudo tee /etc/modprobe.d/cis-blacklist.conf >/dev/null <<'EOF'
# Unused/insecure filesystem types — CIS 1.1.1.x
# squashfs excluded: required by Nix package manager
install cramfs   /bin/true
install freevxfs /bin/true
install jffs2    /bin/true
install hfs      /bin/true
install hfsplus  /bin/true
install udf      /bin/true
install usb-storage /bin/true

# Unused network protocols — CIS 3.5.x
install dccp /bin/true
install sctp /bin/true
install rds  /bin/true
install tipc /bin/true

# CVE-2026-31431 (Copy Fail) — local privilege escalation via AF_ALG AEAD socket.
# Affects kernels 4.14–6.19.12. Interim mitigation per CIS guidance until vendor
# kernel patch is confirmed running (patch installs via unattended-upgrades but
# requires a reboot to activate). algif_aead is not required by any workload on
# this AMI: PyTorch/TF/OpenSSL use userspace crypto, not the kernel AF_ALG socket.
install algif_aead /bin/true
EOF
# Unload any of these already loaded (best-effort; most won't be loaded on a fresh AMI)
for mod in cramfs freevxfs jffs2 hfs hfsplus udf usb-storage dccp sctp rds tipc algif_aead; do
  sudo rmmod "$mod" 2>/dev/null || true
done

# ==============================
# System-Wide TLS Hardening (OpenSSL 3.0)
# ==============================
# Ubuntu 22.04 ships OpenSSL 3.0 with TLS 1.2 as the implicit default, but
# applications can override it. Enforce it explicitly at the system level so
# every process that links against libssl inherits the minimum version and
# cipher strength — regardless of per-app configuration.
#
# MinProtocol = TLSv1.2 : disables TLS 1.0 and TLS 1.1 system-wide
# CipherString = DEFAULT@SECLEVEL=2 : minimum 112-bit security, 2048-bit RSA/DH,
#   224-bit ECC — eliminates RC4, 3DES, export ciphers, and SHA-1 signatures
# SignatureAlgorithms: restrict to SHA-256+ with ECDSA or RSA-PSS
#
# TLS 1.3 cipher suites (TLS_AES_256_GCM_SHA384 etc.) are fixed by the spec
# and not configurable via CipherString — they are always strong.
if [ -f /etc/ssl/openssl.cnf ]; then
  # Patch or insert [system_default_sect] in the openssl.cnf
  if grep -q '^\[system_default_sect\]' /etc/ssl/openssl.cnf; then
    # Update existing section values
    sudo sed -i '/^\[system_default_sect\]/,/^\[/ {
      s/^MinProtocol\s*=.*/MinProtocol = TLSv1.2/
      s/^CipherString\s*=.*/CipherString = DEFAULT@SECLEVEL=2/
    }' /etc/ssl/openssl.cnf
    # Append if keys don't exist yet in the section
    grep -q '^MinProtocol' /etc/ssl/openssl.cnf || \
      sudo sed -i '/^\[system_default_sect\]/a MinProtocol = TLSv1.2' /etc/ssl/openssl.cnf
    grep -q '^CipherString' /etc/ssl/openssl.cnf || \
      sudo sed -i '/^\[system_default_sect\]/a CipherString = DEFAULT@SECLEVEL=2' /etc/ssl/openssl.cnf
  else
    # Append a new system_default_sect
    sudo tee -a /etc/ssl/openssl.cnf >/dev/null <<'OPENSSLEOF'

[system_default_sect]
MinProtocol = TLSv1.2
CipherString = DEFAULT@SECLEVEL=2
OPENSSLEOF
  fi

  # Point the ssl_conf block at system_default_sect if not already wired up
  if ! grep -q 'system_default\s*=' /etc/ssl/openssl.cnf; then
    sudo sed -i '/^\[ssl_default_sect\]\|^\[ssl_sect\]/a system_default = system_default_sect' \
      /etc/ssl/openssl.cnf 2>/dev/null || true
  fi
fi

# ==============================
# Network Stack Hardening (CIS)
# ==============================
sudo tee /etc/sysctl.d/99-cis-net.conf >/dev/null <<'EOF'
# IPv4
net.ipv4.ip_forward = 0
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.secure_redirects = 0
net.ipv4.conf.default.secure_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1
net.ipv4.tcp_syncookies = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1

# IPv6 (do not disable IPv6; harden RA/redirects)
net.ipv6.conf.all.accept_ra = 0
net.ipv6.conf.default.accept_ra = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0

# Additional hardening
kernel.kptr_restrict = 2
kernel.dmesg_restrict = 1
kernel.perf_event_paranoid = 3
kernel.kexec_load_disabled = 1
kernel.yama.ptrace_scope = 1
fs.protected_fifos = 2
fs.protected_regular = 2
EOF
sudo sysctl --system >/dev/null 2>&1 || true

# ==============================
# Base Performance Tuning
# ==============================
# Conservative tuning that benefits any server workload: reduced swap pressure,
# smarter writeback, larger network buffers, deeper inotify watch limits.
# Security sysctl files (99-cis-*.conf) take higher precedence where they overlap.
sudo tee /etc/sysctl.d/60-base-perf.conf >/dev/null <<'EOF'
# ── Memory ────────────────────────────────────────────────────────────────────
# Swap only under real memory pressure; EBS-backed swap is slow and hurts
# any workload that loses data from RAM unexpectedly.
vm.swappiness = 10

# Allow up to 40% of RAM as dirty before blocking writers;
# start background writeback at 10%. Reduces latency spikes on
# large sequential writes (dataset saves, model checkpoints).
vm.dirty_ratio = 40
vm.dirty_background_ratio = 10

# ── Network ───────────────────────────────────────────────────────────────────
# Larger socket listen backlog for Jupyter, MLflow, REST API servers.
net.core.somaxconn = 65535
net.core.netdev_max_backlog = 5000
net.ipv4.tcp_max_syn_backlog = 8192

# Reclaim TIME_WAIT sockets faster; ML jobs open many short-lived connections
# to S3, SageMaker endpoints, and package mirrors.
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_tw_reuse = 1

# ── Filesystem ────────────────────────────────────────────────────────────────
# Jupyter, MLflow, and PyTorch DataLoader use inotify to watch dataset dirs.
# Default kernel limit (8192) is too low for repos with large file trees.
fs.inotify.max_user_watches = 131072
fs.inotify.max_user_instances = 512
EOF
sudo sysctl --system >/dev/null 2>&1 || true

# ==============================
# Auditd Hardening (CIS)
# ==============================
sudo tee /etc/audit/rules.d/99-hardening.rules >/dev/null <<'EOF'
## Identity and auth
-w /etc/passwd -p wa -k identity
-w /etc/group -p wa -k identity
-w /etc/shadow -p wa -k identity
-w /etc/gshadow -p wa -k identity
-w /etc/security/opasswd -p wa -k identity
-w /etc/sudoers -p wa -k scope
-w /etc/sudoers.d/ -p wa -k scope
-w /var/log/sudo.log -p wa -k actions
## Network and system config
-w /etc/ssh/sshd_config -p wa -k sshd
-w /etc/sysctl.conf -p wa -k sysctl
-w /etc/sysctl.d/ -p wa -k sysctl
-w /etc/audit/ -p wa -k audit
-w /etc/cron.allow -p wa -k cron
-w /etc/at.allow -p wa -k at
## Time changes
-a always,exit -F arch=b64 -S adjtimex,settimeofday,clock_settime -k time-change
-a always,exit -F arch=b32 -S adjtimex,settimeofday,clock_settime -k time-change
-w /etc/localtime -p wa -k time-change
## Kernel module loading
-a always,exit -F arch=b64 -S init_module,finit_module,delete_module -k modules
-a always,exit -F arch=b32 -S init_module,finit_module,delete_module -k modules
## MAC policy
-w /etc/apparmor/ -p wa -k mac-policy
## Privileged command execution — CIS 4.1.3
-w /usr/bin/sudo -p x -k sudo
## User and group management — CIS 4.1.6
-w /usr/sbin/useradd -p x -k user-mgmt
-w /usr/sbin/usermod -p x -k user-mgmt
-w /usr/sbin/userdel -p x -k user-mgmt
-w /usr/sbin/groupadd -p x -k user-mgmt
-w /usr/sbin/groupmod -p x -k user-mgmt
-w /usr/sbin/groupdel -p x -k user-mgmt
-w /usr/bin/passwd -p x -k user-mgmt
## Network environment changes — CIS 4.1.5
-a always,exit -F arch=b64 -S sethostname,setdomainname -k network-change
-a always,exit -F arch=b32 -S sethostname,setdomainname -k network-change
-w /etc/hosts -p wa -k network-change
-w /etc/network -p wa -k network-change
## Login and logout events — CIS 4.1.7
-w /var/log/faillog -p wa -k logins
-w /var/log/lastlog -p wa -k logins
## Session initiation — CIS 4.1.8
-w /var/run/utmp -p wa -k session
-w /var/log/wtmp -p wa -k session
-w /var/log/btmp -p wa -k session
## DAC permission modifications — CIS 4.1.9
-a always,exit -F arch=b64 -S chmod,fchmod,fchmodat -F auid>=1000 -F auid!=4294967295 -k perm-mod
-a always,exit -F arch=b32 -S chmod,fchmod,fchmodat -F auid>=1000 -F auid!=4294967295 -k perm-mod
-a always,exit -F arch=b64 -S chown,fchown,lchown,fchownat -F auid>=1000 -F auid!=4294967295 -k perm-mod
-a always,exit -F arch=b32 -S chown,fchown,lchown,fchownat -F auid>=1000 -F auid!=4294967295 -k perm-mod
-a always,exit -F arch=b64 -S setxattr,lsetxattr,fsetxattr,removexattr,lremovexattr,fremovexattr -F auid>=1000 -F auid!=4294967295 -k perm-mod
-a always,exit -F arch=b32 -S setxattr,lsetxattr,fsetxattr,removexattr,lremovexattr,fremovexattr -F auid>=1000 -F auid!=4294967295 -k perm-mod
## Unsuccessful unauthorized file access — CIS 4.1.10
-a always,exit -F arch=b64 -S creat,open,openat,truncate,ftruncate -F exit=-EACCES -F auid>=1000 -F auid!=4294967295 -k access
-a always,exit -F arch=b32 -S creat,open,openat,truncate,ftruncate -F exit=-EACCES -F auid>=1000 -F auid!=4294967295 -k access
-a always,exit -F arch=b64 -S creat,open,openat,truncate,ftruncate -F exit=-EPERM -F auid>=1000 -F auid!=4294967295 -k access
-a always,exit -F arch=b32 -S creat,open,openat,truncate,ftruncate -F exit=-EPERM -F auid>=1000 -F auid!=4294967295 -k access
## Successful filesystem mounts — CIS 4.1.12
-a always,exit -F arch=b64 -S mount -F auid>=1000 -F auid!=4294967295 -k mounts
-a always,exit -F arch=b32 -S mount -F auid>=1000 -F auid!=4294967295 -k mounts
## File deletion by users — CIS 4.1.13
-a always,exit -F arch=b64 -S unlink,unlinkat,rename,renameat -F auid>=1000 -F auid!=4294967295 -k delete
-a always,exit -F arch=b32 -S unlink,unlinkat,rename,renameat -F auid>=1000 -F auid!=4294967295 -k delete
## STIG supplemental: setuid/setgid via execve — catches privilege escalation not caught by path rules
-a always,exit -F arch=b64 -S execve -C uid!=euid -F euid=0 -k setuid
-a always,exit -F arch=b32 -S execve -C uid!=euid -F euid=0 -k setuid
-a always,exit -F arch=b64 -S execve -C gid!=egid -F egid=0 -k setgid
-a always,exit -F arch=b32 -S execve -C gid!=egid -F egid=0 -k setgid
## STIG: additional user/group management commands
-w /usr/bin/chage -p x -k user-mgmt
-w /usr/sbin/chpasswd -p x -k user-mgmt
-w /usr/bin/newgrp -p x -k user-mgmt
-w /usr/bin/chsh -p x -k user-mgmt
-w /usr/bin/chfn -p x -k user-mgmt
## STIG: sudo timestamp directory — Ubuntu 22.04 path (not /var/db/sudo which is BSD/RHEL)
-w /var/lib/sudo/ts -p wa -k sudo_timestamp
## Make audit config immutable (must be last rule)
-e 2
EOF
sudo augenrules --load >/dev/null 2>&1 || sudo service auditd restart || true

# CIS 4.1.11: Generate audit rules for all SUID/SGID executables found on the filesystem
find / -xdev \( -perm -4000 -o -perm -2000 \) -type f 2>/dev/null | \
  awk '{print "-a always,exit -F path=" $1 " -F perm=x -F auid>=1000 -F auid!=4294967295 -k privileged"}' | \
  sudo tee /etc/audit/rules.d/99-privileged.rules >/dev/null

# CIS 4.1.2: auditd storage and overflow settings
#
# max_log_file_action = rotate (not keep_logs): keep_logs ignores num_logs per the
# auditd man page, so audit logs grow unbounded until disk fills and halt triggers.
# rotate + num_logs = 20 caps audit log storage at ~640 MB (20 × 32 MB).
# disk_full_action = halt is CIS-required and kept — the bounded log size ensures
# disk fills only from other sources, giving operators time to respond.
sudo sed -i 's/^max_log_file_action.*/max_log_file_action = rotate/' /etc/audit/auditd.conf || true

# Cap individual audit log file size and total number of retained files
grep -q '^max_log_file\b' /etc/audit/auditd.conf \
  && sudo sed -i 's/^max_log_file\b.*/max_log_file = 32/'    /etc/audit/auditd.conf \
  || echo 'max_log_file = 32'    | sudo tee -a /etc/audit/auditd.conf >/dev/null
grep -q '^num_logs\b' /etc/audit/auditd.conf \
  && sudo sed -i 's/^num_logs\b.*/num_logs = 20/'             /etc/audit/auditd.conf \
  || echo 'num_logs = 20'        | sudo tee -a /etc/audit/auditd.conf >/dev/null

# space_left_action = syslog: email requires an MTA which is not installed;
# silent failure means the operator never learns the disk is filling.
sudo sed -i 's/^space_left_action.*/space_left_action = syslog/'         /etc/audit/auditd.conf || true
sudo sed -i 's/^admin_space_left_action.*/admin_space_left_action = halt/' /etc/audit/auditd.conf || true
sudo sed -i 's/^disk_full_action.*/disk_full_action = halt/'              /etc/audit/auditd.conf || true
sudo sed -i 's/^disk_error_action.*/disk_error_action = halt/'            /etc/audit/auditd.conf || true

# Explicit low-watermark thresholds (MB free before warning/halt)
grep -q '^space_left\b' /etc/audit/auditd.conf \
  && sudo sed -i 's/^space_left\b.*/space_left = 500/'       /etc/audit/auditd.conf \
  || echo 'space_left = 500'     | sudo tee -a /etc/audit/auditd.conf >/dev/null
grep -q '^admin_space_left\b' /etc/audit/auditd.conf \
  && sudo sed -i 's/^admin_space_left\b.*/admin_space_left = 100/' /etc/audit/auditd.conf \
  || echo 'admin_space_left = 100' | sudo tee -a /etc/audit/auditd.conf >/dev/null
sudo augenrules --load >/dev/null 2>&1 || sudo service auditd restart || true

# Enable audit at boot (GRUB)
if [ -f /etc/default/grub ]; then
  sudo sed -i 's/\(GRUB_CMDLINE_LINUX\(_DEFAULT\)\?=\)"/\1"audit=1 /' /etc/default/grub || true
  sudo update-grub >/dev/null 2>&1 || true
fi

# CIS 1.4.2: Ensure GRUB config file has secure permissions
if [ -f /boot/grub/grub.cfg ]; then
  sudo chown root:root /boot/grub/grub.cfg || true
  sudo chmod og-rwx /boot/grub/grub.cfg || true
fi

# STIG UBTU-22-211045: GRUB superuser password (defense-in-depth for serial console)
# Generates a random password at build time — hash stored in GRUB, cleartext discarded.
# On EC2 Nitro there is no physical console; this guards the AWS Serial Console.
if command -v grub-mkpasswd-pbkdf2 >/dev/null 2>&1; then
  _grub_pass="$(openssl rand -base64 24)"
  _grub_hash="$(printf '%s\n%s\n' "${_grub_pass}" "${_grub_pass}" \
    | grub-mkpasswd-pbkdf2 2>/dev/null \
    | awk '/PBKDF2 hash/{print $NF}')"
  if [ -n "${_grub_hash}" ]; then
    sudo tee /etc/grub.d/40_custom_password >/dev/null <<GRUBEOF
set superusers="grubadmin"
password_pbkdf2 grubadmin ${_grub_hash}
GRUBEOF
    sudo chmod 700 /etc/grub.d/40_custom_password
    # Mark all auto-generated boot entries as unrestricted so normal boot does not
    # prompt for the GRUB password. Without this, EC2 instances hang at GRUB on
    # every boot waiting for credentials. The password still protects the GRUB
    # editor and command line (single-user / rescue mode).
    sudo sed -i 's/\${CLASS} \$menuentry_id_option/\${CLASS} --unrestricted \$menuentry_id_option/' \
      /etc/grub.d/10_linux 2>/dev/null || true
    sudo update-grub >/dev/null 2>&1 || true
  fi
  unset _grub_pass _grub_hash
fi

# ==============================
# AppArmor / AIDE / PAM & Auth Policies (CIS)
# ==============================
sudo DEBIAN_FRONTEND=noninteractive apt-get -y install apparmor apparmor-utils aide aide-common libpam-pwquality >/dev/null 2>&1 || true
sudo systemctl enable apparmor >/dev/null 2>&1 || true
sudo aa-enforce /etc/apparmor.d/* >/dev/null 2>&1 || true

# Initialize AIDE DB (may take time)
sudo aideinit >/dev/null 2>&1 || true
if [ -f /var/lib/aide/aide.db.new ]; then
  sudo mv /var/lib/aide/aide.db.new /var/lib/aide/aide.db || true
fi

# Password quality and aging
sudo sed -i 's/^#\?minlen.*/minlen = 14/' /etc/security/pwquality.conf || true
sudo sed -i 's/^#\?dcredit.*/dcredit = -1/' /etc/security/pwquality.conf || true
sudo sed -i 's/^#\?ucredit.*/ucredit = -1/' /etc/security/pwquality.conf || true
sudo sed -i 's/^#\?ocredit.*/ocredit = -1/' /etc/security/pwquality.conf || true
sudo sed -i 's/^#\?lcredit.*/lcredit = -1/' /etc/security/pwquality.conf || true
sudo sed -i 's/^#\?remember.*/remember = 5/' /etc/security/pwquality.conf || echo 'remember = 5' | sudo tee -a /etc/security/pwquality.conf >/dev/null

sudo sed -i 's/^#\?PASS_MAX_DAYS.*/PASS_MAX_DAYS   365/' /etc/login.defs || true
sudo sed -i 's/^#\?PASS_MIN_DAYS.*/PASS_MIN_DAYS   1/' /etc/login.defs || true
sudo sed -i 's/^#\?PASS_WARN_AGE.*/PASS_WARN_AGE  7/' /etc/login.defs || true

# CIS 5.3.4: Ensure SHA-512 is the password hashing algorithm
sudo sed -i 's/^#\?ENCRYPT_METHOD.*/ENCRYPT_METHOD SHA512/' /etc/login.defs || \
  echo 'ENCRYPT_METHOD SHA512' | sudo tee -a /etc/login.defs >/dev/null
# Replace yescrypt with sha512 in PAM — STIG UBTU-22-611035 explicitly requires SHA-512.
# yescrypt is a stronger memory-hard KDF, but STIG predates it and mandates sha512.
sudo sed -i 's/\byescrypt\b/sha512/g' /etc/pam.d/common-password 2>/dev/null || true

# PAM: enforce pwquality (ensure line exists)
if ! grep -q 'pam_pwquality.so' /etc/pam.d/common-password; then
  echo 'password requisite pam_pwquality.so retry=3' | sudo tee -a /etc/pam.d/common-password >/dev/null
fi

# PAM: faillock (account lockout) via pam-auth-update.
# The previous sed-based approach had a bug: two `sed -i '1i...'` inserts produce authsucc
# before authfail in the file, making the lockout logic backwards. pam-auth-update inserts
# modules in the correct Ubuntu 22.04 order: preauth → pam_unix → authfail → authsucc.
sudo tee /usr/share/pam-configs/faillock >/dev/null <<'EOF'
Name: Enable pam_faillock
Default: yes
Priority: 0
Auth-Type: Primary
Auth:
        [default=die] pam_faillock.so authfail audit deny=5 unlock_time=900
Auth-Initial:
        required pam_faillock.so preauth audit deny=5 unlock_time=900
Account-Type: Additional
Account:
        required pam_faillock.so
EOF
sudo DEBIAN_FRONTEND=noninteractive pam-auth-update --enable faillock

# STIG UBTU-22-411025: require re-authentication on every sudo invocation
echo 'Defaults timestamp_timeout=0' | sudo tee /etc/sudoers.d/99-stig-timeout >/dev/null
sudo chmod 440 /etc/sudoers.d/99-stig-timeout

# su restriction to sudo group
if grep -q '^auth' /etc/pam.d/su; then
  sudo sed -i '/pam_wheel.so/d' /etc/pam.d/su || true
  printf 'auth required pam_wheel.so use_uid group=sudo\n' | sudo tee -a /etc/pam.d/su >/dev/null
fi

# Cron/At restrictions
echo 'root' | sudo tee /etc/cron.allow >/dev/null
sudo chown root:root /etc/cron.allow && sudo chmod 640 /etc/cron.allow || true
sudo rm -f /etc/cron.deny 2>/dev/null || true
echo 'root' | sudo tee /etc/at.allow >/dev/null
sudo chown root:root /etc/at.allow && sudo chmod 640 /etc/at.allow || true
sudo rm -f /etc/at.deny 2>/dev/null || true

# Permissions on critical system files
sudo chown root:root /etc/passwd /etc/group /etc/shadow /etc/gshadow 2>/dev/null || true
sudo chmod 0644 /etc/passwd /etc/group 2>/dev/null || true
sudo chmod 0640 /etc/shadow /etc/gshadow 2>/dev/null || true

# STIG directory and file permission hardening
# sshd_config: root-only read (STIG UBTU-22-255010)
sudo chmod 0600 /etc/ssh/sshd_config 2>/dev/null || true
sudo chown root:root /etc/ssh/sshd_config 2>/dev/null || true
# Key system directories: root-owned, no world-write
for d in /etc /usr /var /boot; do
  [ -d "$d" ] && sudo chown root:root "$d" && sudo chmod o-w "$d" 2>/dev/null || true
done
# Audit unowned/ungrouped files on system paths and assign to root
find /etc /usr /var -xdev \( -nouser -o -nogroup \) 2>/dev/null | while read -r f; do
  sudo chown root:root "$f" 2>/dev/null || true
done
# Ensure /etc/passwd- /etc/shadow- backup files have tight permissions
for f in /etc/passwd- /etc/group- /etc/shadow- /etc/gshadow-; do
  [ -f "$f" ] && sudo chmod 0600 "$f" && sudo chown root:root "$f" 2>/dev/null || true
done

# Logrotate: enable compression and sane defaults globally
if [ -f /etc/logrotate.conf ]; then
  sudo sed -i 's/^#\?weekly.*/weekly/' /etc/logrotate.conf || true
  if grep -qE '^rotate ' /etc/logrotate.conf; then
    sudo sed -i 's/^rotate .*/rotate 14/' /etc/logrotate.conf || true
  else
    echo 'rotate 14' | sudo tee -a /etc/logrotate.conf >/dev/null
  fi
  # Uncomment compress if commented out, otherwise append; previous BRE regex was incorrect
  sudo sed -i 's/^#\s*compress\s*$/compress/' /etc/logrotate.conf || true
  grep -q '^compress$' /etc/logrotate.conf || echo 'compress' | sudo tee -a /etc/logrotate.conf >/dev/null
  grep -q '^delaycompress' /etc/logrotate.conf || echo 'delaycompress' | sudo tee -a /etc/logrotate.conf >/dev/null
  grep -q '^dateext' /etc/logrotate.conf || echo 'dateext' | sudo tee -a /etc/logrotate.conf >/dev/null
  grep -q '^su ' /etc/logrotate.conf || echo 'su root syslog' | sudo tee -a /etc/logrotate.conf >/dev/null
  # maxsize: rotate immediately if a log exceeds this size even mid-week.
  # Prevents a runaway process from filling disk between weekly rotation cycles.
  grep -q '^maxsize' /etc/logrotate.conf || echo 'maxsize 100M' | sudo tee -a /etc/logrotate.conf >/dev/null
fi

# Logrotate rules for UFW (if not present)
if [ ! -f /etc/logrotate.d/ufw ]; then
  sudo tee /etc/logrotate.d/ufw >/dev/null <<'EOF'
/var/log/ufw.log {
    weekly
    rotate 8
    missingok
    notifempty
    compress
    delaycompress
    copytruncate
}
EOF
fi

# Journald: persistent storage with compression, size caps, and disk headroom
sudo install -d -m 0755 /etc/systemd/journald.conf.d
sudo tee /etc/systemd/journald.conf.d/99-compression.conf >/dev/null <<'EOF'
[Journal]
Storage=persistent
Compress=yes
Seal=yes
# Hard cap on total journal size
SystemMaxUse=500M
RuntimeMaxUse=200M
# Limit individual journal file size before archiving (default 128M is too large)
SystemMaxFileSize=64M
# Always keep at least 1 GB free for other writers (EBS root vol is 24 GB)
SystemKeepFree=1G
# Age out entries older than 2 weeks regardless of size cap
MaxRetentionSec=2weeks
MaxFileSec=1week
EOF
sudo systemctl restart systemd-journald || true

# ==============================
# Rsyslog (CIS 4.2.1)
# ==============================
sudo apt-get -y install rsyslog >/dev/null 2>&1 || true
sudo systemctl enable rsyslog || true
sudo systemctl start rsyslog || true
# CIS 4.2.1.3: restrict default log file permissions
grep -q '^\$FileCreateMode' /etc/rsyslog.conf || echo '$FileCreateMode 0640' | sudo tee -a /etc/rsyslog.conf >/dev/null

# Prevent auditd events from being double-logged via rsyslog.
# audisp forwards audit records to syslog; without this rule rsyslog writes them
# to /var/log/syslog AND /var/log/auth.log while auditd already writes to
# /var/log/audit/audit.log — doubling audit log disk usage.
if ! grep -q 'audispd' /etc/rsyslog.conf 2>/dev/null; then
  sudo tee -a /etc/rsyslog.conf >/dev/null <<'EOF'
# Drop auditd/audisp messages — already captured in /var/log/audit/
if $programname == 'audispd' then stop
if $programname == 'audit' then stop
EOF
fi
sudo systemctl restart rsyslog || true

# ==============================
# Account and Environment Security (CIS 5.4)
# ==============================

# CIS 5.4.1.4: Lock accounts inactive for more than 30 days
sudo useradd -D -f 30
sudo sed -i 's/^INACTIVE=.*/INACTIVE=30/' /etc/default/useradd 2>/dev/null || \
  echo 'INACTIVE=30' | sudo tee -a /etc/default/useradd >/dev/null

# CIS 5.4.4: Enforce shell timeout of 900 seconds for all interactive sessions
sudo tee /etc/profile.d/99-timeout.sh >/dev/null <<'EOF'
TMOUT=600
readonly TMOUT
export TMOUT
EOF
sudo chmod 644 /etc/profile.d/99-timeout.sh

# CIS 5.4.2: Lock non-root system accounts (UID < 1000) that still have login shells
awk -F: '($3 < 1000 && $1 != "root" && $7 !~ /(nologin|false)/) {print $1}' /etc/passwd | \
  while read -r sysuser; do
    sudo usermod -L -s /usr/sbin/nologin "$sysuser" 2>/dev/null || true
  done

# CIS 6.2.1: Ensure accounts with empty passwords are locked
sudo awk -F: '($2 == "") {print $1}' /etc/shadow 2>/dev/null | while read -r emptyuser; do
  [ -n "$emptyuser" ] && { sudo passwd -l "$emptyuser" 2>/dev/null || true; }
done

# ==============================
# Cron Directory Permissions (CIS 5.1)
# ==============================
for cronpath in /etc/crontab /etc/cron.hourly /etc/cron.daily /etc/cron.weekly /etc/cron.monthly /etc/cron.d; do
  if [ -e "$cronpath" ]; then
    sudo chown root:root "$cronpath" || true
    sudo chmod og-rwx "$cronpath" || true
  fi
done

# ==============================
# AIDE Integrity Check Schedule (CIS 1.3.2)
# ==============================
sudo tee /etc/cron.d/aide-check >/dev/null <<'EOF'
0 5 * * * root /usr/bin/aide --check 2>&1 | /usr/bin/logger -t aide-check
EOF
sudo chown root:root /etc/cron.d/aide-check
sudo chmod 600 /etc/cron.d/aide-check

# ==============================
# Service Audit — Boot Footprint Reduction
# ==============================
# Two categories:
#   A. Disable entirely — services with zero utility on EC2 Nitro instances.
#      Saves boot time, eliminates outbound network noise, shrinks attack surface.
#   B. Boot-optional — useful on demand but not needed at startup.
#      Re-enable with: sudo systemctl enable --now <service>

# ── A. Disable entirely ──────────────────────────────────────────────────────

# fwupd: Linux Vendor Firmware Service — updates device firmware from lvfs.fwupd.org.
# EC2 manages firmware through the Nitro hypervisor; fwupd finds nothing to update
# and makes outbound HTTPS calls on every boot (fwupd-refresh.timer).
for svc in fwupd.service fwupd-refresh.timer fwupd-refresh.service; do
  sudo systemctl disable "$svc" 2>/dev/null || true
  sudo systemctl mask "$svc" 2>/dev/null || true
done

# apport / whoopsie: Ubuntu crash reporter and error telemetry to Canonical.
# No value on production servers; privacy concern and adds outbound network dependency.
for svc in apport.service whoopsie.service; do
  sudo systemctl disable "$svc" 2>/dev/null || true
  sudo systemctl mask "$svc" 2>/dev/null || true
done
# Disable apport kernel hook as well
sudo sed -i 's/^enabled=.*/enabled=0/' /etc/default/apport 2>/dev/null || true

# multipathd: device-mapper multipath for SAN storage (FC/iSCSI HBAs).
# EC2 Nitro NVMe presents single-path block devices; multipathd spends 2-3s at boot
# scanning for multipath devices that don't exist, then runs idle forever.
for svc in multipathd.service multipathd.socket; do
  sudo systemctl disable "$svc" 2>/dev/null || true
  sudo systemctl mask "$svc" 2>/dev/null || true
done

# iscsid: iSCSI initiator daemon — connects to iSCSI SANs over TCP.
# EC2 uses NVMe-over-PCIe (Nitro), not iSCSI. Dead weight at boot.
sudo systemctl disable iscsid.service 2>/dev/null || true
sudo systemctl mask iscsid.service 2>/dev/null || true

# motd-news: fetches Ubuntu "news" from motd.ubuntu.com on every boot (timer-driven).
# Adds an outbound DNS + HTTPS call to the critical boot path with no operational value.
for svc in motd-news.service motd-news.timer; do
  sudo systemctl disable "$svc" 2>/dev/null || true
  sudo systemctl mask "$svc" 2>/dev/null || true
done

# systemd-timesyncd: built-in NTP client — conflicts with chrony (both registered as NTP).
# chrony is already enabled (better accuracy, RFC 5905 NTPv4, handles leap seconds).
# Having two NTP clients causes subtle clock-skew fights; mask timesyncd to prevent
# re-enablement on package updates.
sudo systemctl disable systemd-timesyncd.service 2>/dev/null || true
sudo systemctl mask systemd-timesyncd.service 2>/dev/null || true

# ── B. Boot-optional (installed, autostart disabled) ─────────────────────────
# These services are useful on demand. To re-enable:
#   sudo systemctl enable --now <service>

# atd: the `at` one-shot job scheduler.
# Cron handles all scheduled work in this AMI; `at` is rarely needed.
# Re-enable if you need: echo "my-script.sh" | at now + 5 minutes
sudo systemctl disable atd.service 2>/dev/null || true

# snapd: Canonical's snap package manager.
# All packages in this AMI are managed by Nix. Snapd adds a slow mount namespace
# setup on every boot (~1-2s) and runs background refresh daemons for zero benefit.
# Re-enable if a specific snap package is needed: sudo systemctl enable --now snapd
for svc in snapd.service snapd.socket snapd.seeded.service snapd.apparmor.service; do
  sudo systemctl disable "$svc" 2>/dev/null || true
done

# pollinate: seeds /dev/urandom from entropy.ubuntu.com on first boot.
# EC2 Nitro has hardware RNG (virtio-rng) providing kernel entropy from boot.
# After the first instance launch the seed file exists and pollinate is a no-op anyway.
# Re-enable if deploying to an environment without hardware RNG.
sudo systemctl disable pollinate.service 2>/dev/null || true

# STIG UBTU-22-211040: disable Ctrl-Alt-Delete reboot in GUI and console
sudo systemctl mask ctrl-alt-del.target 2>/dev/null || true
sudo systemctl daemon-reload 2>/dev/null || true

echo "Service audit complete."
