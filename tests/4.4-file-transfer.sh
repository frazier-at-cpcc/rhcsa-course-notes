#!/usr/bin/env bash
# Verifies the secure file transfer commands shown in 4.4 Network Services
# and Secure File Transfer: scp, sftp in batch mode, and rsync over SSH.
# Two AlmaLinux 10 containers on a private network: servera (the client,
# from tests/lib/container.sh) and serverb (sshd and rsync, started here).
# student on servera logs in to bob on serverb with an SSH key, and serverb's
# host key is already in student's known_hosts (objective 10.3 covers both).
# The systemctl half of 4.4 comes from the lab capture
# lab/results/4.4-services-and-transfer.md, not from this script.
# Needs: docker network support
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
source "$HERE/lib/container.sh"
NET=rh4-net; SB=rh4-serverb; NAME=rh4-servera
WORK=$(mktemp -d)
cleanup() {
  ct_down "$NAME"; docker rm -f "$SB" >/dev/null 2>&1 || true
  docker network rm "$NET" >/dev/null 2>&1 || true
  rm -rf "$WORK"
}
trap cleanup EXIT

say() { printf '\n== %s\n' "$*"; }
# show <commands>: run as student on servera, print, keep a copy to assert on
show() { ct_as student "$*" > "$WORK/out" 2>&1 || true; cat "$WORK/out"; }
has() { grep -qF -- "$1" "$WORK/out" || { echo "MISSING: $1" >&2; exit 1; }; }
hasnt() { ! grep -qF -- "$1" "$WORK/out" || { echo "UNEXPECTED: $1" >&2; exit 1; }; }
hasre() { grep -qE -- "$1" "$WORK/out" || { echo "MISSING /$1/" >&2; exit 1; }; }

say "two hosts on one network: servera (client) and serverb (sshd)"
docker network rm "$NET" >/dev/null 2>&1 || true
docker network create "$NET" >/dev/null
docker rm -f "$SB" >/dev/null 2>&1 || true
ca=(); [ -f /root/.ccr/ca-bundle.crt ] && ca=(-v /root/.ccr/ca-bundle.crt:/etc/pki/ca-trust/source/anchors/sandbox-proxy.crt:ro)
docker run -d --name "$SB" --hostname serverb.lab.example.com \
  --network "$NET" --network-alias serverb.lab.example.com --network-alias serverb \
  "${ca[@]}" "$CT_IMAGE" sleep infinity >/dev/null
sb() { docker exec -i "$SB" bash -c "umask 022; $*"; }
sb 'update-ca-trust; dnf -y -q install openssh-server rsync >/dev/null
    ssh-keygen -A >/dev/null; useradd bob; /usr/sbin/sshd'
ct_up "$NAME" openssh-clients rsync
docker network connect --alias servera.lab.example.com --alias servera "$NET" "$NAME"

say "hidden setup: student's key on bob@serverb, serverb in known_hosts"
ct 'useradd student'
ct_as student 'ssh-keygen -q -t ed25519 -N "" -f ~/.ssh/id_ed25519
  ssh-keyscan -t ed25519 serverb serverb.lab.example.com 2>/dev/null > ~/.ssh/known_hosts'
docker exec "$NAME" cat /home/student/.ssh/id_ed25519.pub > "$WORK/key.pub"
sb 'install -d -o bob -g bob -m 700 /home/bob/.ssh; cat > /home/bob/.ssh/authorized_keys
    chown bob: /home/bob/.ssh/authorized_keys; chmod 600 /home/bob/.ssh/authorized_keys' < "$WORK/key.pub"
show 'ssh bob@serverb hostname'
has "serverb.lab.example.com"

say "files to send"
show 'mkdir q3; echo "q3 disk usage" > q3/summary.txt
  dd if=/dev/urandom of=q3/backup.img bs=1M count=5 status=none
  ls -l q3'
hasre '^-rw-r--r-- 1 student student 5242880 .* backup\.img$'
hasre '^-rw-r--r-- 1 student student +14 .* summary\.txt$'

say "scp: push one file, push a tree, pull a file"
show 'scp q3/summary.txt bob@serverb:'
[ ! -s "$WORK/out" ] || { echo "scp printed output" >&2; exit 1; }
show 'ssh bob@serverb ls -l'
hasre '^-rw-r--r-- 1 bob bob 14 .* summary\.txt$'
show 'scp -r q3 bob@serverb:/tmp/'
[ ! -s "$WORK/out" ] || { echo "scp -r printed output" >&2; exit 1; }
show 'ssh bob@serverb ls /tmp/q3'
has "backup.img"
has "summary.txt"
show 'scp bob@serverb:/etc/hostname sb-name; cat sb-name'
has "serverb.lab.example.com"
# the wrong user: no key there, and -B (batch mode) keeps it from asking
show 'scp -B q3/summary.txt alice@serverb:'
has "alice@serverb: Permission denied (publickey,gssapi-keyex,gssapi-with-mic,password)."
has "scp: Connection closed"

say "sftp in batch mode"
ct_as student 'printf "cd /tmp/q3\nls -l\nget backup.img fetched.img\nbye\n" > batch.sftp'
show 'cat batch.sftp'
has "get backup.img fetched.img"
show 'sftp -b batch.sftp bob@serverb'
has "sftp> cd /tmp/q3"
has "sftp> ls -l"
hasre '^-rw-r--r-- +\? bob +bob +5242880 .* backup\.img$'
has "sftp> get backup.img fetched.img"
has "sftp> bye"
show 'ls -l fetched.img'
hasre '^-rw-r--r-- 1 student student 5242880 .* fetched\.img$'
sums=$(ct_as student 'sha256sum < fetched.img; sha256sum < q3/backup.img' | sort -u | wc -l)
[ "$sums" = 1 ] || { echo "fetched.img differs from backup.img" >&2; exit 1; }
# a failing batch command stops the batch with a non-zero exit
ct_as student 'printf "cd /tmp/q3\nget nosuch.txt\nget backup.img x.img\n" > bad.sftp'
show 'cat bad.sftp'
show 'sftp -b bad.sftp bob@serverb; echo $?'
has 'File "/tmp/q3/nosuch.txt" not found.'
[ "$(tail -1 "$WORK/out")" = 1 ] || { echo "sftp -b did not exit 1" >&2; exit 1; }
hasnt "x.img"

say "rsync over SSH"
show 'rsync -av q3/ bob@serverb:q3/'
has "sending incremental file list"
has "created directory q3"
has "backup.img"
has "summary.txt"
hasre '^sent [0-9,]+ bytes  received [0-9,]+ bytes'
has "total size is 5,242,894"
show 'echo appended >> q3/summary.txt
  rsync -av q3/ bob@serverb:q3/'
has "summary.txt"
hasnt "backup.img"
has "total size is 5,242,903"
show 'rm q3/backup.img
  rsync -avn --delete q3/ bob@serverb:q3/'
has "deleting backup.img"
has "(DRY RUN)"
show 'ssh bob@serverb ls q3'
has "backup.img"
show 'rsync -av --delete q3/ bob@serverb:q3/'
has "deleting backup.img"
hasnt "(DRY RUN)"
show 'ssh bob@serverb ls q3'
hasnt "backup.img"
has "summary.txt"
# no trailing slash on the source: rsync copies the directory itself
show 'rsync -a q3 bob@serverb:archive/
  ssh bob@serverb find archive'
has "archive/q3/summary.txt"
# -a keeps the modification time; scp without -p does not
show 'ssh bob@serverb stat -c %y q3/summary.txt; stat -c %y q3/summary.txt'
[ "$(sed -n 1p "$WORK/out")" = "$(sed -n 2p "$WORK/out")" ] || { echo "rsync -a lost mtime" >&2; exit 1; }

echo
echo "ALL 4.4 FILE-TRANSFER CHECKS PASSED"
