#!/usr/bin/env bash
# Verifies the SSH and su commands shown in 1.4 SSH and Switching Users.
# Two AlmaLinux 10 containers on a private network: servera (the client,
# from tests/lib/container.sh) and serverb (sshd started by hand). The
# terminal blocks are typed into an interactive bash as student on servera.
# Password prompts are not shown in the notes; expect types the passwords
# here so the prompt texts listed in the notes are checked.
# From the lab capture instead (lab/results/1.4-logins-and-users.md):
# systemctl get-default, loginctl, and the sudo su / sudo -i lines, which
# need systemd and logind.
# Not executed: Ctrl+Alt+Fn at a physical console (table only).
# Needs: docker
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/lib/container.sh"
NAME=rh1a2-14a; SB=rh1a2-14b; NET=rh1a2-net
WORK=$(mktemp -d)
cleanup() {
  ct_down "$NAME"; docker rm -f "$SB" >/dev/null 2>&1 || true
  docker network rm "$NET" >/dev/null 2>&1 || true; rm -rf "$WORK"
}
trap cleanup EXIT

say() { printf '\n== %s\n' "$*"; }
# term <user>: type each command line from stdin into its own interactive
# bash on servera (ssh would otherwise read the lines that follow it); print
# a clean transcript ("$ " prompt, "  " for a continued line)
term() {
  local u="$1" cmd="" line
  : > "$WORK/out"
  while IFS= read -r line; do
    cmd+="$line"$'\n'
    [[ $line == *\\ ]] && continue
    printf '%s' "$cmd" | { ct_as "$u" 'bash -i 2>&1' || true; } \
    | sed -e '/cannot set terminal process group/d' \
      -e '/no job control in this shell/d' -e 's/^\[[^]]*\][$#] /$ /' \
      -e '/^\$ exit$/d' -e '/^\$ $/d' \
    | awk '{ if (prev ~ /\\$/ && $0 ~ /^> /) $0 = "  " substr($0, 3); print; prev = $0 }' \
    | tr -d '\r' >> "$WORK/out"
    cmd=""
  done
  cat "$WORK/out"
}
has() { grep -qxF -- "$1" "$WORK/out" || { echo "MISSING: $1" >&2; [ -n "${SOFT:-}" ] || exit 1; }; }
sb() { docker exec -i "$SB" bash -c "$*"; }
# sbl: a login shell on serverb, so LANG and the date format match a login
sbl() { docker exec -i "$SB" bash -lc "$*"; }

say "two hosts: servera (client) and serverb (sshd)"
docker rm -f "$SB" >/dev/null 2>&1 || true
docker network rm "$NET" >/dev/null 2>&1 || true
docker network create "$NET" >/dev/null
ca=(); [ -f /root/.ccr/ca-bundle.crt ] && ca=(-v /root/.ccr/ca-bundle.crt:/etc/pki/ca-trust/source/anchors/sandbox-proxy.crt:ro)
docker run -d --name "$SB" --hostname serverb.lab.example.com \
  --network "$NET" --network-alias serverb.lab.example.com --network-alias serverb \
  "${ca[@]}" "$CT_IMAGE" sleep infinity >/dev/null
sb 'update-ca-trust; dnf -y -q install openssh-server procps-ng >/dev/null
    ssh-keygen -A >/dev/null; useradd alice; useradd bob
    echo alice:redhat | chpasswd; echo bob:redhat | chpasswd
    touch /run/utmp; /usr/sbin/sshd'
ct_up "$NAME" openssh-clients sudo expect
docker network connect --alias servera.lab.example.com "$NET" "$NAME"
ct 'useradd student; useradd alice; echo alice:redhat | chpasswd
    echo root:redhat | chpasswd
    echo "student ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/student
    chmod 440 /etc/sudoers.d/student'

say "interactive first login: prompt texts (expect answers them)"
ct "cat > /tmp/first.exp; chmod 644 /tmp/first.exp" <<'EOF'
set timeout 30
spawn ssh alice@serverb.lab.example.com hostname
expect "(yes/no/\\\[fingerprint\\\])? " { send "yes\r" }
expect "password: " { send "redhat\r" }
expect eof
EOF
out=$(ct_as student 'expect /tmp/first.exp' | tr -d '\r')
echo "$out"
grep -qE "^The authenticity of host 'serverb.lab.example.com \([0-9.]+\)' can't be established.$" <<<"$out"
grep -qE '^ED25519 key fingerprint is SHA256:[A-Za-z0-9+/]{43}\.$' <<<"$out"
grep -qx 'This key is not known by any other names.' <<<"$out"
grep -qxF 'Are you sure you want to continue connecting (yes/no/[fingerprint])? yes' <<<"$out"
grep -qxF "Warning: Permanently added 'serverb.lab.example.com' (ED25519) to the list of known hosts." <<<"$out"
grep -qxF "alice@serverb.lab.example.com's password: " <<<"$out"
grep -qx 'serverb.lab.example.com' <<<"$out"
# The fingerprint the client showed is the server's real ED25519 key
fp=$(sb 'ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub' | awk '{print $2}')
grep -qF "ED25519 key fingerprint is $fp." <<<"$out"
# Start the notes' examples from an empty known_hosts
ct_as student 'rm -f ~/.ssh/known_hosts ~/.ssh/known_hosts.old'

say "a key for alice@serverb, as topic 10.3 sets up (not shown in 1.4)"
ct_as student 'ssh-keygen -q -t ed25519 -N "" -f ~/.ssh/id_ed25519'
sb 'install -d -o alice -g alice -m 700 /home/alice/.ssh'
ct_as student 'cat ~/.ssh/id_ed25519.pub' | sb 'cat > /home/alice/.ssh/authorized_keys
  chown alice: /home/alice/.ssh/authorized_keys; chmod 600 /home/alice/.ssh/authorized_keys'

say "first connection with accept-new, remote commands, known_hosts"
term student <<'EOF'
ssh -o StrictHostKeyChecking=accept-new \
alice@serverb.lab.example.com hostname
ssh alice@serverb.lab.example.com 'whoami; pwd'
cut -d' ' -f1,2 ~/.ssh/known_hosts
ssh-keygen -F serverb.lab.example.com | head -1
EOF
has "Warning: Permanently added 'serverb.lab.example.com' (ED25519) to the list of known hosts."
has 'serverb.lab.example.com'
has 'alice'
has '/home/alice'
has 'serverb.lab.example.com ssh-ed25519'
has '# Host serverb.lab.example.com found: line 1 '   # ssh-keygen ends it with a space

say "refused logins"
term student <<'EOF'
ssh -o BatchMode=yes alice@serverb hostname
ssh -o BatchMode=yes \
bob@serverb.lab.example.com true; echo $?
EOF
has 'Host key verification failed.'
has 'bob@serverb.lab.example.com: Permission denied (publickey,gssapi-keyex,gssapi-with-mic,password).'
has '255'

say "who and w on serverb while alice holds a terminal session"
# alice's login shell waits on a terminal for 40 seconds, like a person
ct_as student 'sleep 40 | ssh -tt alice@serverb.lab.example.com >/dev/null 2>&1 &'
sleep 5
sbl 'who; echo ---; w -s' | tee "$WORK/out"
grep -qE '^alice +pts/0 +[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9:]+ \([0-9.]+\)$' "$WORK/out"
grep -qE '^USER +TTY +IDLE +WHAT$' "$WORK/out"
grep -qE '^alice +pts/0 +[0-9.]+s +-bash$' "$WORK/out"

say "host key changed: serverb rebuilt"
sb 'rm -f /etc/ssh/ssh_host_*; ssh-keygen -A >/dev/null; pkill -x sshd; sleep 1; /usr/sbin/sshd'
term student <<'EOF'
ssh alice@serverb.lab.example.com hostname
ssh-keygen -R serverb.lab.example.com
ssh -o StrictHostKeyChecking=accept-new \
alice@serverb.lab.example.com hostname
EOF
has '@    WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!     @'
grep -qE '^Offending (ED25519|ECDSA|RSA) key in /home/student/.ssh/known_hosts:[0-9]+$' "$WORK/out"
has 'Host key verification failed.'
has '# Host serverb.lab.example.com found: line 1'
has '/home/student/.ssh/known_hosts updated.'
has 'Original contents retained as /home/student/.ssh/known_hosts.old'
[ "$(grep -cx 'serverb.lab.example.com' "$WORK/out")" = 1 ]

say "su and su - with passwords (prompt texts only)"
ct "cat > /tmp/su.exp; chmod 644 /tmp/su.exp" <<'EOF'
set timeout 20
spawn bash --norc
expect "$ " ; send "cd /tmp\r"
expect "$ " ; send "su alice -c pwd\r"
expect "Password: " { send "redhat\r" }
expect "$ " ; send "su - alice -c pwd\r"
expect "Password: " { send "redhat\r" }
expect "$ " ; send "su - -c whoami\r"
expect "Password: " { send "wrong\r" }
expect "$ " ; send "su - -c whoami\r"
expect "Password: " { send "redhat\r" }
expect "$ " ; send "exit\r"
expect eof
EOF
out=$(ct_as student 'expect /tmp/su.exp' | tr -d '\r')
echo "$out"
grep -qx 'Password: ' <<<"$out"
grep -qx '/tmp' <<<"$out"
grep -qx '/home/alice' <<<"$out"
grep -qx 'su: Authentication failure' <<<"$out"
grep -qx 'root' <<<"$out"

say "sudo -i and sudo su - (the capture shows the same on RHEL 10)"
term student <<'EOF'
cd /tmp; sudo -i pwd; sudo su - -c pwd; sudo su -c pwd
sudo -u alice -i pwd
EOF
[ "$(grep -A3 -xF '$ cd /tmp; sudo -i pwd; sudo su - -c pwd; sudo su -c pwd' "$WORK/out" | sed 1d | tr '\n' ' ')" = "/root /root /tmp " ]
has '/home/alice'

echo; echo "ALL 1.4 SSH-AND-SU CHECKS PASSED"
