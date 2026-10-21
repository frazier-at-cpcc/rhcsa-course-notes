#!/usr/bin/env bash
# Verifies every command shown in 3.3 Loops.
# The scripts and the input file are pulled straight out of the notes'
# fenced blocks, installed in an AlmaLinux 10 container, and run as student.
# Needs: docker, awk
set -euo pipefail
cd "$(dirname "$0")"
source lib/container.sh
NOTES=../content/domain-3/3.3-loops.md
CT=rh232-33
trap 'ct_down $CT' EXIT
ct_up $CT sudo

say() { printf '\n== %s\n' "$*"; }
run() { printf '$ %s\n' "$1"; OUT=$(ct_as student "$1" 2>&1) || true; printf '%s\n' "$OUT"; }
has() { grep -qE -- "$1" <<<"$OUT" || { echo "MISSING: $1" >&2; exit 1; }; }
hasx() { grep -qxF -- "$1" <<<"$OUT" || { echo "MISSING LINE: $1" >&2; exit 1; }; }
block() {
  awk -v want="label=\"$1\"" '
    /^```/ && on { exit }
    on { print }
    /^```[a-z]+ / && index($0, want) { on = 1 }' "$NOTES"
}
install_file() {   # copy a labelled block from the notes into ~student
  local f=$1 mode=${2:-755}
  [ -n "$(block "$f")" ] || { echo "no block $f in notes" >&2; exit 1; }
  block "$f" | ct "cat > /home/student/$f && chmod $mode /home/student/$f && chown student: /home/student/$f"
}

ct 'useradd student && echo "student ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/student
    chmod 440 /etc/sudoers.d/student'
for f in filesizes.sh mkusers.sh humans.sh; do install_file "$f"; ct "bash -n /home/student/$f"; done
install_file newhires.txt 644

say "for over lists, ranges, seq, globs"
run 'for h in web db; do echo "check $h"; done'; hasx 'check web'; hasx 'check db'
run 'mkdir -p demo && cd demo && for i in {1..3}; do touch app$i.log; done; echo *.log'
hasx 'app1.log app2.log app3.log'
run 'for i in $(seq 1 2 7); do echo -n "$i "; done'; hasx '1 3 5 7 '
run 'cd demo && for f in *.log; do cp "$f" "$f.bak"; done; echo *.bak'
hasx 'app1.log.bak app2.log.bak app3.log.bak'
run 'cd demo && for f in *.log; do mv "$f" "${f%.log}.txt"; done; ls *.txt'
hasx 'app1.txt'
run 'for x in {a..c} {01..03}; do echo -n "$x "; done'; hasx 'a b c 01 02 03 '
run 'for ((i=1; i<=3; i++)); do echo -n "$i "; done'; hasx '1 2 3 '
run 'cd demo && for f in *.nomatch; do echo "got $f"; done'; hasx 'got *.nomatch'
run 'touch "my file.txt"; for f in $(ls my*); do echo "[$f]"; done'
hasx '[my]'; hasx '[file.txt]'
run 'for f in my*; do echo "[$f]"; done'; hasx '[my file.txt]'

say "loop over command line arguments"
run './filesizes.sh /etc/passwd /etc/group /etc'
hasx 'skip: /etc'
p=$(ct 'stat -c %s /etc/passwd'); g=$(ct 'stat -c %s /etc/group')
has "^ +$p  /etc/passwd$"; has "^ +$g  /etc/group$"; has "^ +$((p + g))  total$"
# docker exec splits stdout and stderr; merge them inside the shell to check
# the order a terminal shows: the skip line comes before the total
run './filesizes.sh /etc/passwd /etc/group /etc 2>&1 | tail -2'
[ "$(head -1 <<<"$OUT")" = "skip: /etc" ] || { echo "skip line out of order" >&2; exit 1; }
run 'set -- "a b" c; for f; do echo "[$f]"; done'; hasx '[a b]'; hasx '[c]'

say "while read over a file"
run 'cat newhires.txt'; hasx 'carol    web'
run 'sudo ./mkusers.sh newhires.txt'
hasx 'added alice to devops'; hasx 'added bob to devops'
hasx 'added carol to web'; hasx 'skip alice: exists'
run 'id -nG carol'; hasx 'carol web'
run 'sudo ./mkusers.sh newhires.txt'
[ "$(grep -c '^skip' <<<"$OUT")" = 4 ]
run './mkusers.sh nosuchfile; echo $?'; hasx 'Usage: ./mkusers.sh FILE'; hasx '2'
# a redirect on read (instead of done) rereads line one forever
run 'n=0; while read -r l < newhires.txt; do n=$((n+1)); [ $n -ge 5 ] && break; done; echo "$l"'
hasx '# user   group'
# a file without a final newline loses its last line to while read
run 'printf "one\ntwo" > nonl.txt; while read -r l; do echo "$l"; done < nonl.txt'
hasx 'one'; ! grep -qx two <<<"$OUT"
run 'n=0; until [ $n -ge 3 ]; do n=$((n+1)); done; echo $n'; hasx '3'

say "loop over command output"
run './humans.sh'
hasx 'student 1000 /home/student'; hasx 'alice 1001 /home/alice'
hasx 'bob 1002 /home/bob'; hasx 'carol 1003 /home/carol'
hasx '4 regular accounts'
! grep -q nobody <<<"$OUT"
run 'n=0; seq 3 | while read -r l; do n=$l; done; echo "n=$n"'; hasx 'n=0'
run 'n=0; while read l; do n=$l; done < <(seq 3); echo "n=$n"'; hasx 'n=3'

echo
echo "ALL 3.3 LOOPS CHECKS PASSED"
