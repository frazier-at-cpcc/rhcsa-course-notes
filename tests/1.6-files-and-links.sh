#!/usr/bin/env bash
# Verifies every command shown in 1.6 Files, Directories, and Links.
# Runs in a throwaway AlmaLinux 10 container; exits non-zero on the first
# failure.
# Needs: docker
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
source "$HERE/lib/container.sh"
WORK=$(mktemp -d)
NAME=rh1b-16
trap 'ct_down "$NAME"; rm -rf "$WORK"' EXIT

say() { printf '\n== %s\n' "$*"; }
# docker exec starts every shell with umask 0000; a RHEL 10 login gets 022.
run() { ct "umask 022; $*"; }
show() { run "$@" 2>&1 | tee "$WORK/out" || true; }  # errors are asserted on
has() { grep -qF -- "$1" "$WORK/out" || { echo "MISSING: $1" >&2; exit 1; }; }
hasx() { grep -qx -- "$1" "$WORK/out" || { echo "MISSING LINE: $1" >&2; exit 1; }; }

ct_up "$NAME" findutils tree

run 'useradd alice; groupadd devops; mkdir -p /root/lab'

say "mkdir and mkdir -p"
show 'cd /root/lab && mkdir projects/web/conf'
has "mkdir: cannot create directory 'projects/web/conf': No such file or directory"
show 'cd /root/lab && mkdir -p projects/web/conf && mkdir -p projects/{app,db}/logs && tree projects'
has '    `-- conf'
has "7 directories, 0 files"
show 'cd /root/lab && tree projects | tail -1'
hasx "7 directories, 0 files"
run '[ -d /root/lab/projects/app/logs ] && [ -d /root/lab/projects/db/logs ]'
show 'cd /root/lab && touch projects/web/conf/httpd.conf notes.txt && ls -l notes.txt'
has "-rw-r--r-- 1 root root 0"

say "cp, cp -r, cp -a"
show 'cd /root/lab && cp projects /tmp/'
has "cp: -r not specified; omitting directory 'projects'"
run 'cd /root/lab && cp -r projects /tmp/ && [ -f /tmp/projects/web/conf/httpd.conf ]'
# copying into an existing directory nests the source inside it
run 'cd /root/lab && cp -r projects /tmp/projects && [ -d /tmp/projects/projects ]'
run 'cd /root/lab && echo "Listen 80" > site.conf && chown alice:devops site.conf && chmod 640 site.conf && touch -d "2025-01-15 09:30" site.conf'
show 'cd /root/lab && cp site.conf plain.conf && cp -a site.conf arch.conf && ls -l *.conf'
has "-rw-r----- 1 alice devops 10 Jan 15  2025 arch.conf"
has "-rw-r----- 1 root  root   10 "
has "plain.conf"
has "-rw-r----- 1 alice devops 10 Jan 15  2025 site.conf"
run 'cd /root/lab && rm plain.conf arch.conf'

say "root's interactive aliases"
show 'bash -i -c "alias rm cp mv" 2>/dev/null'
hasx "alias rm='rm -i'"
hasx "alias cp='cp -i'"
hasx "alias mv='mv -i'"

say "mv: rename keeps the inode on one file system"
show 'cd /root/lab && ls -i site.conf && mv site.conf web.conf && ls -i web.conf'
ino1=$(sed -n 1p "$WORK/out" | awk '{print $1}')
ino2=$(sed -n 2p "$WORK/out" | awk '{print $1}')
[ "$ino1" = "$ino2" ]
show 'cd /root/lab && mv web.conf /dev/shm/ && ls -i /dev/shm/web.conf'
ino3=$(awk '{print $1}' "$WORK/out")
[ "$ino3" != "$ino1" ]

say "rm, rmdir"
show 'cd /root/lab && rmdir projects'
has "rmdir: failed to remove 'projects': Directory not empty"
run 'cd /root/lab && mkdir empty && rmdir empty && cp -r projects old && rm -r old && [ ! -e old ]'

say "hard links"
run 'cd /root/lab && echo "Listen 80" > httpd.conf'
show 'cd /root/lab && ln httpd.conf backup.conf && ls -li httpd.conf backup.conf'
has "-rw-r--r-- 2 root root 10"
[ "$(awk '{print $1}' "$WORK/out" | sort -u | wc -l)" = 1 ]
show 'cd /root/lab && echo "Listen 8080" >> backup.conf && cat httpd.conf'
hasx "Listen 8080"
show 'cd /root/lab && rm httpd.conf && ls -li backup.conf'
has "-rw-r--r-- 1 root root 22"
show 'cd /root/lab && ln projects proj-link'
has "ln: projects: hard link not allowed for directory"
show 'echo data > /dev/shm/x && cd /root/lab && ln /dev/shm/x x'
has "ln: failed to create hard link 'x' => '/dev/shm/x': Invalid cross-device link"
show 'cd /root/lab && ls -ld projects projects/web'
has "drwxr-xr-x 5 root root"
has "drwxr-xr-x 3 root root"

say "soft links"
run 'cd /root/lab && echo "Listen 80" > httpd.conf'
show 'cd /root/lab && ln -s httpd.conf current.conf && ls -li httpd.conf current.conf'
has "current.conf -> httpd.conf"
has "lrwxrwxrwx 1 root root 10"
[ "$(awk '{print $1}' "$WORK/out" | sort -u | wc -l)" = 2 ]
show 'cd /root/lab && cat current.conf'
hasx "Listen 80"
show 'cd /root/lab && mv httpd.conf httpd.conf.bak && cat current.conf'
has "cat: current.conf: No such file or directory"
show 'cd /root/lab && find . -xtype l'
hasx "./current.conf"
run 'cd /root/lab && mv httpd.conf.bak httpd.conf'
say "relative targets resolve from the link's directory"
show 'cd /root/lab && ln -s httpd.conf /tmp/web.conf && cat /tmp/web.conf'
has "cat: /tmp/web.conf: No such file or directory"
show 'ln -sf /root/lab/httpd.conf /tmp/web.conf && ls -l /tmp/web.conf && cat /tmp/web.conf'
has "/tmp/web.conf -> /root/lab/httpd.conf"
hasx "Listen 80"
show 'cd /root/lab && ln -s /dev/shm/x xsoft && ln -s projects/web webdir && readlink -f webdir && cd webdir && pwd'
hasx "/root/lab/projects/web"
hasx "/root/lab/webdir"
show 'cd /root/lab && rm webdir && ls -d projects/web'
hasx "projects/web"

echo
echo "ALL 1.6 FILES-AND-LINKS CHECKS PASSED"
