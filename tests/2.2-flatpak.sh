#!/usr/bin/env bash
# Verifies the 2.2 Flatpak commands that the lab capture does not cover:
# a per-user remote and installation, where the remote list is stored, the
# empty search on a fresh remote, and Red Hat's Flatpak remote.
# The system-wide install, run, update, and uninstall in the notes come from
# lab/results/2.2-flatpak.md (a real Rocky Linux 10.2 VM), not from here.
# Downloads from dl.flathub.org (the 1.5 kB Adwaita-dark GTK theme) and
# flatpaks.redhat.io (the app list only).
# Left out: installing from the rhel remote. It needs a Red Hat registry
# login (podman login flatpaks.registry.redhat.io) and a D-Bus session that
# a container lacks, so the notes give those steps as a numbered list.
# Needs: docker
set -euo pipefail
cd "$(dirname "$0")"
source lib/container.sh
CT=rh232-22
trap 'ct_down $CT' EXIT
ct_up $CT flatpak sudo
ct 'useradd student && echo "student ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/student && chmod 440 /etc/sudoers.d/student'

say() { printf '\n== %s\n' "$*"; }
# run CMD: run as student, print a transcript, keep the output in $OUT
run() { printf '$ %s\n' "$1"; OUT=$(ct_as student "$1" 2>&1) || true; printf '%s\n' "$OUT"; }
has() { grep -qE -- "$1" <<<"$OUT" || { echo "MISSING: $1" >&2; exit 1; }; }
hasx() { grep -qxF -- "$1" <<<"$OUT" || { echo "MISSING LINE: $1" >&2; exit 1; }; }
FLATHUB=https://dl.flathub.org/repo/flathub.flatpakrepo
RHEL=https://flatpaks.redhat.io/rhel.flatpakrepo
THEME=org.gtk.Gtk3theme.Adwaita-dark

say "same flatpak build as the lab VM"
run 'rpm -q flatpak'; has '^flatpak-1\.16\.0-'

say "system remote, stored as a plain file"
run "sudo flatpak remote-add --if-not-exists flathub $FLATHUB"
run 'flatpak remotes'; has '^flathub\s+system$'
run "grep -A3 'remote \"flathub\"' /var/lib/flatpak/repo/config"
hasx '[remote "flathub"]'; hasx 'url=https://dl.flathub.org/repo/'
hasx 'xa.title=Flathub'; hasx 'gpg-verify=true'

say "a fresh remote has no appstream data yet, so search finds nothing"
run 'flatpak search calculator'; hasx 'No matches found'
run 'sudo flatpak update --appstream'; hasx 'Updating appstream data for remote flathub'
run 'flatpak search --columns=application,remotes calculator | head -2'
[ "$(grep -c 'flathub$' <<<"$OUT")" = 2 ] || { echo "search still empty" >&2; exit 1; }

say "user installation needs its own remote"
run "flatpak remote-add --user --if-not-exists flathub $FLATHUB"
run 'flatpak remotes'; has '^flathub\s+system$'; has '^flathub\s+user$'
run "flatpak install --user -y --noninteractive flathub $THEME 2>&1 | tail -1"
hasx "Installing runtime/$THEME/x86_64/3.22"
run 'flatpak list --columns=application,branch,installation'
has "^$THEME\s+3\.22\s+user$"
run 'ls ~/.local/share/flatpak'; hasx 'repo'; hasx 'runtime'
run 'sudo flatpak list --system | wc -l'; hasx '0'
run "flatpak uninstall --user -y --noninteractive $THEME 2>&1 | tail -1"
hasx "Uninstalling runtime/$THEME/x86_64/3.22"
run 'flatpak remote-delete --user flathub; flatpak remotes'
hasx "$(printf 'flathub\tsystem')"; ! grep -q user <<<"$OUT"

say "Red Hat's Flatpak remote"
run "sudo flatpak remote-add --if-not-exists rhel $RHEL"
run 'flatpak remotes'; has '^rhel\s+system,oci,no-gpg-verify$'
run 'sudo flatpak remote-ls rhel --app --columns=application'
hasx 'org.mozilla.firefox'; hasx 'org.mozilla.Thunderbird'

say "disable, then delete a remote"
run 'sudo flatpak remote-modify --disable rhel'
run 'flatpak remotes --show-disabled'; has '^rhel\s+system,disabled,oci,no-gpg-verify$'
run 'flatpak remotes'; ! grep -q rhel <<<"$OUT"
run 'sudo flatpak remote-delete rhel; flatpak remotes'
! grep -q rhel <<<"$OUT"

echo
echo "ALL 2.2 FLATPAK CHECKS PASSED"
