#!/usr/bin/env bash
# Verifies every command shown in 1.8 System Documentation.
# Runs in a throwaway AlmaLinux 10 container; exits non-zero on the first
# failure.
#
# The container image swaps in coreutils-single and ships no man pages, so the
# test installs man-db, man-pages, info, the full coreutils, and a few
# packages whose pages the notes use. In a container nothing runs
# man-db-cache-update.service after dnf, which is what lets the notes show a
# stale index being rebuilt with mandb.
#
# Not executable here: the interactive keys of man (less) and info. The
# notes give those as tables.
# Needs: docker
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
source "$HERE/lib/container.sh"
WORK=$(mktemp -d)
NAME=rh1b-18
trap 'ct_down "$NAME"; rm -rf "$WORK"' EXIT

say() { printf '\n== %s\n' "$*"; }
run() { ct "umask 022; $*"; }
# Commands run as student (wheel, passwordless sudo) with a narrow terminal,
# so man formats for a 48-column notes page.
show() { ct_as student "umask 022; export MANWIDTH=48 COLUMNS=48; $*" 2>&1 | tee "$WORK/out" || true; }
has() { grep -qF -- "$1" "$WORK/out" || { echo "MISSING: $1" >&2; exit 1; }; }
hasx() { grep -qx -- "$1" "$WORK/out" || { echo "MISSING LINE: $1" >&2; exit 1; }; }

ct_up "$NAME" sudo
run 'dnf -y -q swap coreutils-single coreutils --allowerasing >/dev/null
dnf -y -q install man-db man-pages info util-linux passwd cronie chrony \
  NetworkManager >/dev/null
dnf -y -q reinstall shadow-utils tar >/dev/null
useradd -G wheel student
echo "student ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/student'

say "rpm file trigger: what keeps the index current on a real system"
run 'rpm -q --filetriggers man-db' > "$WORK/out"
has "systemctl start man-db-cache-update"
run 'rpm -ql man-db' > "$WORK/out"
has "/usr/lib/systemd/system/man-db-cache-update.service"
grep -q cron "$WORK/out" && { echo "man-db ships a cron job" >&2; exit 1; }

say "stale index, then mandb"
show 'man -k crontab'
hasx "crontab: nothing appropriate."
show 'sudo mandb'
has "manual pages were added."
show 'man -k crontab'
has "crontab (1)"
has "crontab (5)"

say "whatis / man -f, man -w, sections"
show 'man -f passwd'
has "passwd (1)           - change user password"
has "passwd (5)           - password file"
show 'whatis passwd'
has "passwd (5)           - password file"
show 'man -w passwd; man -w 5 passwd'
hasx "/usr/share/man/man1/passwd.1.gz"
hasx "/usr/share/man/man5/passwd.5.gz"
show 'man -aw passwd'
[ "$(wc -l < "$WORK/out")" = 2 ]
show 'man 5 passwd 2>/dev/null | head -6'
has "passwd(5)     File Formats Manual    passwd(5)"
has "passwd - password file"
# the section table in man(1) backs the table in the notes
show 'MANWIDTH=200 man 1 man 2>/dev/null | grep -E "^ +[1-9]   "'
has "1   Executable programs or shell commands"
has "5   File formats and conventions"
has "7   Miscellaneous"
has "8   System administration commands"

# every page named in the notes' section table and exam box exists
show 'man -w ls tar 2 open 4 null 5 crontab 5 fstab 7 nmcli-examples 8 useradd 8 mandb'
[ "$(grep -c '^/usr/share/man/man' "$WORK/out")" = 9 ]
has "/usr/share/man/man5/fstab.5.gz"
has "/usr/share/man/man4/null.4.gz"

say "apropos and section filters"
show 'man -k nmcli'
has "nmcli-examples (7)   - usage examples of nmcli"
show 'apropos -s 8 passwd'
has "chpasswd (8)"
grep -q "(5)" "$WORK/out" && { echo "section filter leaked" >&2; exit 1; }
show 'man -k "^passwd"'
has "passwd (1)"
has "passwd (5)"
grep -q "chpasswd" "$WORK/out" && { echo "anchor did not filter" >&2; exit 1; }

say "--help and builtins"
show 'tar --help | grep -- "--bzip2"'
has "-j, --bzip2"
show 'type cd; help cd | head -2'
hasx "cd is a shell builtin"
has "Change the shell working directory."

say "info"
show 'info -w tar'
hasx "/usr/share/info/tar.info.gz"
show 'info coreutils "ls invocation" | head -1'
has "Node: ls invocation,  Next: dir invocation,  Up: Directory listing"

say "/usr/share/doc"
show 'rpm -qd chrony'
hasx "/usr/share/doc/chrony/README"
hasx "/usr/share/doc/chrony/chrony.keys.example"
hasx "/usr/share/man/man5/chrony.conf.5.gz"
show 'ls /usr/share/doc/chrony'
has "chrony.keys.example"
show 'head -3 /usr/share/doc/chrony/chrony.keys.example'
has "#"
show 'ls -d /usr/share/licenses/chrony'
hasx "/usr/share/licenses/chrony"

echo
echo "ALL 1.8 DOCUMENTATION CHECKS PASSED"
