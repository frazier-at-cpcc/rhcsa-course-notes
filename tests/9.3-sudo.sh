#!/usr/bin/env bash
# Verifies every command shown in 9.3 Privileged Access with sudo.
# Runs in a throwaway AlmaLinux 10 container as a wheel user with sudo;
# exits non-zero on the first failure. sudoers files are read on every sudo
# call, so a rule persists across a reboot as long as the file stays.
# Interactive steps (visudo's editor, typing a password at a prompt) are not
# scripted: the rule files are written with tee and checked with visudo -c.
# Needs: docker
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
source "$HERE/lib/container.sh"
WORK=$(mktemp -d)
NAME=rh92-93
trap 'ct_down "$NAME"; rm -rf "$WORK"' EXIT

say() { printf '\n== %s\n' "$*"; }
showas() {   # user command...
  local u="$1"; shift
  printf '$ %s\n' "$*"
  ct_as "$u" "umask 022; $*" 2>&1 | tee "$WORK/out" || true
}
show() { showas student "$@"; }
# A command typed at a real terminal, with the user's password at the prompt
showtty() {   # user command
  printf '$ %s\n' "$2"
  ct_as "$1" "sleep 1; printf 'Rh10-exam!\\n'" \
    | ct_as "$1" "script -qec '$2' /dev/null" 2>&1 | tr -d '\r' | tee "$WORK/out" || true
}
has() { grep -qF -- "$1" "$WORK/out" || { echo "MISSING: $1" >&2; exit 1; }; }
hasx() { grep -qxF -- "$1" "$WORK/out" || { echo "MISSING LINE: $1" >&2; exit 1; }; }
hasnt() { if grep -qF -- "$1" "$WORK/out"; then echo "UNEXPECTED: $1" >&2; exit 1; fi; }

ct_up "$NAME" sudo util-linux
ct 'useradd -G wheel student
    echo "student ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/student
    chmod 440 /etc/sudoers.d/student
    useradd alice; useradd bob; groupadd webops; usermod -aG webops bob
    echo "Rh10-exam!" | passwd --stdin alice
    echo "Rh10-exam!" | passwd --stdin bob'

say "the shipped sudoers file"
show "sudo grep -E '^[^#]*wheel|includedir' /etc/sudoers"
hasx '%wheel	ALL=(ALL)	ALL'
hasx '#includedir /etc/sudoers.d'
show 'ls -l /etc/sudoers; sudo ls -ld /etc/sudoers.d'
has '-r--r----- 1 root root'
has 'drwxr-x--- 2 root root'

say "wheel membership"
show 'sudo -l -U alice'
hasx 'User alice is not allowed to run sudo on servera.'
show 'sudo usermod -aG wheel alice'
show 'sudo -l -U alice | tail -2'
hasx 'User alice may run the following commands on servera:'
hasx '    (ALL) ALL'

say "a drop-in with a command restriction and NOPASSWD"
show 'sudo tee /etc/sudoers.d/webops >/dev/null <<"EOF"
# Web team: manage httpd only, no password
Cmnd_Alias WEB = /usr/bin/systemctl restart httpd, \
                 /usr/bin/systemctl reload httpd, \
                 /usr/bin/systemctl status httpd
%webops ALL=(root) NOPASSWD: WEB
EOF'
show 'sudo chmod 440 /etc/sudoers.d/webops'
show 'sudo visudo -c'
hasx '/etc/sudoers: parsed OK'
hasx '/etc/sudoers.d/webops: parsed OK'
show 'sudo -l -U bob | tail -4'
has '(root) NOPASSWD: /usr/bin/systemctl restart httpd,'
has '/usr/bin/systemctl status httpd'
# sudo -l with a command answers "would this be allowed?"
showas bob 'sudo -l systemctl restart httpd'
hasx '/bin/systemctl restart httpd'
showas bob 'sudo -l systemctl stop httpd; echo "exit $?"'
hasx 'exit 1'
showtty bob 'sudo dnf -y install nmap'
has 'Sorry, user bob is not allowed to execute'
has "'/bin/dnf -y install nmap' as root on servera.lab.example.com."

say "visudo catches a syntax error before it locks you out"
show 'echo "%webops ALL=(root) NOPASWD: ALL" | sudo tee /etc/sudoers.d/broken >/dev/null'
show 'sudo visudo -cf /etc/sudoers.d/broken'
has "/etc/sudoers.d/broken:1:32: syntax error"
# sudo still works from the other files, but complains on every call
show 'sudo rm /etc/sudoers.d/broken'
has "/etc/sudoers.d/broken:1:32: syntax error"
ct '[ ! -e /etc/sudoers.d/broken ]'

say "file names with a dot are ignored"
show 'sudo mv /etc/sudoers.d/webops /etc/sudoers.d/webops.conf; sudo -l -U bob | tail -1'
hasx 'User bob is not allowed to run sudo on servera.'
show 'sudo mv /etc/sudoers.d/webops.conf /etc/sudoers.d/webops'

say "group rules need the percent sign"
ct 'groupadd admins; useradd -G admins frank'
show 'echo "admins ALL=(ALL) ALL" | sudo tee /etc/sudoers.d/admins; sudo -l -U frank | tail -1'
hasx 'User frank is not allowed to run sudo on servera.'
show 'echo "%admins ALL=(ALL) ALL" | sudo tee /etc/sudoers.d/admins; sudo -l -U frank | tail -1'
hasx '    (ALL) ALL'

say "credential cache and editor defaults"
show 'sudo sudo -V | grep -E "timestamp timeout|editor"'
has 'Authentication timestamp timeout: 5.0 minutes'

say "run as another user, and root shells"
show 'sudo -u alice whoami; sudo whoami'
hasx 'alice'
hasx 'root'
show 'sudo -i pwd; sudo -s pwd'
hasx '/root'
hasx '/home/student'
show 'sudo -i bash -c "echo \$USER \$HOME"; sudo -s bash -c "echo \$USER \$HOME"'
hasx 'root /root'

say "su and the root account"
show 'sudo passwd -S root'
has 'root L '
# su - starts a login shell (root's PATH and home); su keeps the caller's
show 'sudo su - alice -c pwd; sudo su alice -c pwd'
hasx '/home/alice'
hasx '/home/student'
show 'grep -c alice /etc/group; sudo grep wheel /etc/group'
hasx 'wheel:x:10:student,alice'

echo; echo "ALL 9.3 SUDO CHECKS PASSED"
