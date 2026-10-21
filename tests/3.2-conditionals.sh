#!/usr/bin/env bash
# Verifies every command shown in 3.2 Conditionals and Tests.
# The scripts are pulled straight out of the notes' ```bash label="..." blocks,
# installed in an AlmaLinux 10 container, and run as the user student.
# Needs: docker, awk
set -euo pipefail
cd "$(dirname "$0")"
source lib/container.sh
NOTES=../content/domain-3/3.2-conditionals.md
CT=rh23-32
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
install_script() {
  local f=$1
  [ -n "$(block "$f")" ] || { echo "no block $f in notes" >&2; exit 1; }
  block "$f" | ct "cat > /home/student/$f && chmod 755 /home/student/$f && chown student: /home/student/$f"
  ct "bash -n /home/student/$f"
}

ct 'useradd student && echo "student ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/student
    chmod 440 /etc/sudoers.d/student'
for f in checkpath.sh q.sh distro.sh; do install_script "$f"; done

say "exit status is the condition"
run 'test -d /etc; echo $?'; hasx '0'
run '[ -d /etc/hostname ]; echo $?'; hasx '1'
run '[ "$(id -u)" -eq 0 ] || echo "not root"'; hasx 'not root'
run 'if grep -q student /etc/passwd; then echo yes; fi'; hasx 'yes'
run '[-d /etc] 2>&1; echo $?'; has 'command not found'; hasx '127'

say "operators from the table"
run '[ 10 -gt 9 ] && echo int-true; [ 10 \> 9 ] || echo text-false'
hasx 'int-true'; hasx 'text-false'
run 'c=00; [ "$c" = 0 ] || echo str-differs; [ "$c" -eq 0 ] && echo int-equal'
hasx 'str-differs'; hasx 'int-equal'
run '[ ! -e /etc/nologin ] && echo no-nologin'; hasx 'no-nologin'
run 's=""; [ -z "$s" ] && echo empty; s=x; [ -n "$s" ] && echo set'
hasx 'empty'; hasx 'set'
run 'touch old; sleep 1; touch new; [ new -nt old ] && echo newer'; hasx 'newer'
run '[ -r /etc/shadow ] || echo cannot-read; [ -x /usr/bin/ls ] && echo can-run'
hasx 'cannot-read'; hasx 'can-run'

say "if / elif / else"
run 'ln -s /var/www/html webroot'
run './checkpath.sh webroot'; hasx 'webroot: link to /var/www/html'
run './checkpath.sh /etc'; hasx '/etc: directory'
run './checkpath.sh /etc/hostname'
hasx "/etc/hostname: file, $(ct 'stat -c %s /etc/hostname') bytes"
hasx '/etc/hostname: file, 24 bytes'
run 'touch notes.txt; ./checkpath.sh notes.txt'; hasx 'notes.txt: empty file'
run './checkpath.sh /etc/nologin; echo $?'; hasx '/etc/nologin: not found'; hasx '1'
run './checkpath.sh; echo $?'; hasx 'Usage: ./checkpath.sh PATH'; hasx '2'

say "quoting and [[ ]]"
run './q.sh'
hasx './q.sh: line 4: [: =: unary operator expected'
hasx './q.sh: line 5: [: My: binary operator expected'
hasx '[[ ]] copes'; hasx 'web node 01'
run 'host=web01.lab.example.com; [[ $host == web* ]] && echo glob-match'
hasx 'glob-match'

say "&& and || chains"
run '[ -d /srv/backup ] || sudo mkdir /srv/backup'
run '[ -d /srv/backup ] && echo ready'; hasx 'ready'
run 'true && false || echo "C ran anyway"'; hasx 'C ran anyway'
run "grep -q '^student:' /etc/passwd && echo \"student exists\""; hasx 'student exists'

say "case"
run './distro.sh redhat'; hasx 'fedora'
run './distro.sh fedora'; hasx 'redhat'
run './distro.sh centos; echo $?'; hasx 'Usage: ./distro.sh redhat|fedora'; hasx '1'
run './distro.sh 2>/dev/null; echo $?'; hasx '1'
run './distro.sh --help; echo $?'; hasx 'Usage: ./distro.sh redhat|fedora'; hasx '0'

echo
echo "ALL 3.2 CONDITIONALS CHECKS PASSED"
