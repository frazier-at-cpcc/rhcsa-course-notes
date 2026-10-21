#!/usr/bin/env bash
# Verifies every command shown in 10.2 Default and Special Permissions.
# Runs in a throwaway AlmaLinux 10 container; exits non-zero on the first
# failure. A fresh login is simulated with "su - user", which runs the same
# PAM session stack (pam_umask) and login scripts as an SSH or console login,
# so it proves what the next login after a reboot gets.
# Needs: docker
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
source "$HERE/lib/container.sh"
WORK=$(mktemp -d)
NAME=rh9-102
trap 'ct_down "$NAME"; rm -rf "$WORK"' EXIT

say() { printf '\n== %s\n' "$*"; }
# Commands typed by the student (wheel, sudo) in an ordinary login session
show() {
  printf '$ %s\n' "$*"
  ct "su - student -c $(printf '%q' "$*")" 2>&1 | tee "$WORK/out" || true
}
# Commands typed by another user right after a fresh login
login() {   # user command
  printf '[%s] $ %s\n' "$1" "$2"
  ct "su - $1 -c $(printf '%q' "$2")" 2>&1 | tee "$WORK/out" || true
}
has() { grep -qF -- "$1" "$WORK/out" || { echo "MISSING: $1" >&2; exit 1; }; }
hasx() { grep -qxF -- "$1" "$WORK/out" || { echo "MISSING LINE: $1" >&2; exit 1; }; }

ct_up "$NAME" sudo util-linux acl
ct 'useradd -G wheel student
    echo "student ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/student
    chmod 440 /etc/sudoers.d/student
    groupadd devops; useradd -G devops alice; useradd -G devops bob
    useradd carol'

say "RHEL 10 default umask comes from /etc/login.defs through pam_umask"
show 'grep ^UMASK /etc/login.defs; grep pam_umask /etc/pam.d/postlogin'
hasx 'UMASK		022'
has 'session     optional                   pam_umask.so silent'
show 'grep -n umask /etc/profile /etc/bashrc'
has '/etc/bashrc:70:    [ `umask` -eq 0 ] && umask 022'
login alice 'umask; umask -S'
hasx '0022'
hasx 'u=rwx,g=rx,o=rx'
login root 'umask'
hasx '0022'

say "umask math"
login alice 'touch f1; mkdir d1; ls -ld f1 d1'
has '-rw-r--r-- 1 alice alice'
has 'drwxr-xr-x 2 alice alice'
login alice 'umask 027; touch f2; mkdir d2; ls -ld f2 d2'
has '-rw-r----- 1 alice alice'
has 'drwxr-x--- 2 alice alice'
login alice 'umask 007; touch f3; mkdir d3; ls -ld f3 d3'
has '-rw-rw---- 1 alice alice'
has 'drwxrwx--- 2 alice alice'
login alice 'umask 077; touch f4; mkdir d4; ls -ld f4 d4'
has '-rw------- 1 alice alice'
has 'drwx------ 2 alice alice'
# Bits are switched off, not subtracted
login alice 'umask 033; touch f6; ls -l f6'
has '-rw-r--r-- 1 alice alice'
login alice 'umask 27; umask'
hasx '0027'
# A umask never adds execute to a new file
login alice 'umask 000; touch f5; ls -l f5'
has '-rw-rw-rw- 1 alice alice'
# The umask set in one shell is gone at the next login
login alice 'umask'
hasx '0022'

say "per user: ~/.bashrc"
login alice 'echo "umask 007" >> ~/.bashrc'
login alice 'umask'
hasx '0007'

say "system wide: UMASK in /etc/login.defs"
show "sudo sed -i 's/^UMASK.*/UMASK\t\t027/' /etc/login.defs"
show 'grep ^UMASK /etc/login.defs'
hasx 'UMASK		027'
login bob 'umask'
hasx '0027'
login root 'umask'
hasx '0027'
# The per-user setting runs later and wins
login alice 'umask'
hasx '0007'
show "sudo sed -i 's/^UMASK.*/UMASK\t\t022/' /etc/login.defs"

say "system wide alternative: /etc/profile.d"
show 'echo "umask 027" | sudo tee /etc/profile.d/umask.sh'
login bob 'umask'
hasx '0027'
ct 'su bob -c "bash -c umask"' | tee "$WORK/out"   # non-login shell skips profile.d
hasx '0022'
show 'sudo rm /etc/profile.d/umask.sh'

say "home directories ignore the umask"
show 'grep ^HOME_MODE /etc/login.defs; sudo useradd dave; sudo ls -ld /home/dave'
hasx 'HOME_MODE	0700'
has 'drwx------ 2 dave dave'

say "setuid and setgid programs"
show 'ls -l /usr/bin/passwd /usr/bin/write'
has '-rwsr-xr-x 1 root root'
has '-rwxr-sr-x 1 root tty'

say "sticky bit"
show 'ls -ld /tmp'
has 'drwxrwxrwt'
login alice 'echo hi > /tmp/alice.txt; chmod 666 /tmp/alice.txt'
login bob 'rm -f /tmp/alice.txt'
hasx "rm: cannot remove '/tmp/alice.txt': Operation not permitted"

say "shared group directory with setgid"
show 'sudo mkdir -p /srv/devops /srv/plain'
show 'sudo chgrp devops /srv/devops /srv/plain'
show 'sudo chmod 770 /srv/plain; sudo chmod 2770 /srv/devops'
show 'ls -ld /srv/plain /srv/devops'
has 'drwxrwx--- 2 root devops'
has 'drwxrws--- 2 root devops'
login bob 'touch /srv/plain/a.txt /srv/devops/b.txt; mkdir /srv/devops/sub'
show 'sudo ls -l /srv/plain /srv/devops'
has '-rw-r--r-- 1 bob bob 0'
has '-rw-r--r-- 1 bob devops    0'
has 'drwxr-sr-x 2 bob devops'

say "sticky on the shared directory"
show 'sudo chmod 3770 /srv/devops; ls -ld /srv/devops'
has 'drwxrws--T 3 root devops'
login alice 'rm -f /srv/devops/b.txt'
hasx "rm: cannot remove '/srv/devops/b.txt': Operation not permitted"
show 'sudo chmod g-s,o-t /srv/devops; ls -ld /srv/devops'
has 'drwxrwx--- 3 root devops'
show 'sudo chmod g+s /srv/devops; ls -ld /srv/devops'
has 'drwxrws--- 3 root devops'
show 'sudo stat -c "%a %A" /srv/devops'
hasx '2770 drwxrws---'

say "capital S and T mean the execute bit is missing"
show 'touch s.txt; chmod 4644 s.txt; ls -l s.txt'
has '-rwSr--r-- 1 student student'

say "default ACL: the group can edit, whatever the umask"
show 'sudo setfacl -m d:g::rwx,d:o::- /srv/devops'
login bob 'umask; touch /srv/devops/c.txt; ls -l /srv/devops/c.txt'
hasx '0022'
has '-rw-rw---- 1 bob devops 0'

say "a named-user ACL entry"
show 'sudo setfacl -m u:carol:rx /srv/devops'
show 'getfacl /srv/devops'
has '# flags: -s-'
hasx 'user:carol:r-x'
hasx 'mask::rwx'
hasx 'default:group::rwx'
hasx 'default:other::---'
show 'ls -ld /srv/devops'
has 'drwxrws---+ 3 root devops'
login carol 'ls /srv/devops'
hasx 'c.txt'
login carol 'touch /srv/devops/d.txt'
hasx "touch: cannot touch '/srv/devops/d.txt': Permission denied"
show 'sudo setfacl -x u:carol /srv/devops'
show 'sudo setfacl -k /srv/devops'
show 'getfacl -c /srv/devops'
if grep -q -e default -e carol "$WORK/out"; then echo "ACL left behind"; exit 1; fi
show 'sudo setfacl -m u:carol:rx /srv/devops; sudo setfacl -b /srv/devops; ls -ld /srv/devops'
has 'drwxrws--- 3 root devops'

echo; echo "ALL 10.2 UMASK-AND-SPECIAL CHECKS PASSED"
