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
# Shells get umask 022 and dnf installs documentation, as on a real system.
# Under `set -o pipefail`, avoid `ct ... | grep -q`: grep can exit before ct
# finishes writing and the pipe fails with status 141. Capture the output in
# a variable first, then test it.
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
  # The container image installs packages without docs; a real system keeps
  # man pages, info files, and /usr/share/doc, so turn that off.
  ct "sed -i '/^tsflags=nodocs/d' /etc/dnf/dnf.conf"
  if [ $# -gt 0 ]; then ct "dnf -y -q install $* >/dev/null"; fi
}

# docker exec starts shells with umask 0000; a RHEL login gets 0022.
ct() { docker exec -i "$CT_NAME" bash -c "umask 022; $*"; }
ct_as() { local u="$1"; shift; docker exec -i -u "$u" -w "/home/$u" "$CT_NAME" bash -lc "umask 022; $*"; }
ct_down() { docker rm -f "${1:-$CT_NAME}" >/dev/null 2>&1 || true; }
