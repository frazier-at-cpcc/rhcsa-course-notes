#!/usr/bin/env bash
# Verifies every command shown in 2.2 Flatpak Repositories and Apps.
# Runs in the RHEL 10 VM because `flatpak run` needs bubblewrap namespaces,
# which a container does not allow. Downloads from Flathub (dl.flathub.org):
# the kibi editor (about 2 MB) and the org.freedesktop.Platform runtime
# (about 260 MB; --no-related skips the GL and locale extensions), plus a
# tiny GTK theme for the per-user installation. One reboot proves that the
# remotes and installed apps persist.
# Not run: installing from Red Hat's registry needs a subscribed RHEL system;
# the test records the error an unsubscribed system gets instead.
# Needs: the helpers in lib/vm.sh
set -euo pipefail
cd "$(dirname "$0")"
source lib/vm.sh
trap 'vm_down rh23-22' EXIT
vm_up rh23-22 23131

say() { printf '\n== %s\n' "$*"; }
run() { printf '$ %s\n' "$1"; OUT=$(vm "export LANG=C.UTF-8; $1" 2>&1) || true; printf '%s\n' "$OUT"; }
# A failed check is counted, not fatal, so one slow VM run reports them all.
FAILS=0
fail() { echo "FAILED: $1" >&2; FAILS=$((FAILS + 1)); }
has() { grep -qE -- "$1" <<<"$OUT" || fail "missing $1"; }
hasx() { grep -qxF -- "$1" <<<"$OUT" || fail "missing line $1"; }
APP=com.github.ilai_deutel.kibi
THEME=org.gtk.Gtk3theme.Adwaita-dark
FLATHUB=https://dl.flathub.org/repo/flathub.flatpakrepo
RHEL=https://flatpaks.redhat.io/rhel.flatpakrepo

say "flatpak is installed, with no remotes yet"
run 'rpm -q flatpak; flatpak --version'; has '^flatpak-1\.16'; hasx 'Flatpak 1.16.0'
run 'flatpak remotes | wc -l'; hasx '0'

say "configure access to Flatpak repositories"
run "sudo flatpak remote-add --if-not-exists flathub $FLATHUB"
run "sudo flatpak remote-add --if-not-exists rhel $RHEL"
run 'flatpak remotes'; has '^flathub\s+system$'; has '^rhel\s+system,oci'
run 'flatpak remotes --columns=name,url'
has '^flathub\s+https://dl.flathub.org/repo/$'; has '^rhel\s+oci\+https://flatpaks.redhat.io/rhel/$'
run 'grep -A2 "remote \"flathub\"" /var/lib/flatpak/repo/config'; hasx 'url=https://dl.flathub.org/repo/'
run 'flatpak remote-ls rhel --app --columns=name,application'
has 'org.mozilla.firefox'; has 'org.mozilla.Thunderbird'
run 'flatpak remote-ls flathub --app | wc -l'; has '^[0-9]{4}$'
run "flatpak search --columns=application,version,remotes kibi"; has "^$APP\s"
run "flatpak remote-info flathub $APP | grep -E 'Runtime|Download'"
has 'Runtime: org.freedesktop.Platform/x86_64/'

say "install from Flathub (system installation)"
t0=$(date +%s)
run "sudo flatpak install -y --noninteractive --no-related flathub $APP"
has "Installing app/$APP/x86_64/stable"; has 'Installing runtime/org.freedesktop.Platform/x86_64/'
echo "(install took $(( $(date +%s) - t0 )) s)"
run 'flatpak list --columns=application,branch,installation'
has "^$APP\s+stable\s+system$"; has '^org.freedesktop.Platform\s+[0-9.]+\s+system$'
run 'flatpak list --app --columns=application,origin'; has "^$APP\s+flathub$"
run "flatpak info $APP | grep -E 'Origin|Installation|Runtime'"
has 'Origin: flathub'; has 'Installation: system'
run "flatpak run $APP --version"; has '^kibi 0\.3\.2'

say "Red Hat's registry needs a subscription"
run 'sudo flatpak install -y --noninteractive rhel org.mozilla.firefox; echo "status $?"'
has '^status [1-9]'

say "per-user installation"
run "flatpak remote-add --user --if-not-exists flathub $FLATHUB"
run "flatpak install --user -y --noninteractive flathub $THEME"
run 'flatpak list --columns=application,installation'
has "^$THEME\s+user$"; has "^$APP\s+system$"
run 'flatpak remotes'; has '^flathub\s+user$'; has '^flathub\s+system$'
run 'ls ~/.local/share/flatpak'; hasx 'repo'
run 'sudo -u root flatpak list --app --columns=application'
! grep -q Gtk3theme <<<"$OUT" || fail "user app visible to root"

say "disable a remote"
run 'sudo flatpak remote-modify --disable rhel'
run 'flatpak remotes --show-disabled'; has '^rhel\s+system,disabled'

say "reboot: remotes and installs persist"
vm_reboot
run 'flatpak remotes --show-disabled'
has '^flathub\s+system$'; has '^flathub\s+user$'; has '^rhel\s+system,disabled'
run 'flatpak list --columns=application,installation'
has "^$APP\s+system$"; has "^$THEME\s+user$"
run "flatpak run $APP --version"; has '^kibi 0\.3\.2'

say "uninstall and clean up"
run "flatpak uninstall --user -y --noninteractive $THEME"
run "sudo flatpak uninstall -y --noninteractive $APP"
run 'flatpak list --columns=application'; has '^org.freedesktop.Platform$'
run 'sudo flatpak uninstall -y --noninteractive --unused'
run 'flatpak list | wc -l'; hasx '0'
run 'sudo flatpak remote-delete rhel'
run 'flatpak remotes'; ! grep -q rhel <<<"$OUT" || fail "rhel remote still there"

[ "$FAILS" = 0 ] || { echo "$FAILS checks failed" >&2; exit 1; }
echo
echo "ALL 2.2 FLATPAK CHECKS PASSED"
