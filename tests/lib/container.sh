# Shared helper for tests that only need a RHEL 10 userland: shell tools,
# text processing, archives, permissions, users and groups, scripting, dnf.
# Much faster than the VM in tests/lib/vm.sh; use the VM for anything that
# needs systemd, SELinux, disks, firewalld, or NetworkManager.
#
#   ct_up <name> [packages...]   start an AlmaLinux 10 container, install packages
#   ct <command...>              run a command as root (bash -c)
#   ct_as <user> <command...>    run a command as another user (login shell)
#   ct_down <name>               remove it (call from your EXIT trap)
#
# The container's hostname is servera.lab.example.com, matching the VM.
#
# Needs: docker

CT_IMAGE="${CT_IMAGE:-mirror.gcr.io/library/almalinux:10.2}"

ct_up() {
  CT_NAME="$1"; shift
  local args=(-d --name "$CT_NAME" --hostname servera.lab.example.com)
  # Authoring sandbox only: trust its HTTPS-inspecting proxy so dnf works.
  if [ -f /root/.ccr/ca-bundle.crt ]; then
    args+=(-v /root/.ccr/ca-bundle.crt:/etc/pki/ca-trust/source/anchors/sandbox-proxy.crt:ro)
  fi
  docker rm -f "$CT_NAME" >/dev/null 2>&1 || true
  docker run "${args[@]}" "$CT_IMAGE" sleep infinity >/dev/null
  if [ -f /root/.ccr/ca-bundle.crt ]; then ct update-ca-trust; fi
  if [ $# -gt 0 ]; then ct "dnf -y -q install $* >/dev/null"; fi
}

ct() { docker exec -i "$CT_NAME" bash -c "$*"; }
ct_as() { local u="$1"; shift; docker exec -i -u "$u" -w "/home/$u" "$CT_NAME" bash -lc "$*"; }
ct_down() { docker rm -f "${1:-$CT_NAME}" >/dev/null 2>&1 || true; }
