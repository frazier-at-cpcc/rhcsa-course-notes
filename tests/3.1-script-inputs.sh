#!/usr/bin/env bash
# Verifies every command shown in 3.1 Script Inputs and Command Output.
# The scripts are pulled straight out of the notes' ```bash label="..." blocks,
# installed in an AlmaLinux 10 container, and run as the user student.
# Needs: docker, awk
set -euo pipefail
cd "$(dirname "$0")"
source lib/container.sh
NOTES=../content/domain-3/3.1-script-inputs.md
CT=rh232-31
trap 'ct_down $CT' EXIT
ct_up $CT sudo

say() { printf '\n== %s\n' "$*"; }
run() { printf '$ %s\n' "$1"; OUT=$(ct_as student "$1" 2>&1) || true; printf '%s\n' "$OUT"; }
has() { grep -qE -- "$1" <<<"$OUT" || { echo "MISSING: $1" >&2; exit 1; }; }
hasx() { grep -qxF -- "$1" <<<"$OUT" || { echo "MISSING LINE: $1" >&2; exit 1; }; }
# block FILE: print the fenced block labelled FILE from the notes
block() {
  awk -v want="label=\"$1\"" '
    /^```/ && on { exit }
    on { print }
    /^```[a-z]+ / && index($0, want) { on = 1 }' "$NOTES"
}
install_script() {   # copy a script from the notes into ~student
  local f=$1
  [ -n "$(block "$f")" ] || { echo "no block $f in notes" >&2; exit 1; }
  block "$f" | ct "cat > /home/student/$f && chmod 755 /home/student/$f && chown student: /home/student/$f"
  ct "bash -n /home/student/$f"
}

say "accounts for the examples"
ct 'useradd student && echo "student ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/student
    chmod 440 /etc/sudoers.d/student
    groupadd devops && useradd -G devops alice'
for f in args.sh diskcheck.sh userinfo.sh newproj.sh; do install_script "$f"; done

say "PATH already holds script directories"
run 'echo $PATH | tr : "\n" | grep -E "bin$" | head -3'
hasx '/home/student/.local/bin'; hasx '/home/student/bin'
run 'echo $PATH'; has ':/usr/local/bin:'

say "positional parameters, \$@ versus \$*, shift"
run './args.sh "web server" db cache'
hasx 'Called as: ./args.sh'; hasx 'Arg count: 3'
hasx 'Arg: [web server]'; hasx 'Arg: [db]'; hasx 'Arg: [cache]'
hasx 'Star: [web server db cache]'
hasx 'After shift: 2 left, $1=db'

say "command substitution and the script's exit status"
run './diskcheck.sh; echo $?'
has '^/ is [0-9]+% full \(limit 80%\)$'
pct=$(grep -oE '[0-9]+%' <<<"$OUT" | head -1)
want=0; [ "${pct%\%}" -lt 80 ] || want=1
[ "$(tail -1 <<<"$OUT")" = "$want" ]
run './diskcheck.sh / 5; echo $?'
if [ "${pct%\%}" -ge 5 ]; then [ "$(tail -1 <<<"$OUT")" = 1 ]; fi
hasx "/ is $pct full (limit 5%)"

say "exit codes"
run './userinfo.sh; echo $?'
hasx 'Usage: ./userinfo.sh USERNAME'; [ "$(tail -1 <<<"$OUT")" = 2 ]
run './userinfo.sh alice'
hasx 'User:   alice (UID 1001)'; hasx 'Home:   /home/alice'
hasx 'Groups: alice devops'
run './userinfo.sh carol; echo "status $?"'
hasx './userinfo.sh: no such user: carol'; hasx 'status 1'
run 'getent passwd carol; echo $?'; hasx '2'
run './userinfo.sh alice bob 2>/dev/null; echo $?'; hasx '2'

say "read"
run "printf 'atlas\ndevops\n' | sudo ./newproj.sh"
hasx 'drwxrws--- root:devops /srv/projects/atlas'
! grep -q 'Project name' <<<"$OUT"     # no prompt when stdin is a pipe
run 'read -r first rest <<< "web db cache"; echo "$first / $rest"'
hasx 'web / db cache'

echo
echo "ALL 3.1 SCRIPT-INPUTS CHECKS PASSED"
