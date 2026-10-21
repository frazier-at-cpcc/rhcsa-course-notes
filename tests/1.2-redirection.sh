#!/usr/bin/env bash
# Verifies every command shown in 1.2 Redirection and Pipes.
# Runs in a throwaway AlmaLinux 10 container. The terminal blocks are typed
# into an interactive bash (bash -i) as student, a user with sudo, so the
# shell's own error messages match a real terminal.
# Needs: docker
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/lib/container.sh"
NAME=rh1a2-12
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

ct_up "$NAME" sudo
ct 'useradd student
    echo "student ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/student
    chmod 440 /etc/sudoers.d/student'

say "stdout and stderr to separate files"
term student <<'EOF'
find /etc -name "*.conf" > ok.txt 2> err.txt
wc -l ok.txt err.txt
tail -1 err.txt
find /etc -name "*.conf" 2>/dev/null | wc -l
EOF
has '  39 ok.txt'
has '   3 err.txt'
has '  42 total'
has "find: ‘/etc/sudoers.d’: Permission denied"
has '39'

say "append, overwrite, noclobber"
term student <<'EOF'
echo "first run" > run.log
echo "second run" >> run.log; cat run.log
echo "third run" > run.log; cat run.log
set -o noclobber
echo "oops" > run.log
echo "forced" >| run.log; cat run.log
EOF
has 'first run'
has 'second run'
has 'third run'
has 'bash: run.log: cannot overwrite existing file'
has 'forced'
[ "$(ct_as student 'cat run.log')" = forced ]

say "both streams: &> and 2>&1, and why order matters"
term student <<'EOF'
ls /etc/hosts /nope > out.txt 2>&1
cat out.txt
ls /etc/hosts /nope 2>&1 > out.txt
cat out.txt
ls /etc/hosts /nope &> out.txt; wc -l < out.txt
EOF
# once inside out.txt, once on the terminal, once in out.txt again
[ "$(grep -c "ls: cannot access '/nope': No such file or directory" "$WORK/out")" = 2 ]
[ "$(grep -cx '/etc/hosts' "$WORK/out")" = 2 ]
has '2'

say "input: <, here document, here string"
term student <<'EOF'
wc -l /etc/passwd
wc -l < /etc/passwd
tr a-z A-Z <<< "servera ready"
cat > motd.txt <<EOT
Welcome to $(hostname -s)
Maintenance: Sunday 02:00
EOT
cat motd.txt
cat <<"EOT"
Home is $HOME
EOT
EOF
has '17 /etc/passwd'
has '17'
has 'SERVERA READY'
has '> Welcome to $(hostname -s)'
has 'Welcome to servera'
has 'Maintenance: Sunday 02:00'
has 'Home is $HOME'

say "pipes and tee"
term student <<'EOF'
cut -d: -f7 /etc/passwd | sort | uniq -c
grep -c bash /etc/passwd | tee bash-users.txt
cat bash-users.txt
ls /nope | wc -l
ls /nope |& wc -l
false | true; echo $?
set -o pipefail; false | true; echo $?
EOF
has '      2 /bin/bash'
has '     11 /usr/sbin/nologin'
[ "$(grep -cx 2 "$WORK/out")" = 2 ]     # tee printed it, and the file holds it
grep -A2 -xF '$ ls /nope | wc -l' "$WORK/out" | sed -n 3p | grep -qx 0
grep -A1 -xF '$ ls /nope |& wc -l' "$WORK/out" | sed -n 2p | grep -qx 1
grep -A1 -xF '$ false | true; echo $?' "$WORK/out" | sed -n 2p | grep -qx 0
grep -A1 -xF '$ set -o pipefail; false | true; echo $?' "$WORK/out" | sed -n 2p | grep -qx 1

say "root-owned files: sudo does not cover the redirect"
term student <<'EOF'
sudo echo "Lab use only" > /etc/motd
echo "Lab use only" | sudo tee /etc/motd
echo "10.0.0.5 nas" | sudo tee -a /etc/hosts
echo "10.0.0.6 nfs1" \
| sudo tee -a /etc/hosts > /dev/null
tail -2 /etc/hosts
EOF
has 'bash: /etc/motd: Permission denied'
has 'Lab use only'
[ "$(grep -cx '10.0.0.5 nas' "$WORK/out")" = 2 ]
has '  | sudo tee -a /etc/hosts > /dev/null'
[ "$(grep -cx '10.0.0.6 nfs1' "$WORK/out")" = 1 ]   # only tail printed it
[ "$(ct 'cat /etc/motd')" = "Lab use only" ]

say "the try-it task"
ct_as student 'find / -name "*.repo" > /home/student/repos.txt 2> /dev/null; echo "# checked" >> repos.txt'
out=$(ct_as student 'cat repos.txt')
echo "$out"
grep -q '^/etc/yum.repos.d/almalinux-baseos.repo$' <<<"$out"
[ "$(tail -1 <<<"$out")" = "# checked" ]
if grep -q 'Permission denied' <<<"$out"; then exit 1; fi

echo; echo "ALL 1.2 REDIRECTION CHECKS PASSED"
