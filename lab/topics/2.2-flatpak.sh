# 2.2 Configure access to Flatpak repositories; install and remove Flatpak
# software packages. Downloads a runtime (a few hundred MB) from Flathub.

phase1() {
  section "Remotes"
  run "rpm -q flatpak"
  run "flatpak --version"
  run "flatpak remotes --show-details"
  run "sudo flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo"
  run "flatpak remotes"
  expect 'flathub'
  run "flatpak remote-ls flathub --app --columns=application | grep -E '^org\.gnome\.(Calculator|TextEditor)$'"
  run "flatpak search --columns=application,remotes calculator | head -4"

  section "Installing and running"
  run "sudo flatpak install -y --noninteractive flathub org.gnome.Calculator 2>&1 | tail -4"
  run "flatpak list --app"
  expect 'org.gnome.Calculator'
  run "flatpak list --runtime --columns=application,branch | head -4"
  run "flatpak info org.gnome.Calculator | head -10"
  run "flatpak run --command=sh org.gnome.Calculator -c 'echo running inside the sandbox; cat /etc/os-release | head -1'"
  run "flatpak install --user -y --noninteractive flathub org.gnome.Calculator 2>&1 | tail -2"
  run "flatpak remotes --user; flatpak list --app --user"

  section "Updating and removing"
  run "sudo flatpak update -y --noninteractive 2>&1 | tail -2"
  run "sudo flatpak uninstall -y --noninteractive org.gnome.Calculator 2>&1 | tail -2"
  run "sudo flatpak uninstall -y --noninteractive --unused 2>&1 | tail -2"
  run "flatpak list"
  run "sudo flatpak remote-delete flathub; flatpak remotes"
}

cleanup() {
  flatpak uninstall -y --noninteractive --all >/dev/null 2>&1
  runuser -l "$LAB_USER" -c 'flatpak uninstall --user -y --noninteractive --all; flatpak remote-delete --user flathub' >/dev/null 2>&1
  flatpak remote-delete flathub >/dev/null 2>&1
}
