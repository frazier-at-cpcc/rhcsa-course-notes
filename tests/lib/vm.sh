# Shared helper for tests that need a whole RHEL 10 system: systemd, SELinux
# in enforcing mode, LVM on spare disks, firewalld, NetworkManager, a boot
# loader. Source it, then:
#
#   vm_up <name> <ssh-port>      boot a fresh VM (about 10 s from a snapshot)
#   vm <command...>              run a command as the student user
#   vm_root <command...>         run a command as root (sudo)
#   vm_put <local> <remote>      copy a file into the VM
#   vm_reboot                    reboot and wait for SSH again
#   vm_down <name>               stop it (call from your EXIT trap)
#
# The VM is AlmaLinux 10, a rebuild of RHEL 10 that matches it command for
# command. Disks: vda (system), vdb and vdc (2 GiB each, blank). NICs: eth0
# (user-mode NAT, the default route) and eth1 (unconfigured, for addressing
# exercises). Users: student (wheel, passwordless sudo) and root, both with
# the password "redhat". The hostname is servera.lab.example.com.
#
# The first run builds a base image with the exam's packages and saves a
# snapshot of the booted system; later runs restore that snapshot with every
# write going to a throwaway overlay, so each test starts from the same clean
# machine and tests can run in parallel. KVM is used when /dev/kvm exists;
# without it QEMU emulates the CPU (TCG), which works but is slower.
#
# Needs: qemu-system-x86_64, qemu-img, ssh, curl, flock, python3

VM_CACHE="${VM_CACHE:-$HOME/.cache/rhcsa-vm}"
VM_IMAGE="AlmaLinux-10-GenericCloud-10.2-20261012.0.x86_64.qcow2"
VM_IMAGE_URL="https://repo.almalinux.org/almalinux/10/cloud/x86_64/images/$VM_IMAGE"
VM_IMAGE_SHA256="cbee4726fc0f5a60694bb4f289003cc221e715dfbacebcce76b54daf386d8eca"
VM_SLOTS="${VM_SLOTS:-2}"          # VMs allowed to run at once on this host
VM_MEM="${VM_MEM:-1536}"
VM_PACKAGES="lvm2 xfsprogs dosfstools e2fsprogs nfs-utils autofs firewalld
  policycoreutils-python-utils setroubleshoot-server httpd chrony tuned at
  cronie flatpak tar gzip bzip2 vim-enhanced nano man-db man-pages
  bash-completion rsync openssh-clients psmisc lsof sos"

_vm_accel() {
  if [ -w /dev/kvm ]; then echo "kvm"; else echo "tcg"; fi
}
_vm_qemu_args() {   # args every boot shares, so a saved snapshot restores
  local accel; accel=$(_vm_accel)
  local cpu="max"; [ "$accel" = kvm ] && cpu="host"
  echo "-machine q35 -accel $accel -cpu $cpu -smp 2 -m $VM_MEM -nographic"
  echo "-drive file=$VM_CACHE/base.qcow2,if=virtio,format=qcow2"
  echo "-drive file=$VM_CACHE/vdb.qcow2,if=virtio,format=qcow2"
  echo "-drive file=$VM_CACHE/vdc.qcow2,if=virtio,format=qcow2"
  echo "-device virtio-net-pci,netdev=n0,mac=52:54:00:00:00:10"
  echo "-device virtio-net-pci,netdev=n1,mac=52:54:00:00:00:11"
}
_vm_ssh_opts() {
  echo "-q -o BatchMode=yes -o StrictHostKeyChecking=no"
  echo "-o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=5"
  echo "-i $VM_CACHE/id_ed25519"
}
_vm_wait_ssh() {   # port timeout
  local s; s=$(date +%s)
  until ssh $(_vm_ssh_opts) -p "$1" student@127.0.0.1 true 2>/dev/null; do
    [ $(( $(date +%s) - s )) -gt "$2" ] && { echo "VM did not answer SSH in $2 s" >&2; return 1; }
    sleep 3
  done
}
_vm_monitor() {   # socket command
  python3 - "$1" "$2" <<'PY'
import socket, sys, time
s = socket.socket(socket.AF_UNIX); s.connect(sys.argv[1]); s.settimeout(600)
def read_prompt():
    buf = b""
    while not buf.endswith(b"(qemu) "):
        chunk = s.recv(4096)
        if not chunk: break
        buf += chunk
    return buf
read_prompt()
s.sendall(sys.argv[2].encode() + b"\n")
print(read_prompt().decode(errors="replace").replace("(qemu) ", "").strip())
PY
}

vm_build_base() {
  mkdir -p "$VM_CACHE"
  local tag; tag="ready-$(_vm_accel)"
  exec 8>"$VM_CACHE/build.lock"; flock 8
  if [ -f "$VM_CACHE/base.qcow2" ] && qemu-img snapshot -l "$VM_CACHE/base.qcow2" 2>/dev/null | grep -q " $tag "; then
    flock -u 8; return 0
  fi
  echo "Building the RHEL 10 test VM (one time, several minutes)..." >&2
  if [ ! -f "$VM_CACHE/$VM_IMAGE" ]; then
    curl -sSfL -o "$VM_CACHE/$VM_IMAGE.part" "$VM_IMAGE_URL"
    echo "$VM_IMAGE_SHA256  $VM_CACHE/$VM_IMAGE.part" | sha256sum -c --quiet
    mv "$VM_CACHE/$VM_IMAGE.part" "$VM_CACHE/$VM_IMAGE"
  fi
  [ -f "$VM_CACHE/id_ed25519" ] || ssh-keygen -q -t ed25519 -N "" -f "$VM_CACHE/id_ed25519"
  rm -f "$VM_CACHE/base.qcow2" "$VM_CACHE/vdb.qcow2" "$VM_CACHE/vdc.qcow2"
  cp "$VM_CACHE/$VM_IMAGE" "$VM_CACHE/base.qcow2"
  qemu-img resize -q "$VM_CACHE/base.qcow2" 20G
  qemu-img create -q -f qcow2 "$VM_CACHE/vdb.qcow2" 2G
  qemu-img create -q -f qcow2 "$VM_CACHE/vdc.qcow2" 2G
  local seed; seed=$(mktemp -d)
  cat > "$seed/user-data" <<EOF
#cloud-config
hostname: servera
fqdn: servera.lab.example.com
ssh_pwauth: true
users:
  - name: student
    groups: wheel
    sudo: "ALL=(ALL) NOPASSWD:ALL"
    lock_passwd: false
    ssh_authorized_keys: ["$(cat "$VM_CACHE/id_ed25519.pub")"]
chpasswd:
  expire: false
  users:
    - {name: student, password: redhat, type: text}
    - {name: root, password: redhat, type: text}
EOF
  printf 'instance-id: servera\nlocal-hostname: servera\n' > "$seed/meta-data"
  : > "$seed/vendor-data"
  # Serve the cloud-init seed over HTTP (10.0.2.2 is the host as the VM sees
  # it) instead of attaching a seed disk, so the saved machine has exactly
  # the devices every later boot has.
  python3 -m http.server 22998 --bind 127.0.0.1 --directory "$seed" >/dev/null 2>&1 &
  local http=$!
  local mon="$VM_CACHE/build.mon"; rm -f "$mon"
  # shellcheck disable=SC2046
  qemu-system-x86_64 $(_vm_qemu_args) -serial file:"$VM_CACHE/build-console.log" \
    -monitor unix:"$mon",server,nowait \
    -smbios "type=1,serial=ds=nocloud;s=http://10.0.2.2:22998/" \
    -netdev user,id=n0,hostfwd=tcp:127.0.0.1:22999-:22 -netdev user,id=n1,restrict=on,net=192.168.99.0/24 &
  local pid=$!
  _vm_wait_ssh 22999 1800
  local S="ssh $(_vm_ssh_opts) -p 22999 student@127.0.0.1"
  # Authoring sandbox only: its HTTPS-inspecting proxy needs its CA trusted
  # before dnf can reach the mirrors. CI runners and lab machines skip this.
  if [ -f /root/.ccr/ca-bundle.crt ]; then
    $S 'sudo tee /etc/pki/ca-trust/source/anchors/sandbox-proxy.crt >/dev/null' < /root/.ccr/ca-bundle.crt
    $S 'sudo update-ca-trust'
  fi
  $S "sudo cloud-init status --wait >/dev/null; sudo dnf -y -q install $VM_PACKAGES"
  # eth1 is left for addressing exercises: no automatic DHCP profile.
  $S 'printf "[main]\nno-auto-default=52:54:00:00:00:11\n" | sudo tee /etc/NetworkManager/conf.d/90-lab.conf >/dev/null
      for c in $(nmcli -t -f UUID,DEVICE con show | awk -F: "\$2==\"eth1\"{print \$1}"); do sudo nmcli con delete "$c" >/dev/null; done
      sudo nmcli device disconnect eth1 >/dev/null 2>&1 || true'
  $S 'sudo systemctl enable --now firewalld atd >/dev/null 2>&1; sudo mandb -q >/dev/null 2>&1;
      sudo hostnamectl hostname servera.lab.example.com; sudo dnf clean all -q; sync'
  kill "$http" 2>/dev/null
  sleep 20   # let the system settle before the snapshot
  _vm_monitor "$mon" "stop" >/dev/null
  local out; out=$(_vm_monitor "$mon" "savevm $tag")
  _vm_monitor "$mon" "quit" >/dev/null 2>&1 || true
  wait "$pid" 2>/dev/null || true
  rm -rf "$seed"
  qemu-img snapshot -l "$VM_CACHE/base.qcow2" | grep -q " $tag " \
    || { echo "snapshot failed: $out" >&2; flock -u 8; return 1; }
  flock -u 8
}

vm_up() {   # name port
  VM_NAME="$1"; VM_PORT="$2"
  vm_build_base
  local tag; tag="ready-$(_vm_accel)"
  # Wait for a free slot so the host is not overloaded.
  local i
  while :; do
    for i in $(seq 1 "$VM_SLOTS"); do
      exec 9>"$VM_CACHE/slot.$i"
      flock -n 9 && break 2
    done
    sleep 5
  done
  VM_RUN=$(mktemp -d)
  # shellcheck disable=SC2046
  qemu-system-x86_64 $(_vm_qemu_args) -snapshot -loadvm "$tag" \
    -serial file:"$VM_RUN/console.log" -monitor unix:"$VM_RUN/mon",server,nowait \
    -netdev user,id=n0,hostfwd=tcp:127.0.0.1:"$VM_PORT"-:22 \
    -netdev user,id=n1,restrict=on,net=192.168.99.0/24 \
    -pidfile "$VM_RUN/pid" -daemonize
  _vm_wait_ssh "$VM_PORT" 600
  # The restored clock is the snapshot's; set it to now.
  vm_root "date -s @$(date +%s) >/dev/null; hwclock -w 2>/dev/null || true"
}

vm() { ssh $(_vm_ssh_opts) -p "$VM_PORT" student@127.0.0.1 "$@"; }
vm_root() { ssh $(_vm_ssh_opts) -p "$VM_PORT" student@127.0.0.1 sudo bash -c "$(printf '%q ' "$*")"; }
vm_put() { scp $(_vm_ssh_opts) -P "$VM_PORT" "$1" student@127.0.0.1:"$2"; }
vm_reboot() {
  vm_root "systemctl reboot" || true
  sleep 10
  _vm_wait_ssh "$VM_PORT" 900
}

vm_down() {
  [ -n "${VM_RUN:-}" ] || return 0
  [ -f "$VM_RUN/pid" ] && kill "$(cat "$VM_RUN/pid")" 2>/dev/null
  sleep 1
  rm -rf "$VM_RUN"
  flock -u 9 2>/dev/null || true
}
