# Helpers for the lab capture scripts in lab/topics/. Sourced by lab/run.sh;
# not meant to be run on its own.
#
# A topic script defines up to three functions:
#   phase1    the commands to capture
#   phase2    optional; run after a reboot, to prove the change persists
#   cleanup   undo everything, so the next topic starts from a clean system
#
# Inside them:
#   section "Title"        start a section in the results file
#   block "Label"          start a console block (default label "Terminal")
#   run 'command'          run as the student user, record "$ command" + output
#   run_in DIR 'command'   same, in another working directory
#   expect 'regex'         the last run's output must match (records PASS/FAIL)
#   expect_rc N            the last run's exit status must be N
#   note "text"            a plain note in the results file
#   setup 'command'        run as root, silently (logged), for scaffolding the
#                          notes do not show; a failure here fails the topic
#   show_file PATH [LABEL] record a file's contents in a labeled block
#
# Commands run through a login shell as "student", exactly as typed, so the
# output matches what a student sees; use sudo in the command the way the
# notes show it.

LAB_USER="${LAB_USER:-student}"

_open=0
_close_block() { if [ "$_open" = 1 ]; then echo '```' >>"$OUT"; echo >>"$OUT"; _open=0; fi; }

section() { _close_block; printf '### %s\n\n' "$1" >>"$OUT"; }
note() { _close_block; printf '%s\n\n' "$*" >>"$OUT"; }
block() { _close_block; printf '```console label="%s"\n' "${1:-Terminal}" >>"$OUT"; _open=1; }

_run_as_student() {   # dir command
  runuser -l "$LAB_USER" -c "cd $(printf '%q' "$1") && $2" 2>&1
}

run_in() {
  local dir="$1" c="$2"
  [ "$_open" = 1 ] || block "Terminal"
  printf '$ %s\n' "$c" >>"$OUT"
  LAST_OUT=$(_run_as_student "$dir" "$c"); LAST_RC=$?
  [ -n "$LAST_OUT" ] && printf '%s\n' "$LAST_OUT" >>"$OUT"
  printf '%s\t%s\t%s\n' "$TOPIC" "$LAST_RC" "$c" >>"$RESULTS/commands.tsv"
  return 0
}
run() { run_in "/home/$LAB_USER" "$1"; }

expect() {
  if printf '%s\n' "$LAST_OUT" | grep -Eq -- "$1"; then
    printf 'PASS\t%s\texpect %s\n' "$TOPIC" "$1" >>"$RESULTS/checks.tsv"
  else
    printf 'FAIL\t%s\texpect %s\n' "$TOPIC" "$1" >>"$RESULTS/checks.tsv"
  fi
}
expect_rc() {
  if [ "$LAST_RC" = "$1" ]; then
    printf 'PASS\t%s\texit %s\n' "$TOPIC" "$1" >>"$RESULTS/checks.tsv"
  else
    printf 'FAIL\t%s\texit %s (got %s)\n' "$TOPIC" "$1" "$LAST_RC" >>"$RESULTS/checks.tsv"
  fi
}

setup() {
  printf '[%s] %s\n' "$TOPIC" "$1" >>"$RESULTS/setup.log"
  if ! bash -c "$1" >>"$RESULTS/setup.log" 2>&1; then
    printf 'FAIL\t%s\tsetup: %s\n' "$TOPIC" "$1" >>"$RESULTS/checks.tsv"
    return 1
  fi
}

show_file() {
  _close_block
  printf '```text label="%s"\n' "${2:-$1}" >>"$OUT"
  cat "$1" >>"$OUT" 2>&1
  printf '```\n\n' >>"$OUT"
}

# The spare disks and NIC, discovered once by run.sh preflight.
lab_env() { . "$STATE/env"; }

# part DISK N: the device name of partition N (vdb -> vdb1, nvme0n1 -> nvme0n1p1)
part() { case "$1" in *[0-9]) echo "${1}p$2" ;; *) echo "$1$2" ;; esac; }

# wipe DISK: remove every signature and partition table (cleanup helper)
wipe() { local d; for d in "$1"?*; do [ -b "$d" ] && lvmdevices -y --deldev "$d" >/dev/null 2>&1; done; wipefs -a "$1"* >/dev/null 2>&1; wipefs -a "$1" >/dev/null 2>&1; partprobe "$1" 2>/dev/null; udevadm settle; }
