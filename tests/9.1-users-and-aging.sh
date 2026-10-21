#!/usr/bin/env bash
# Verifies every command shown in 9.1 Users and Password Aging.
# Runs in a throwaway AlmaLinux 10 container as a wheel user with sudo,
# the way a student works on the exam; exits non-zero on the first failure.
# Accounts live in /etc/passwd, /etc/shadow, and /etc/group, so they persist
# across a reboot without any extra step; no reboot is needed here.
# Needs: docker
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
source "$HERE/lib/container.sh"
WORK=$(mktemp -d)
NAME=rh92-91
trap 'ct_down "$NAME"; rm -rf "$WORK"' EXIT

say() { printf '\n== %s\n' "$*"; }
# Run as the student user (wheel, passwordless sudo), like the exam.
show() {
  printf '$ %s\n' "$*"
  ct_as student "umask 022; $*" 2>&1 | tee "$WORK/out" || true
}
has() { grep -qF -- "$1" "$WORK/out" || { echo "MISSING: $1" >&2; exit 1; }; }
hasx() { grep -qxF -- "$1" "$WORK/out" || { echo "MISSING LINE: $1" >&2; exit 1; }; }

ct_up "$NAME" sudo util-linux
ct 'useradd -G wheel student
    echo "student ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/student
    chmod 440 /etc/sudoers.d/student'

say "defaults for new accounts"
show 'sudo useradd -D'
hasx 'HOME=/home'
hasx 'SHELL=/bin/bash'
hasx 'SKEL=/etc/skel'
show 'grep -E "^(UID_MIN|PASS_MAX_DAYS|HOME_MODE|UMASK)" /etc/login.defs'
has 'PASS_MAX_DAYS	99999'
has 'HOME_MODE	0700'

say "useradd with options"
show 'sudo useradd -u 2001 -c "Alice Admin" alice'
show 'id alice; grep alice /etc/passwd'
hasx 'uid=2001(alice) gid=2001(alice) groups=2001(alice)'
hasx 'alice:x:2001:2001:Alice Admin:/home/alice:/bin/bash'
show 'ls -ld /home/alice'
has 'drwx------ 2 alice alice'
show 'sudo useradd -r -s /sbin/nologin -M webapp'
show 'id webapp'
uid=$(sed -n 's/^uid=\([0-9]*\)(webapp).*/\1/p' "$WORK/out")
[ "$uid" -lt 1000 ]

say "passwords"
show 'rpm -qf /usr/bin/passwd; rpm -q passwd'
has 'shadow-utils-'
has 'package passwd is not installed'
show 'echo "Rh10-exam!" | sudo passwd --stdin alice'
[ ! -s "$WORK/out" ]   # shadow-utils passwd on RHEL 10 prints nothing here
show 'sudo grep alice /etc/shadow | cut -c1-30'
has 'alice:$y$'
show 'sudo passwd -S alice'
has 'alice P '
# A regular user can change only their own password, and must know the old one.
show 'passwd alice'
has 'passwd: You may not view or modify password information for alice.'

say "shadow fields: all nine"
show 'sudo grep alice /etc/shadow | cut -d: -f1,3-'
fields=$(awk -F: '{print NF}' "$WORK/out")
[ "$fields" = "8" ]   # name plus fields 3 to 9

say "password aging with chage"
show 'sudo chage -M 90 -m 7 -W 14 alice'
show 'sudo chage -E 2026-12-31 alice'
show 'sudo chage -l alice'
has 'Minimum number of days between password change		: 7'
has 'Maximum number of days between password change		: 90'
has 'Number of days of warning before password expires	: 14'
has 'Account expires						: Dec 31, 2026'
show 'sudo getent shadow alice | cut -d: -f3-'
has ':7:90:14::20818:'
show 'sudo chage -d 0 alice'
show 'sudo getent shadow alice | cut -d: -f3-'
hasx '0:7:90:14::20818:'
show 'sudo chage -l alice | head -2'
hasx 'Last password change					: password must be changed'
hasx 'Password expires					: password must be changed'
show 'sudo chage -d 20747 alice; sudo passwd -e alice; sudo chage -l alice | head -1'
hasx 'Last password change					: password must be changed'
show 'sudo chage -E -1 alice; sudo chage -l alice | grep "Account expires"'
has 'Account expires						: never'

say "login.defs only affects accounts created after the change"
show "sudo sed -i 's/^PASS_MAX_DAYS.*/PASS_MAX_DAYS\t90/' /etc/login.defs"
show 'grep ^PASS_MAX_DAYS /etc/login.defs'
hasx 'PASS_MAX_DAYS	90'
show 'sudo useradd bob'
show 'sudo chage -l bob | grep Maximum'
hasx 'Maximum number of days between password change		: 90'
show 'sudo chage -l student | grep Maximum'
hasx 'Maximum number of days between password change		: 99999'
show 'sudo passwd -S bob; sudo passwd -S student'
grep -Eq '^bob L [0-9-]+ 0 90 7 -1$' "$WORK/out"
grep -Eq '^student L [0-9-]+ 0 99999 7 -1$' "$WORK/out"

say "usermod"
show 'sudo usermod -c "Bob Builder" -s /bin/sh bob'
show 'sudo usermod -l robert -d /home/robert -m bob'
show 'grep ^robert: /etc/passwd'
hasx 'robert:x:2002:2002:Bob Builder:/home/robert:/bin/sh'
show 'ls /home'
hasx 'robert'

say "locking accounts"
ct 'echo "Rh10-exam!" | passwd --stdin robert'
show 'sudo usermod -L robert; sudo passwd -S robert'
has 'robert L 2026-'
show 'sudo grep robert /etc/shadow | cut -c1-12'
has 'robert:!$y$'
show 'sudo usermod -U robert'
show 'sudo passwd -S robert'
has 'robert P '
show 'sudo usermod -e 1 robert; sudo chage -l robert | grep "Account expires"'
has 'Account expires						: Jan 02, 1970'
show 'sudo chage -E 0 robert; sudo chage -l robert | grep "Account expires"'
has 'Account expires						: Jan 01, 1970'
show 'sudo chage -E -1 robert'

say "nologin shell"
show 'sudo usermod -s /sbin/nologin alice'
show 'sudo su - alice'
hasx 'This account is currently not available.'
show 'sudo su -s /bin/bash -c whoami alice'
hasx 'alice'

say "userdel"
show 'sudo userdel robert; ls -ld /home/robert'
has 'drwx------ 2 2002 bob'
show 'sudo rm -rf /home/robert; sudo useradd carol; sudo userdel -r carol; ls /home'
if grep -q carol "$WORK/out"; then echo "userdel -r left the home"; exit 1; fi

echo; echo "ALL 9.1 USERS-AND-AGING CHECKS PASSED"
