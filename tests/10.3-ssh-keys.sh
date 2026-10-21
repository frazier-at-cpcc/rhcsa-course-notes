#!/usr/bin/env bash
# Verifies every command shown in 10.3 SSH Key-Based Authentication.
# Two throwaway AlmaLinux 10 containers: servera (client) and serverb (sshd).
# Prompts (passphrases, passwords) are answered through a pseudo-terminal
# with `script`, so the output is what a student sees at a real terminal.
# Exits non-zero on the first failure.
#
# Container differences from a real RHEL 10 host, handled in setup only:
# - No systemd in a container, so sshd runs as a plain process and
#   "systemctl restart sshd" is replaced by stopping and starting it. The
#   notes give the systemctl commands as a list, not as console output.
# - pam_loginuid cannot write the audit login ID inside a container, so it
#   is made optional for sshd on serverb.
# - The container image ships /etc/ssh/sshd_config.d/25-permitrootlogin.conf
#   from its kickstart; a stock RHEL 10 install has no such file (the
#   installer writes 01-permitrootlogin.conf only when root password SSH
#   login is ticked), so it is removed to match a stock system.
# Needs: docker
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
source "$HERE/lib/container.sh"
WORK=$(mktemp -d)
A=rh9-103a; B=rh9-103b
trap 'ct_down "$A"; ct_down "$B"; rm -rf "$WORK"' EXIT

say() { printf '\n== %s\n' "$*"; }
on() { local c="$1"; shift; CT_NAME="$c" ct "$@"; }
show() {   # container user command
  printf '[%s %s] $ %s\n' "$1" "$2" "$3"
  CT_NAME="$1" ct_as "$2" "$3" 2>&1 | tr -d '\r' | tee "$WORK/out" || true
}
# Run a command on a pseudo-terminal, typing each answer after a pause
tty() {   # container user command answers...
  local c="$1" u="$2" cmd="$3"; shift 3
  printf '[%s %s] $ %s\n' "$c" "$u" "$cmd"
  { for a in "$@"; do sleep 3; printf '%s\n' "$a"; done; sleep 6; } \
    | docker exec -i -u "$u" -w "$(CT_NAME="$c" ct "getent passwd $u | cut -d: -f6")" "$c" \
        script -qec "bash -lc $(printf '%q' "$cmd")" /dev/null 2>&1 \
    | tr -d '\r' | tee "$WORK/out" || true
}
has() { grep -qF -- "$1" "$WORK/out" || { echo "MISSING: $1" >&2; exit 1; }; }
hasx() { grep -qxF -- "$1" "$WORK/out" || { echo "MISSING LINE: $1" >&2; exit 1; }; }
hasnt() { if grep -qF -- "$1" "$WORK/out"; then echo "UNEXPECTED: $1" >&2; exit 1; fi; }
sshd_restart() {   # stands in for: sudo systemctl restart sshd
  on "$B" 'kill $(cat /run/sshd.pid) 2>/dev/null; sleep 1; /usr/sbin/sshd -E /var/log/sshd.log'
  sleep 1
}

ct_up "$B" openssh-server openssh-clients sudo util-linux procps-ng
ct_up "$A" openssh-clients sudo util-linux procps-ng
BIP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$B")
for c in "$A" "$B"; do
  on "$c" 'useradd -G wheel student
    echo "student ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/student
    chmod 440 /etc/sudoers.d/student
    useradd -u 2001 alice; useradd -u 2002 bob
    echo "Rh10-exam!" | passwd --stdin alice
    echo "Rh10-exam!" | passwd --stdin bob
    echo "Rh10-root!" | passwd --stdin root 2>/dev/null'
done
on "$A" "echo '$BIP serverb.lab.example.com serverb' >> /etc/hosts"
on "$B" 'sed -i "s/^session\s*required\s*pam_loginuid.so/session optional pam_loginuid.so/" /etc/pam.d/sshd
    rm -f /etc/ssh/sshd_config.d/25-permitrootlogin.conf
    ssh-keygen -A >/dev/null; /usr/sbin/sshd -E /var/log/sshd.log'
# Trust serverb's host key up front (first-contact prompts are covered in 1.4)
for u in alice bob root; do
  on "$A" "h=\$(getent passwd $u | cut -d: -f6); mkdir -p -m 700 \$h/.ssh
    ssh-keyscan -t ed25519 serverb 2>/dev/null > \$h/.ssh/known_hosts
    chmod 644 \$h/.ssh/known_hosts; chown -R $u: \$h/.ssh"
done

say "stock sshd settings"
show "$B" student 'sudo grep -E "^(Include|AuthorizedKeysFile)" /etc/ssh/sshd_config'
hasx 'Include /etc/ssh/sshd_config.d/*.conf'
hasx 'AuthorizedKeysFile	.ssh/authorized_keys'
show "$B" student 'ls -l /etc/ssh/sshd_config'
has '-rw------- 1 root root'
show "$B" student 'sudo ls /etc/ssh/sshd_config.d/'
hasx '40-redhat-crypto-policies.conf'
hasx '50-redhat.conf'
show "$B" student "sudo sshd -T | grep -E '^(permitrootlogin|passwordauth|pubkeyauth)'"
hasx 'permitrootlogin without-password'
hasx 'pubkeyauthentication yes'
hasx 'passwordauthentication yes'

say "ssh-keygen with a passphrase"
tty "$A" alice 'ssh-keygen -t ed25519' '' 'Secret-pass1' 'Secret-pass1'
has 'Generating public/private ed25519 key pair.'
has 'Enter file in which to save the key (/home/alice/.ssh/id_ed25519):'
has 'Your identification has been saved in /home/alice/.ssh/id_ed25519'
has 'Your public key has been saved in /home/alice/.ssh/id_ed25519.pub'
has 'alice@servera.lab.example.com'
show "$A" alice 'ls -l ~/.ssh'
has '-rw------- 1 alice alice'
has '-rw-r--r-- 1 alice alice'
has 'id_ed25519.pub'

say "ssh-copy-id"
tty "$A" alice 'ssh-copy-id alice@serverb' 'Rh10-exam!'
has "alice@serverb's password:"
hasnt 'Permission denied'
has 'Number of key(s) added: 1'
show "$B" alice 'ls -ld ~/.ssh; ls -l ~/.ssh/authorized_keys'
has 'drwx------ 2 alice alice'
has '-rw------- 1 alice alice'
show "$B" alice 'cut -c1-40 ~/.ssh/authorized_keys'
has 'ssh-ed25519 AAAA'

say "the passphrase is asked on every use"
tty "$A" alice 'ssh alice@serverb whoami' 'Secret-pass1'
has "Enter passphrase for key '/home/alice/.ssh/id_ed25519':"
hasx 'alice'

say "ssh-agent holds the unlocked key"
tty "$A" alice 'eval $(ssh-agent); ssh-add; ssh-add -l; ssh alice@serverb whoami' 'Secret-pass1'
has 'Agent pid'
has 'Enter passphrase for /home/alice/.ssh/id_ed25519:'
has 'Identity added: /home/alice/.ssh/id_ed25519 (alice@servera.lab.example.com)'
has '256 SHA256:'
has '(ED25519)'
hasx 'alice'
hasnt "Enter passphrase for key"

say "a locked password does not block key logins"
on "$B" 'usermod -L alice'
tty "$A" alice 'eval $(ssh-agent) >/dev/null; ssh-add 2>/dev/null; ssh alice@serverb whoami' 'Secret-pass1'
hasx 'alice'
on "$B" 'usermod -U alice'

say "bad permissions on authorized_keys"
show "$B" alice 'chmod 664 ~/.ssh/authorized_keys'
tty "$A" alice 'eval $(ssh-agent) >/dev/null; ssh-add 2>/dev/null; ssh alice@serverb whoami' 'Secret-pass1' 'Rh10-exam!'
has "alice@serverb's password:"
on "$B" 'grep -c "Authentication refused: bad ownership or modes for file /home/alice/.ssh/authorized_keys" /var/log/sshd.log'
show "$B" alice 'chmod 600 ~/.ssh/authorized_keys'

say "root keeps key access under the default"
on "$A" 'ssh-keygen -q -t ed25519 -N "" -f /root/.ssh/id_ed25519'
on "$B" "mkdir -p -m 700 /root/.ssh"
on "$A" 'cat /root/.ssh/id_ed25519.pub' | on "$B" 'cat > /root/.ssh/authorized_keys; chmod 600 /root/.ssh/authorized_keys'
on "$A" 'ssh -o BatchMode=yes root@serverb whoami' > "$WORK/out"
hasx 'root'

say "a drop-in that disables password and root login"
show "$B" student 'printf "PasswordAuthentication no\nPermitRootLogin no\n" | sudo tee /etc/ssh/sshd_config.d/10-hardening.conf'
show "$B" student 'sudo sshd -t; echo "exit $?"'
hasx 'exit 0'
show "$B" student "sudo sshd -T | grep -E '^(permitrootlogin|passwordauth)'"
hasx 'permitrootlogin no'
hasx 'passwordauthentication no'
sshd_restart

say "typo caught by sshd -t"
show "$B" student 'echo "PasswordAuthentcation no" | sudo tee /etc/ssh/sshd_config.d/20-typo.conf >/dev/null'
show "$B" student 'sudo sshd -t'
has '/etc/ssh/sshd_config.d/20-typo.conf: line 1: Bad configuration option: PasswordAuthentcation'
has 'terminating, 1 bad configuration options'
show "$B" student 'sudo rm /etc/ssh/sshd_config.d/20-typo.conf'

say "the first value wins"
show "$B" student 'echo "PasswordAuthentication yes" | sudo tee /etc/ssh/sshd_config.d/90-late.conf >/dev/null'
show "$B" student "sudo sshd -T | grep ^passwordauth"
hasx 'passwordauthentication no'
show "$B" student 'sudo rm /etc/ssh/sshd_config.d/90-late.conf'

say "results after the restart"
tty "$A" bob 'ssh bob@serverb'
hasx 'bob@serverb: Permission denied (publickey,gssapi-keyex,gssapi-with-mic).'
tty "$A" root 'ssh root@serverb'
hasx 'root@serverb: Permission denied (publickey,gssapi-keyex,gssapi-with-mic).'
tty "$A" alice 'eval $(ssh-agent) >/dev/null; ssh-add 2>/dev/null; ssh alice@serverb whoami' 'Secret-pass1'
hasx 'alice'

say "settings survive a restart of sshd (stand-in for a reboot)"
sshd_restart
on "$B" '/usr/sbin/sshd -T' > "$WORK/out"
hasx 'passwordauthentication no'
hasx 'permitrootlogin no'

echo; echo "ALL 10.3 SSH-KEYS CHECKS PASSED"
