#!/usr/bin/env bash
# Verifies every command shown in 1.5 Archives and Compression.
# Runs in a throwaway AlmaLinux 10 container; exits non-zero on the first
# failure.
# Needs: docker
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
source "$HERE/lib/container.sh"
WORK=$(mktemp -d)
NAME=rh1b-15
trap 'ct_down "$NAME"; rm -rf "$WORK"' EXIT

say() { printf '\n== %s\n' "$*"; }
# docker exec starts every shell with umask 0000; a RHEL 10 login gets 022.
run() { ct "umask 022; $*"; }
run_as() { local u="$1"; shift; ct_as "$u" "umask 022; $*"; }
# show: print a command's output and keep a copy for the assertions
show() { run "$@" 2>&1 | tee "$WORK/out"; }
has() { grep -qF -- "$1" "$WORK/out" || { echo "MISSING: $1" >&2; exit 1; }; }

ct_up "$NAME" tar gzip bzip2 xz file acl

say "set up a small web document root"
run 'useradd alice; useradd bob; groupadd devops
mkdir -p /srv/web/css
echo "<h1>servera</h1>" > /srv/web/index.html
echo "body{}" > /srv/web/css/site.css
seq 1 40000 | sed "s|^|10.0.0.5 GET /index.html 200 |" \
  > /srv/web/access.log
chown -R alice:devops /srv/web
chmod 640 /srv/web/index.html'

say "create with an absolute path, then list"
show 'cd /root && tar -czf web.tar.gz /srv/web'
has "tar: Removing leading \`/' from member names"
show 'cd /root && tar -tf web.tar.gz'
has "srv/web/index.html"
show 'cd /root && tar -tvf web.tar.gz'
has "-rw-r----- alice/devops"
has "srv/web/css/site.css"

say "create with -C and each compression flag"
run 'cd /root
tar -cf web.tar -C /srv web
tar -czf web.tar.gz -C /srv web
tar -cjf web.tar.bz2 -C /srv web
tar -cJf web.tar.xz -C /srv web'
show 'cd /root && wc -c web.tar*'
has "web.tar.bz2"
# sizes rank: xz < bzip2 < gzip < plain tar
run 'cd /root
[ $(stat -c %s web.tar.xz) -lt $(stat -c %s web.tar.bz2) ]
[ $(stat -c %s web.tar.bz2) -lt $(stat -c %s web.tar.gz) ]
[ $(stat -c %s web.tar.gz) -lt $(stat -c %s web.tar) ]'
show 'cd /root && file web.tar web.tar.bz2 web.tar.xz'
has "web.tar.xz:  XZ compressed data, checksum CRC64"
show 'cd /root && file web.tar*'
has "web.tar:     POSIX tar archive (GNU)"
has "bzip2 compressed data"
has "gzip compressed data"
has "XZ compressed data"
show 'cd /root && tar -tf web.tar.bz2'
has "web/css/site.css"
# -a picks the compressor from the suffix
show 'cd /root && tar -caf auto.tar.bz2 -C /srv web && file auto.tar.bz2'
has "bzip2 compressed"

say "the -f trap: -f takes the next word as the archive name"
show 'cd /root && mkdir trap && cd trap && tar -cfz web.tgz -C /srv web; echo "exit=$?"; ls'
has "tar: web.tgz: Cannot stat: No such file or directory"
has "exit=2"
grep -qx "z" "$WORK/out"

say "extract as root: -C, owners and modes kept"
show 'mkdir /restore && tar -xf /root/web.tar.gz -C /restore && ls -l /restore/web'
has "-rw-r----- 1 alice devops"
show 'tar -xf /root/web.tar.gz -C /nowhere; echo "exit=$?"'
has "tar: /nowhere: Cannot open: No such file or directory"
say "extract one member"
show 'cd /tmp && tar -xf /root/web.tar.bz2 web/index.html && ls -R web'
has "index.html"
run '[ ! -e /tmp/web/access.log ]'

say "extract as a regular user: user owns, umask applies unless -p"
run 'cp /root/web.tar.gz /home/bob/ && chown bob: /home/bob/web.tar.gz'
show_as() { run_as bob "$@" 2>&1 | tee "$WORK/out"; }
show_as 'umask 077; tar -xf web.tar.gz; ls -l web'
has "-rw------- 1 bob bob"
has "drwx------ 2 bob bob"
show_as 'umask 077; rm -rf web; tar -xpf web.tar.gz; ls -l web'
has "-rw-r--r-- 1 bob bob"
has "-rw-r----- 1 bob bob"

say "ACLs survive only with --acls"
run 'mkdir -p /root/acl/d && touch /root/acl/d/f && setfacl -m u:bob:rw /root/acl/d/f
cd /root && tar -cf noacl.tar -C acl d && tar --acls -cf acl.tar -C acl d
mkdir r1 r2 && tar -xf noacl.tar -C r1 && tar --acls -xf acl.tar -C r2'
show 'cd /root && getfacl -c r1/d/f'
grep -q "user:bob" "$WORK/out" && { echo "ACL kept without --acls" >&2; exit 1; }
show 'cd /root && getfacl -c r2/d/f'
has "user:bob:rw-"

say "gzip, gunzip, -k, -l, zcat"
run 'mkdir /root/z && cp /srv/web/access.log /root/z/'
show 'cd /root/z && gzip access.log && ls'
has "access.log.gz"
grep -qx "access.log" "$WORK/out" && { echo "gzip kept original" >&2; exit 1; }
show 'cd /root/z && gzip -l access.log.gz'
has "93.3% access.log"
show 'cd /root/z && gunzip access.log.gz && gzip -k access.log && ls'
grep -qx "access.log" "$WORK/out"
grep -qx "access.log.gz" "$WORK/out"
show 'cd /root/z && zcat access.log.gz | tail -1'
has "10.0.0.5 GET /index.html 200 40000"
run 'cd /root/z && [ "$(gzip -d -c access.log.gz | sha256sum)" = "$(sha256sum < access.log)" ]'

say "bzip2, bunzip2, bzcat"
run 'cd /root/z && rm access.log.gz'
show 'cd /root/z && bzip2 -k access.log && ls'
grep -qx "access.log.bz2" "$WORK/out"
show 'cd /root/z && bunzip2 access.log.bz2; echo "exit=$?"'
has "bunzip2: Output file access.log already exists."
has "exit=1"
show 'cd /root/z && bzcat access.log.bz2 | head -1'
has "10.0.0.5 GET /index.html 200 1"
show 'cd /root/z && rm access.log && bunzip2 access.log.bz2 && ls'
grep -qx "access.log" "$WORK/out"

say "gzip -r compresses files one by one; it does not archive"
show 'cp -a /srv/web /root/gz && gzip -r /root/gz && find /root/gz -type f | sort'
has "/root/gz/css/site.css.gz"
has "/root/gz/index.html.gz"

say "levels: -1 fast, -9 small"
run 'cd /root/z
gzip -1 -c access.log > fast.gz
gzip -9 -c access.log > small.gz
[ $(stat -c %s small.gz) -lt $(stat -c %s fast.gz) ]'

echo
echo "ALL 1.5 ARCHIVES CHECKS PASSED"
