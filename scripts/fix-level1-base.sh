#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

# Baseline CIS-aligned hardening controls shared by Level 1 and Level 2.
# This script is intended to run on the base AMI after the general harden.sh
# pass, and before the image is finalized.

if [[ "$(id -u)" -ne 0 ]]; then
  echo "ERROR: fix-level1-base.sh must run as root" >&2
  exit 1
fi

ensure_login_defs() {
  local key="$1" value="$2"
  if grep -qE "^[#[:space:]]*${key}[[:space:]]+" /etc/login.defs; then
    sed -i "s|^[#[:space:]]*${key}[[:space:]].*|${key} ${value}|" /etc/login.defs
  else
    printf '%s %s\n' "$key" "$value" >> /etc/login.defs
  fi
}

echo "=== Level 1 base remediation ==="

export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y apparmor apparmor-utils auditd audispd-plugins libpam-pwquality nftables rsyslog systemd-timesyncd || true
apt-get purge -y ufw rsync ftp || true

systemctl enable --now apparmor || true
systemctl enable --now auditd || true
systemctl enable --now rsyslog || true
systemctl enable --now nftables || true

systemctl disable --now chrony 2>/dev/null || true
systemctl disable --now chronyd 2>/dev/null || true
systemctl unmask systemd-timesyncd || true
systemctl enable --now systemd-timesyncd || true

mkdir -p /etc/security/pwquality.conf.d
cat >/etc/security/pwquality.conf.d/99-cis-level1.conf <<'EOF'
minlen = 14
minclass = 4
dcredit = -1
ucredit = -1
lcredit = -1
ocredit = -1
difok = 8
dictcheck = 1
maxrepeat = 3
maxsequence = 3
enforcing = 1
enforce_for_root
retry = 3
EOF

ensure_login_defs ENCRYPT_METHOD SHA512
ensure_login_defs PASS_MAX_DAYS 365
ensure_login_defs PASS_MIN_DAYS 1
ensure_login_defs PASS_WARN_AGE 7

sed -i 's/\byescrypt\b/sha512/g' /etc/pam.d/common-password || true

cat >/usr/share/pam-configs/local-pwhistory <<'EOF'
Name: Enforce password history
Default: yes
Priority: 1024
Password-Type: Primary
Password:
	required pam_pwhistory.so remember=5 use_authtok enforce_for_root
EOF

cat >/usr/share/pam-configs/faillock <<'EOF'
Name: Enable pam_faillock
Default: yes
Priority: 0
Auth-Type: Primary
Auth-Initial:
	required pam_faillock.so preauth silent audit deny=5 unlock_time=900
Auth:
	[default=die] pam_faillock.so authfail audit deny=5 unlock_time=900
Account-Type: Additional
Account:
	required pam_faillock.so
EOF

DEBIAN_FRONTEND=noninteractive pam-auth-update --enable faillock --enable local-pwhistory --force || true

if ! grep -q 'pam_pwquality.so' /etc/pam.d/common-password; then
  sed -i '/pam_unix.so/i password\trequisite\t\t\tpam_pwquality.so retry=3' /etc/pam.d/common-password
fi

awk -F: '($2 == "") {print $1}' /etc/shadow | while read -r user; do
  [[ -n "$user" ]] && passwd -l "$user" || true
done

mkdir -p /etc/sudoers.d
cat >/etc/sudoers.d/99-cis-sudo <<'EOF'
Defaults timestamp_timeout=0
Defaults logfile="/var/log/sudo.log"
EOF
chmod 440 /etc/sudoers.d/99-cis-sudo
touch /var/log/sudo.log
chmod 600 /var/log/sudo.log
chown root:root /var/log/sudo.log

groupadd -f sugroup
gpasswd -M '' sugroup || true
sed -i '/pam_wheel.so/d' /etc/pam.d/su || true
printf 'auth required pam_wheel.so use_uid group=sugroup\n' >> /etc/pam.d/su

echo 'umask 027' >/etc/profile.d/99-umask.sh
chmod 644 /etc/profile.d/99-umask.sh
grep -q 'umask 027' /etc/bash.bashrc 2>/dev/null || printf '\numask 027\n' >> /etc/bash.bashrc

awk -F: '($3 >= 1000 && $7 !~ /(nologin|false)/) {print $1 ":" $6}' /etc/passwd | \
while IFS=: read -r user home; do
  [[ -d "$home" ]] || continue
  find "$home" -maxdepth 1 -type f -name '.*' ! -name '.bash_logout' -print0 2>/dev/null \
    | xargs -0 -r chown "$user:$(id -gn "$user")" || true
  find "$home" -maxdepth 1 -type f -name '.*' ! -name '.bash_logout' -print0 2>/dev/null \
    | xargs -0 -r chmod 740 || true
  [[ -f "$home/.bash_history" ]] && chmod 600 "$home/.bash_history" || true
done

mkdir -p /etc/ssh/sshd_config.d
cat >/etc/ssh/sshd_config.d/99-cis-level1.conf <<'EOF'
PermitRootLogin no
ClientAliveInterval 15
ClientAliveCountMax 3
EOF
chmod 600 /etc/ssh/sshd_config.d/99-cis-level1.conf
chown root:root /etc/ssh/sshd_config.d/99-cis-level1.conf
systemctl restart ssh || true

cat >/etc/sysctl.d/99-cis-level1.conf <<'EOF'
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv6.conf.all.accept_source_route = 0
net.ipv6.conf.default.accept_source_route = 0
net.ipv6.conf.all.forwarding = 0
EOF
sysctl --system >/dev/null || true

mkdir -p /etc/systemd/journald.conf.d
cat >/etc/systemd/journald.conf.d/99-cis-forwarding.conf <<'EOF'
[Journal]
ForwardToSyslog=no
EOF
systemctl restart systemd-journald || true

if [[ -f /etc/postfix/main.cf ]]; then
  if grep -q '^inet_interfaces' /etc/postfix/main.cf; then
    sed -i 's/^inet_interfaces.*/inet_interfaces = loopback-only/' /etc/postfix/main.cf
  else
    echo 'inet_interfaces = loopback-only' >> /etc/postfix/main.cf
  fi
  systemctl restart postfix || true
fi

cat >/etc/nftables.conf <<'EOF'
#!/usr/sbin/nft -f
flush ruleset
table inet filter {
  chain input {
    type filter hook input priority 0;
    policy drop;
    iif "lo" accept
    ct state established,related accept
    tcp dport 22 accept
  }
  chain forward {
    type filter hook forward priority 0;
    policy drop;
  }
  chain output {
    type filter hook output priority 0;
    policy accept;
  }
}
EOF
chmod 644 /etc/nftables.conf
systemctl enable --now nftables || true
nft -f /etc/nftables.conf || true

chown root:shadow /etc/shadow /etc/gshadow 2>/dev/null || true
chown root:shadow /etc/shadow- /etc/gshadow- 2>/dev/null || true
chmod 640 /etc/shadow /etc/gshadow 2>/dev/null || true
chmod 640 /etc/shadow- /etc/gshadow- 2>/dev/null || true
echo 'root' >/etc/cron.allow
chown root:root /etc/cron.allow
chmod 640 /etc/cron.allow
find /var/log -type f -exec chmod g-wx,o-rwx {} + 2>/dev/null || true

for mod in cramfs freevxfs hfs hfsplus jffs2 udf usb-storage; do
  cat >/etc/modprobe.d/${mod}.conf <<EOF
install ${mod} /bin/true
blacklist ${mod}
EOF
done

if [[ -f /etc/default/grub ]]; then
  sed -i 's/\(GRUB_CMDLINE_LINUX\(_DEFAULT\)\?=\)"/\1"apparmor=1 security=apparmor audit=1 /' /etc/default/grub || true
  update-grub || true
fi
