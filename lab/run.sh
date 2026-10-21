#!/usr/bin/env bash
# Capture the RHCSA lab sessions on a disposable RHEL 10 machine.
#
#   sudo lab/run.sh                 preflight, then every topic in lab/topics/
#   sudo lab/run.sh 5.2 6.3         only these topics (by number prefix)
#   sudo lab/run.sh --status        progress and check counts so far
#   sudo lab/run.sh --preflight     check the machine without running topics
#
# Topics that must prove persistence reboot the machine. The script installs a
# systemd timer that resumes the run about a minute after each boot, so the
# whole run is unattended: start it, let it reboot, and come back to
# lab/results/ (and lab/results.tar.gz) when --status says it is done.
#
# DESTRUCTIVE: it repartitions the two spare disks, adds and removes users,
# changes firewall, SELinux, network, and boot loader settings. Run it only on
# a throwaway VM built for this. See lab/README.md.
set -uo pipefail

LAB_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
RESULTS="$LAB_DIR/results"
STATE=/var/lib/rhcsa-lab
UNIT=rhcsa-lab-resume
# shellcheck source=lab/lib.sh
. "$LAB_DIR/lib.sh"

die() { echo "run.sh: $*" >&2; exit 1; }
log() { printf '%s %s\n' "$(date '+%F %T')" "$*" | tee -a "$RESULTS/run.log"; }

[ "$(id -u)" = 0 ] || die "run as root (sudo lab/run.sh)"
mkdir -p "$RESULTS" "$STATE"

topic_files() {
  local f
  if [ $# -eq 0 ]; then
    find "$LAB_DIR/topics" -name '*.sh' -printf '%f\n' | sort -V
  else
    for f in "$@"; do
      find "$LAB_DIR/topics" -name "$f-*.sh" -printf '%f\n'
    done | sort -V
  fi
}

# ---------- preflight ----------

preflight() {
  local ok=1
  . /etc/os-release
  log "OS: $PRETTY_NAME, kernel $(uname -r)"
  case "${VERSION_ID%%.*}" in 10) ;; *) echo "  needs RHEL 10 (or AlmaLinux/Rocky 10); found $VERSION_ID"; ok=0 ;; esac
  [ "$(getenforce)" = Enforcing ] || { echo "  SELinux must be Enforcing (found $(getenforce))"; ok=0; }

  # Spare disks: whole disks with no partitions, holders, or file systems.
  local root_disk spare=()
  root_disk=$(lsblk -no PKNAME "$(findmnt -no SOURCE /)" 2>/dev/null | head -1)
  if [ -n "${LAB_DISKS:-}" ]; then
    read -r -a spare <<<"$LAB_DISKS"
  else
    while read -r name type; do
      [ "$type" = disk ] || continue
      [ "$name" = "$root_disk" ] && continue
      [ "$(lsblk -no NAME "/dev/$name" | wc -l)" = 1 ] || continue
      [ -z "$(blkid -p "/dev/$name" 2>/dev/null)" ] || continue
      spare+=("/dev/$name")
    done < <(lsblk -dno NAME,TYPE | grep -v '^sr\|^loop\|^zram')
  fi
  if [ "${#spare[@]}" -lt 2 ]; then
    echo "  needs two blank spare disks (found: ${spare[*]:-none}); set LAB_DISKS=\"/dev/vdb /dev/vdc\" to choose"
    ok=0
  fi

  # Spare NIC: an Ethernet device with no active connection.
  local nic="${LAB_NIC:-}"
  if [ -z "$nic" ]; then
    nic=$(nmcli -t -f DEVICE,TYPE,STATE device | awk -F: '$2=="ethernet" && $3!="connected" {print $1; exit}')
  fi
  [ -n "$nic" ] || { echo "  needs a second, unconfigured Ethernet NIC; set LAB_NIC=<device> to choose"; ok=0; }

  local main_nic main_ip
  main_nic=$(ip -o route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<NF;i++) if($i=="dev") print $(i+1)}')
  main_ip=$(ip -o -4 addr show dev "$main_nic" 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -1)
  dnf -q repolist >/dev/null 2>&1 || { echo "  dnf cannot reach its repositories"; ok=0; }

  [ "$ok" = 1 ] || die "preflight failed; fix the items above"
  cat >"$STATE/env" <<EOF
DISK1=${spare[0]}
DISK2=${spare[1]}
NIC=$nic
MAIN_NIC=$main_nic
MAIN_IP=$main_ip
EOF
  log "spare disks ${spare[0]} ${spare[1]}, spare NIC $nic, main NIC $main_nic ($main_ip)"
}

prepare() {
  . "$STATE/env"
  log "preparing the machine"
  dnf -y -q install lvm2 xfsprogs dosfstools e2fsprogs parted nfs-utils autofs \
    firewalld policycoreutils-python-utils setroubleshoot-server httpd chrony \
    tuned at cronie flatpak tar bzip2 rsync bind-utils psmisc lsof man-pages \
    createrepo_c dnf-plugins-core >>"$RESULTS/setup.log" 2>&1 || die "package install failed"
  id "$LAB_USER" >/dev/null 2>&1 || useradd -G wheel "$LAB_USER"
  echo "$LAB_USER:redhat" | chpasswd
  echo "$LAB_USER ALL=(ALL) NOPASSWD: ALL" >/etc/sudoers.d/90-rhcsa-lab
  chmod 440 /etc/sudoers.d/90-rhcsa-lab
  # A key the harness uses to log in as the student over SSH (see lib.sh).
  [ -f "$STATE/id_ed25519" ] || ssh-keygen -q -t ed25519 -N "" -C rhcsa-lab-harness -f "$STATE/id_ed25519"
  install -d -m 700 -o "$LAB_USER" -g "$LAB_USER" "/home/$LAB_USER/.ssh"
  grep -qf "$STATE/id_ed25519.pub" "/home/$LAB_USER/.ssh/authorized_keys" 2>/dev/null \
    || cat "$STATE/id_ed25519.pub" >>"/home/$LAB_USER/.ssh/authorized_keys"
  chown "$LAB_USER:" "/home/$LAB_USER/.ssh/authorized_keys"; chmod 600 "/home/$LAB_USER/.ssh/authorized_keys"
  restorecon -R "/home/$LAB_USER/.ssh"
  hostnamectl hostname servera.lab.example.com
  grep -q 'servera.lab.example.com' /etc/hosts \
    || echo "$MAIN_IP servera.lab.example.com servera" >>/etc/hosts
  systemctl enable --now firewalld atd crond chronyd >>"$RESULTS/setup.log" 2>&1
  # Keep NetworkManager from putting an automatic DHCP profile on the spare
  # NIC; topic 8.1 configures it by hand.
  local mac uuid
  mac=$(cat "/sys/class/net/$NIC/address")
  printf '[main]\nno-auto-default=%s\n' "$mac" >/etc/NetworkManager/conf.d/90-rhcsa-lab.conf
  for uuid in $(nmcli -g UUID,DEVICE connection show | awk -F: -v n="$NIC" '$2==n {print $1}'); do
    nmcli connection delete "$uuid" >>"$RESULTS/setup.log" 2>&1
  done
  systemctl reload NetworkManager
  {
    echo "date: $(date -Is)"
    cat /etc/os-release
    echo "kernel: $(uname -r)"
    echo "selinux: $(getenforce)"
    rpm -q systemd dnf NetworkManager firewalld lvm2 xfsprogs chrony tuned autofs nfs-utils flatpak policycoreutils grub2-tools 2>&1
    lsblk
    nmcli device status
    cat "$STATE/env"
  } >"$RESULTS/environment.txt"
}

# ---------- running topics ----------

install_resume() {
  cat >/etc/systemd/system/$UNIT.service <<EOF
[Unit]
Description=Resume the RHCSA lab capture after a reboot
[Service]
Type=oneshot
ExecStart=/usr/bin/bash $LAB_DIR/run.sh --resume
TimeoutStartSec=infinity
EOF
  cat >/etc/systemd/system/$UNIT.timer <<EOF
[Unit]
Description=Resume the RHCSA lab capture after boot
[Timer]
OnBootSec=60s
[Install]
WantedBy=timers.target
EOF
  systemctl daemon-reload
  systemctl enable $UNIT.timer >/dev/null 2>&1
}

remove_resume() {
  systemctl disable $UNIT.timer >/dev/null 2>&1
  rm -f /etc/systemd/system/$UNIT.service /etc/systemd/system/$UNIT.timer
  systemctl daemon-reload
}

# Run one phase of one topic in a subshell so topics cannot leak functions.
run_phase() {   # file phase
  local file="$1" phase="$2"
  (
    TOPIC="${file%.sh}"
    OUT="$RESULTS/$TOPIC.md"
    phase1() { :; }; cleanup() { :; }
    # shellcheck disable=SC1090
    . "$LAB_DIR/topics/$file"
    lab_env
    if [ "$phase" = phase1 ]; then
      : >"$OUT"
      printf '<!-- %s captured %s on %s -->\n\n' "$TOPIC" "$(date -Is)" "$(. /etc/os-release; echo "$PRETTY_NAME")" >>"$OUT"
    else
      printf '\n<!-- after reboot: %s -->\n\n' "$(date -Is)" >>"$OUT"
    fi
    "$phase"
    _close_block
  )
}

has_phase2() {
  grep -q '^phase2()' "$LAB_DIR/topics/$1"
}

process_queue() {
  local file
  while [ -s "$STATE/queue" ]; do
    file=$(head -1 "$STATE/queue")
    if [ -f "$STATE/pending" ] && [ "$(cat "$STATE/pending")" = "$file" ]; then
      log "$file: phase2 (after reboot)"
      run_phase "$file" phase2
      rm -f "$STATE/pending"
    else
      log "$file: phase1"
      run_phase "$file" phase1
      if has_phase2 "$file"; then
        echo "$file" >"$STATE/pending"
        log "$file: rebooting to check persistence"
        sync
        systemctl reboot
        exit 0
      fi
    fi
    log "$file: cleanup"
    run_phase "$file" cleanup
    sed -i '1d' "$STATE/queue"
  done
  finish
}

finish() {
  remove_resume
  local pass fail
  pass=$(grep -c '^PASS' "$RESULTS/checks.tsv" 2>/dev/null || true)
  fail=$(grep -c '^FAIL' "$RESULTS/checks.tsv" 2>/dev/null || true)
  {
    echo "# RHCSA lab capture summary"
    echo
    echo "- Machine: $(. /etc/os-release; echo "$PRETTY_NAME"), kernel $(uname -r)"
    echo "- Finished: $(date -Is)"
    echo "- Checks: ${pass:-0} passed, ${fail:-0} failed"
    echo
    echo "## Failed checks"
    echo
    grep '^FAIL' "$RESULTS/checks.tsv" 2>/dev/null | sed 's/^/- /' || true
    echo
    echo "## Commands that exited non-zero"
    echo
    echo "Some are expected (the notes show errors on purpose); review each."
    echo
    awk -F'\t' '$2!=0 {printf "- %s: exit %s: `%s`\n", $1, $2, $3}' "$RESULTS/commands.tsv" 2>/dev/null
  } >"$RESULTS/SUMMARY.md"
  tar -C "$LAB_DIR" -czf "$LAB_DIR/results.tar.gz" results
  echo done >"$STATE/status"
  log "finished: ${pass:-0} checks passed, ${fail:-0} failed; see $RESULTS/SUMMARY.md and $LAB_DIR/results.tar.gz"
}

# ---------- main ----------

case "${1:-}" in
  --status)
    echo "status: $(cat "$STATE/status" 2>/dev/null || echo 'not started')"
    echo "remaining topics: $(wc -l <"$STATE/queue" 2>/dev/null || echo 0)"
    [ -f "$STATE/pending" ] && echo "waiting on reboot check for: $(cat "$STATE/pending")"
    echo "checks so far: $(grep -c '^PASS' "$RESULTS/checks.tsv" 2>/dev/null || echo 0) passed, $(grep -c '^FAIL' "$RESULTS/checks.tsv" 2>/dev/null || echo 0) failed"
    tail -5 "$RESULTS/run.log" 2>/dev/null
    exit 0 ;;
  --preflight)
    preflight; echo "preflight OK"; cat "$STATE/env"; exit 0 ;;
  --resume)
    echo running >"$STATE/status"
    process_queue
    exit 0 ;;
esac

preflight
prepare
rm -f "$STATE/pending" "$RESULTS/SUMMARY.md"
topic_files "$@" >"$STATE/queue"
[ -s "$STATE/queue" ] || die "no matching topics"
# A rerun replaces only the topics it runs; earlier results for other topics stay.
while read -r f; do
  t="${f%.sh}"
  rm -f "$RESULTS/$t.md"
  for tsv in checks commands; do
    [ -f "$RESULTS/$tsv.tsv" ] && sed -i "/\t$t\t/d; /^$t\t/d" "$RESULTS/$tsv.tsv"
  done
done <"$STATE/queue"
log "running $(wc -l <"$STATE/queue") topics"
echo running >"$STATE/status"
install_resume
process_queue
