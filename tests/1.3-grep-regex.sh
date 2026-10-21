#!/usr/bin/env bash
# Verifies every container command shown in 1.3 grep and Regular
# Expressions. Runs in a throwaway AlmaLinux 10 container; the terminal
# blocks are typed into an interactive bash as student, a user with sudo.
# Not run here: the journal and /var/log/secure block, which comes from the
# lab capture lab/results/4.3-logs-and-journal.md (a container has no
# journald or rsyslog).
# Needs: docker
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/lib/container.sh"
NAME=rh1a2-13
WORK=$(mktemp -d)
trap 'ct_down "$NAME"; rm -rf "$WORK"' EXIT

say() { printf '\n== %s\n' "$*"; }
# term <user>: type stdin into an interactive bash; print a clean
# transcript ("$ " prompt, "  " for a continued line), keep it for has()
term() {
  { ct_as "$1" 'bash -i 2>&1' || true; } | sed -e '/cannot set terminal process group/d' \
    -e '/no job control in this shell/d' -e 's/^\[[^]]*\][$#] /$ /' \
    -e '/^\$ exit$/d' \
  | awk '{ if (prev ~ /\\$/ && $0 ~ /^> /) $0 = "  " substr($0, 3); print; prev = $0 }' \
  | tee "$WORK/out"
}
has() { grep -qxF -- "$1" "$WORK/out" || { echo "MISSING: $1" >&2; [ -n "${SOFT:-}" ] || exit 1; }; }
# after <command line> <n> <text>: line n after the command is exactly text
after() { local got; got=$(grep -A"$2" -xF -- "\$ $1" "$WORK/out" | sed -n "$(( $2 + 1 ))p"); [ "$got" = "$3" ] || { echo "AFTER '$1' +$2: got '$got', want '$3'" >&2; [ -n "${SOFT:-}" ] || exit 1; }; }

ct_up "$NAME" sudo openssh-server
ct 'useradd student; useradd alice; useradd -s /usr/sbin/nologin svcbackup
    echo "student ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/student
    chmod 440 /etc/sudoers.d/student'

say "basic searches in /etc/passwd"
term student <<'EOF'
grep alice /etc/passwd
grep -n '^root' /etc/passwd
grep -c nologin /etc/passwd
grep -vc nologin /etc/passwd
grep -i 'super user' /etc/passwd
grep -q bob /etc/passwd; echo $?
EOF
has 'alice:x:1001:1001::/home/alice:/bin/bash'
has '1:root:x:0:0:Super User:/root:/bin/bash'
after "grep -c nologin /etc/passwd" 1 14
after "grep -vc nologin /etc/passwd" 1 6
[ "$(ct 'wc -l < /etc/passwd')" = 20 ]
after "grep -i 'super user' /etc/passwd" 1 'root:x:0:0:Super User:/root:/bin/bash'
after 'grep -q bob /etc/passwd; echo $?' 1 1

say "-w, -o, -r, -l"
term student <<'EOF'
grep -c ftp /etc/services
grep -cw ftp /etc/services
grep -o '^[^:]*' /etc/passwd | head -3
sudo grep -l alice /etc/{passwd,shadow,hosts}
grep -r '^Include' /etc/ssh
cd /etc/ssh; sudo grep -rl '^Include' .
EOF
after 'grep -c ftp /etc/services' 1 55
after 'grep -cw ftp /etc/services' 1 17
[ "$(grep -A3 -xF "\$ grep -o '^[^:]*' /etc/passwd | head -3" "$WORK/out" | tail -3 | tr '\n' ' ')" = "root bin daemon " ]
after "sudo grep -l alice /etc/{passwd,shadow,hosts}" 1 /etc/passwd
after "sudo grep -l alice /etc/{passwd,shadow,hosts}" 2 /etc/shadow
after "sudo grep -l alice /etc/{passwd,shadow,hosts}" 3 "\$ grep -r '^Include' /etc/ssh"   # not hosts
has './sshd_config'
has './sshd_config.d/40-redhat-crypto-policies.conf'
has "grep: /etc/ssh/sshd_config: Permission denied"

say "BRE versus ERE"
term student <<'EOF'
grep '^\(alice\|student\):' /etc/passwd
grep -Ec '^(alice|student):' /etc/passwd
grep 'x:[0-9]{4}:' /etc/passwd | wc -l
grep -E 'x:[0-9]{4}:' /etc/passwd | cut -d: -f1
grep 'a|b' /etc/passwd | wc -l
EOF
after "grep '^\(alice\|student\):' /etc/passwd" 1 'student:x:1000:1000::/home/student:/bin/bash'
after "grep '^\(alice\|student\):' /etc/passwd" 2 'alice:x:1001:1001::/home/alice:/bin/bash'
after "grep -Ec '^(alice|student):' /etc/passwd" 1 2
after "grep 'x:[0-9]{4}:' /etc/passwd | wc -l" 1 0
[ "$(grep -A3 -xF "\$ grep -E 'x:[0-9]{4}:' /etc/passwd | cut -d: -f1" "$WORK/out" | tail -3 | tr '\n' ' ')" = "student alice svcbackup " ]
after "grep 'a|b' /etc/passwd | wc -l" 1 0

say "anchors and -v: login shells, active config lines"
term student <<'EOF'
grep 'bash$' /etc/passwd | cut -d: -f1
ls -l /etc/ssh/sshd_config
sudo grep -c '' /etc/ssh/sshd_config
sudo grep -Ev '^(#|$)' /etc/ssh/sshd_config
EOF
[ "$(grep -A3 -xF "\$ grep 'bash\$' /etc/passwd | cut -d: -f1" "$WORK/out" | tail -3 | tr '\n' ' ')" = "root student alice " ]
grep -q '^-rw-------\. 1 root root .* /etc/ssh/sshd_config$' "$WORK/out" \
  || grep -q '^-rw------- 1 root root .* /etc/ssh/sshd_config$' "$WORK/out"
after "sudo grep -c '' /etc/ssh/sshd_config" 1 130
has 'Include /etc/ssh/sshd_config.d/*.conf'
has 'AuthorizedKeysFile	.ssh/authorized_keys'
has 'Subsystem	sftp	/usr/libexec/openssh/sftp-server'
[ "$(grep -A4 -xF "\$ sudo grep -Ev '^(#|\$)' /etc/ssh/sshd_config" "$WORK/out" | sed 1d | grep -vc '^\$ ')" = 3 ]

say "matching lines into a file, original order"
term student <<'EOF'
grep -w ftp /etc/services > ftp-lines.txt
wc -l < ftp-lines.txt; head -2 ftp-lines.txt
grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}' \
/etc/hosts | head -1
EOF
after 'wc -l < ftp-lines.txt; head -2 ftp-lines.txt' 1 17
grep -A3 -xF '$ wc -l < ftp-lines.txt; head -2 ftp-lines.txt' "$WORK/out" | sed -n 3p | grep -qE '^ftp-data +20/tcp$'
grep -A3 -xF '$ wc -l < ftp-lines.txt; head -2 ftp-lines.txt' "$WORK/out" | sed -n 4p | grep -qE '^ftp-data +20/udp$'
has '  /etc/hosts | head -1'
grep -A1 -xF '  /etc/hosts | head -1' "$WORK/out" | sed -n 2p | grep -qx '127.0.0.1'

say "the try-it task"
ct "grep -E ':(/usr)?/sbin/nologin\$' /etc/passwd > /root/nologin-users.txt"
[ "$(ct 'wc -l < /root/nologin-users.txt')" = 14 ]
[ "$(ct 'grep nologin /etc/passwd')" = "$(ct 'cat /root/nologin-users.txt')" ]
[ "$(ct "grep -E '^[^:]+:x:[0-9]{4}:' /etc/passwd | cut -d: -f1 | tr '\n' ' '")" = "student alice svcbackup " ]

echo; echo "ALL 1.3 GREP-REGEX CHECKS PASSED"
