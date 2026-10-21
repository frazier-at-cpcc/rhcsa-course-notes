#!/usr/bin/env bash
# Verifies every command shown in 9.2 Groups and Membership.
# Runs in a throwaway AlmaLinux 10 container as a wheel user with sudo;
# exits non-zero on the first failure. Groups live in /etc/group and
# /etc/gshadow, so they persist across a reboot with no extra step.
# Needs: docker
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
source "$HERE/lib/container.sh"
WORK=$(mktemp -d)
NAME=rh92-92
trap 'ct_down "$NAME"; rm -rf "$WORK"' EXIT

say() { printf '\n== %s\n' "$*"; }
showas() {   # user command...
  local u="$1"; shift
  printf '$ %s\n' "$*"
  ct_as "$u" "umask 022; $*" 2>&1 | tee "$WORK/out" || true
}
show() { showas student "$@"; }
has() { grep -qF -- "$1" "$WORK/out" || { echo "MISSING: $1" >&2; exit 1; }; }
hasx() { grep -qxF -- "$1" "$WORK/out" || { echo "MISSING LINE: $1" >&2; exit 1; }; }
hasnt() { if grep -qF -- "$1" "$WORK/out"; then echo "UNEXPECTED: $1" >&2; exit 1; fi; }

ct_up "$NAME" sudo util-linux
ct 'useradd -G wheel student
    echo "student ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/student
    chmod 440 /etc/sudoers.d/student
    useradd -u 2001 alice; useradd -u 2002 bob; useradd -u 2003 carol'

say "groupadd"
show 'sudo groupadd -g 3000 devops'
show 'sudo groupadd dbadmin'
show "grep -E '^(devops|dbadmin):' /etc/group"
hasx 'devops:x:3000:'
hasx 'dbadmin:x:3001:'
show 'sudo groupadd -r backup; getent group backup'
gid=$(awk -F: '/^backup:/{print $3}' "$WORK/out"); [ "$gid" -lt 1000 ]

say "primary vs supplementary"
show 'id alice'
hasx 'uid=2001(alice) gid=2001(alice) groups=2001(alice)'
show 'sudo usermod -aG devops alice'
show 'id -Gn alice'
hasx 'alice devops'
show 'id alice'
hasx 'uid=2001(alice) gid=2001(alice) groups=2001(alice),3000(devops)'
show 'grep ^devops: /etc/group'
hasx 'devops:x:3000:alice'

say "usermod -G without -a replaces the list"
show 'sudo usermod -G dbadmin alice; id -Gn alice'
hasx 'alice dbadmin'
show 'sudo usermod -aG devops,dbadmin alice'
show 'id -Gn alice'
hasx 'alice devops dbadmin'
show 'groups alice'
hasx 'alice : alice devops dbadmin'
show 'sudo useradd -G devops -g dbadmin dave'
show 'id -gn dave; id -Gn dave'
hasx 'dbadmin'
hasx 'dbadmin devops'
show 'sudo usermod -g devops bob; id bob'
hasx 'uid=2002(bob) gid=3000(devops) groups=3000(devops)'

say "gpasswd"
show 'sudo gpasswd -a carol devops'
hasx 'Adding user carol to group devops'
show 'sudo gpasswd -d alice dbadmin'
hasx 'Removing user alice from group dbadmin'
show 'sudo gpasswd -M alice,carol dbadmin; grep -E "^(devops|dbadmin):" /etc/group'
hasx 'devops:x:3000:alice,dave,carol'
hasx 'dbadmin:x:3001:alice,carol'
show 'sudo gpasswd -A alice devops; sudo grep ^devops: /etc/gshadow'
hasx 'devops:!:alice:alice,dave,carol'
# The group administrator can manage members without sudo
showas alice 'gpasswd -d dave devops'
hasx 'Removing user dave from group devops'

say "groupmod"
show 'touch /tmp/report; sudo chgrp devops /tmp/report'
show 'sudo groupmod -n ops devops; sudo groupmod -g 3100 ops; grep ^ops: /etc/group; id bob'
hasx 'ops:x:3100:alice,carol'
hasx 'uid=2002(bob) gid=3100(ops) groups=3100(ops)'
# Files keep the old GID number after groupmod -g
show 'ls -l /tmp/report'
has 'student 3000 '
show 'sudo find /tmp -gid 3000 -exec chgrp ops {} +; ls -l /tmp/report'
has 'student ops '

say "groupdel"
show 'sudo groupdel ops'
hasx "groupdel: cannot remove the primary group of user 'bob'"
show 'sudo groupdel backup; getent group backup || echo gone'
hasx 'gone'

say "newgrp and sg change the group for new files"
showas alice 'touch a.txt; sg ops -c "touch b.txt"'
showas alice 'ls -l a.txt b.txt'
has 'alice alice 0'
has 'alice ops   0'
showas alice 'echo "touch c.txt; id -gn" | newgrp ops; ls -l c.txt'
hasx 'ops'
has 'alice ops 0'
# A non-member is asked for a group password, which is not set
ct 'useradd erin'
showas erin 'sg ops -c id < /dev/null'
hasnt 'gid=3100(ops)'

say "group membership is read at login"
# A session that started before the change keeps its old list until re-login
ct 'su - erin -c "id -Gn > /tmp/before; sleep 4; id -Gn > /tmp/after" &
    sleep 1.5; usermod -aG ops erin; sleep 4'
[ "$(ct cat /tmp/before)" = "erin" ] && [ "$(ct cat /tmp/after)" = "erin" ]
showas erin 'id -Gn; id -Gn erin'
hasx 'erin ops'

echo; echo "ALL 9.2 GROUPS CHECKS PASSED"
