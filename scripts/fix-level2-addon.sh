#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

# Additional script-only controls beyond the Level 1 baseline.
# This script assumes fix-level1-base.sh and the general harden.sh already ran.

if [[ "$(id -u)" -ne 0 ]]; then
  echo "ERROR: fix-level2-addon.sh must run as root" >&2
  exit 1
fi

echo "=== Level 2 add-on remediation ==="

cat >/usr/share/pam-configs/faillock <<'EOF'
Name: Enable pam_faillock
Default: yes
Priority: 0
Auth-Type: Primary
Auth-Initial:
	required pam_faillock.so preauth silent audit deny=5 unlock_time=900 even_deny_root root_unlock_time=900
Auth:
	[default=die] pam_faillock.so authfail audit deny=5 unlock_time=900 even_deny_root root_unlock_time=900
Account-Type: Additional
Account:
	required pam_faillock.so
EOF
DEBIAN_FRONTEND=noninteractive pam-auth-update --enable faillock --force || true

cat >/etc/ssh/sshd_config.d/99-cis-level2.conf <<'EOF'
AllowTcpForwarding no
GSSAPIAuthentication no
EOF
chmod 600 /etc/ssh/sshd_config.d/99-cis-level2.conf
chown root:root /etc/ssh/sshd_config.d/99-cis-level2.conf
systemctl restart ssh || true

for mod in dccp rds sctp tipc squashfs; do
  cat >/etc/modprobe.d/${mod}.conf <<EOF
install ${mod} /bin/true
blacklist ${mod}
EOF
done

if [[ -f /etc/default/grub ]]; then
  sed -i 's/\(GRUB_CMDLINE_LINUX\(_DEFAULT\)\?=\)"/\1"audit_backlog_limit=8192 /' /etc/default/grub || true
  update-grub || true
fi

mkdir -p /etc/audit/rules.d
chmod 640 /etc/audit/rules.d/*.rules 2>/dev/null || true
chown root:root /etc/audit/rules.d/*.rules 2>/dev/null || true

cat >/etc/audit/rules.d/99-level2-addon.rules <<'EOF'
-a always,exit -F arch=b64 -S setxattr -S lsetxattr -S fsetxattr -S removexattr -S lremovexattr -S fremovexattr -k perm_mod
-a always,exit -F arch=b32 -S setxattr -S lsetxattr -S fsetxattr -S removexattr -S lremovexattr -S fremovexattr -k perm_mod
-a always,exit -F arch=b64 -S init_module -S finit_module -S delete_module -k modules
-a always,exit -F arch=b32 -S init_module -S finit_module -S delete_module -k modules
-w /etc/apparmor/ -p wa -k MAC-policy
-w /etc/apparmor.d/ -p wa -k MAC-policy
-w /etc/pam.conf -p wa -k identity
-w /etc/pam.d/ -p wa -k identity
-w /etc/nsswitch.conf -p wa -k identity
-w /etc/hosts -p wa -k system-locale
-w /etc/hostname -p wa -k system-locale
-w /etc/issue -p wa -k system-locale
-w /etc/issue.net -p wa -k system-locale
-w /etc/network/ -p wa -k system-locale
-w /usr/bin/chacl -p x -k perm_chng
-w /usr/bin/chcon -p x -k perm_chng
-w /usr/bin/setfacl -p x -k perm_chng
-w /usr/sbin/usermod -p x -k usermod
-w /usr/bin/kmod -p x -k modules
-w /var/log/faillog -p wa -k logins
-w /var/run/faillock/ -p wa -k logins
EOF

if [[ -f /etc/audit/auditd.conf ]]; then
  sed -i 's/^max_log_file_action.*/max_log_file_action = keep_logs/' /etc/audit/auditd.conf || true
  sed -i 's/^space_left_action.*/space_left_action = email/' /etc/audit/auditd.conf || true
  sed -i 's/^action_mail_acct.*/action_mail_acct = root/' /etc/audit/auditd.conf || true
fi

if command -v augenrules >/dev/null 2>&1; then
  augenrules --load || true
fi
systemctl restart auditd || true
