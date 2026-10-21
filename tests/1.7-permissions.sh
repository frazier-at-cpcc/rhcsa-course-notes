#!/usr/bin/env bash
# Verifies every command shown in 1.7 Standard Permissions.
# Runs in a throwaway AlmaLinux 10 container; exits non-zero on the first
# failure.
# Needs: docker
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
source "$HERE/lib/container.sh"
WORK=$(mktemp -d)
NAME=rh1b-17
trap 'ct_down "$NAME"; rm -rf "$WORK"' EXIT

say() { printf '\n== %s\n' "$*"; }
# docker exec starts every shell with umask 0000; a RHEL 10 login gets 022.
run() { ct "umask 022; $*"; }
# show <user> <commands>: run as that user, print, keep a copy to assert on
show() { local u="$1"; shift; ct_as "$u" "umask 022; $*" 2>&1 | tee "$WORK/out" || true; }
has() { grep -qF -- "$1" "$WORK/out" || { echo "MISSING: $1" >&2; exit 1; }; }
hasnt() { ! grep -qF -- "$1" "$WORK/out" || { echo "UNEXPECTED: $1" >&2; exit 1; }; }

ct_up "$NAME" sudo

say "users: student (sudo), alice, bob; group devops = alice, bob"
run 'useradd -G wheel student
echo "student ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/student
useradd alice; useradd bob; groupadd devops
usermod -aG devops alice; usermod -aG devops bob
mkdir -p /srv/project && echo "Q4 plan" > /srv/project/plan.txt
mkdir -p /srv/site/css && touch /srv/site/index.html /srv/site/css/site.css'

say "reading ls -l"
show student 'ls -l /srv/project/plan.txt'
has "-rw-r--r-- 1 root root 8"

say "chown and chgrp"
show student 'cd /srv/project && sudo chown alice:devops plan.txt && ls -l plan.txt'
has "-rw-r--r-- 1 alice devops 8"
show student 'cd /srv/project && sudo chown bob plan.txt && sudo chgrp alice plan.txt && ls -l plan.txt'
has "-rw-r--r-- 1 bob alice 8"
show student 'cd /srv/project && sudo chown alice: plan.txt && ls -l plan.txt'
has "-rw-r--r-- 1 alice alice 8"
show student 'cd /srv/project && sudo chown :devops plan.txt && ls -l plan.txt'
has "-rw-r--r-- 1 alice devops 8"
show student 'sudo chown -R alice:devops /srv/project && ls -ld /srv/project'
has "drwxr-xr-x 2 alice devops"

say "regular users: give away no, chgrp to own group yes"
show alice 'touch notes.txt && chown bob notes.txt'
has "chown: changing ownership of 'notes.txt': Operation not permitted"
show alice 'chgrp devops notes.txt && ls -l notes.txt'
has "-rw-r--r-- 1 alice devops 0"
show alice 'chgrp bob notes.txt'
has "chgrp: changing group of 'notes.txt': Operation not permitted"

say "symbolic chmod"
show alice 'cd /srv/project && chmod g+w,o-r plan.txt && ls -l plan.txt'
has "-rw-rw---- 1 alice devops 8"
show alice 'cd /srv/project && chmod u=rwx,go= plan.txt && ls -l plan.txt'
has "-rwx------ 1 alice devops 8"
show alice 'cd /srv/project && chmod a+r plan.txt && ls -l plan.txt'
has "-rwxr--r-- 1 alice devops 8"

say "octal chmod and stat"
show alice 'cd /srv/project && chmod 640 plan.txt && stat -c "%a %A %U:%G %n" plan.txt'
has "640 -rw-r----- alice:devops plan.txt"
show alice 'cd /srv/project && chmod 750 . && stat -c "%a %A %n" .'
has "750 drwxr-x--- ."

say "capital X: execute on directories only"
show student 'sudo chmod -R u=rwX,g=rX,o= /srv/site && sudo ls -lR /srv/site'
has "drwxr-x--- 2 root root"
has "-rw-r----- 1 root root 0"
hasnt "-rwx"
# X keeps execute on a file that already had it
run 'touch /srv/site/deploy.sh && chmod 744 /srv/site/deploy.sh && chmod -R u=rwX,g=rX,o= /srv/site'
[ "$(run 'stat -c %a /srv/site/deploy.sh /srv/site/index.html' | tr '\n' ' ')" = "750 640 " ]

say "first match wins: owner bits are used even when group has more"
run 'cd /srv/project && chmod 070 plan.txt'
show alice 'ls -l /srv/project/plan.txt; cat /srv/project/plan.txt'
has "----rwx--- 1 alice devops 8"
has "cat: /srv/project/plan.txt: Permission denied"
show bob 'cat /srv/project/plan.txt'
has "Q4 plan"
run 'chmod 640 /srv/project/plan.txt'

say "directory r without x"
run 'mkdir /srv/drop && echo "draft" > /srv/drop/report.txt && chmod 704 /srv/drop'
show bob 'ls -ld /srv/drop; ls -l /srv/drop; cd /srv/drop; cat /srv/drop/report.txt'
has "drwx---r-- 2 root root"
has "-????????? ? ? ? ?            ? report.txt"
has "ls: cannot access '/srv/drop/report.txt': Permission denied"
has "cd: /srv/drop: Permission denied"
has "cat: /srv/drop/report.txt: Permission denied"

say "directory x without r"
run 'chmod 701 /srv/drop'
show bob 'ls /srv/drop; cat /srv/drop/report.txt'
has "ls: cannot open directory '/srv/drop': Permission denied"
has "draft"

say "directory w+x lets you delete files you do not own"
run 'chmod 703 /srv/drop; ls -l /srv/drop/report.txt'
show bob 'rm -f /srv/drop/report.txt && echo removed'
has "removed"
run '[ ! -e /srv/drop/report.txt ]'

say "w on the file alone does not allow delete"
run 'echo "draft" > /srv/drop/report.txt && chmod 666 /srv/drop/report.txt && chmod 705 /srv/drop'
show bob 'echo "edit" >> /srv/drop/report.txt && rm -f /srv/drop/report.txt'
has "rm: cannot remove '/srv/drop/report.txt': Permission denied"

say "root ignores rwx, except it needs one x bit to execute"
run 'printf "#!/bin/sh\necho ran\n" > /srv/s.sh; chmod 000 /srv/s.sh; cat /srv/s.sh >/dev/null'
run '/srv/s.sh' 2>&1 | tee "$WORK/out" || true
has "Permission denied"
run 'chmod 001 /srv/s.sh'
run '/srv/s.sh' 2>&1 | tee "$WORK/out" || true
has "ran"

echo
echo "ALL 1.7 PERMISSIONS CHECKS PASSED"
