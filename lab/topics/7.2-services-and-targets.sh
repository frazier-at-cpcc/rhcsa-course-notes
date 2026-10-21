# 7.2 Start and stop services and configure services to start automatically
# at boot; configure systems to boot into a specific target automatically.

phase1() {
  setup "systemctl get-default > $STATE/default-target"

  section "Enabling a service for boot"
  run "systemctl is-enabled httpd; systemctl is-active httpd"
  run "sudo systemctl enable --now httpd"
  expect 'Created symlink'
  run "systemctl is-enabled httpd; systemctl is-active httpd"
  run "systemctl list-unit-files --state=enabled --type=service --no-pager | head -8"
  run "sudo systemctl disable httpd"
  run "sudo systemctl enable httpd"

  section "Masking"
  run "sudo systemctl mask --now cups 2>&1; sudo systemctl mask nfs-server"
  run "sudo systemctl start nfs-server"
  expect 'masked'
  run "systemctl is-enabled nfs-server"
  run "sudo systemctl unmask nfs-server"

  section "Unit files and dependencies"
  run "systemctl cat httpd --no-pager | head -12"
  run "systemctl list-dependencies multi-user.target --no-pager | head -10"
  run "systemctl show -p WantedBy -p After httpd"

  section "The default target"
  run "systemctl get-default"
  run "sudo systemctl set-default multi-user.target"
  run "ls -l /etc/systemd/system/default.target"
  expect 'multi-user.target'
}

phase2() {
  section "After a reboot"
  run "systemctl get-default"
  expect 'multi-user.target'
  run "systemctl is-active httpd"
  expect '^active'
  run "systemctl status httpd --no-pager | head -4"
}

cleanup() {
  systemctl disable --now httpd >/dev/null 2>&1
  systemctl unmask nfs-server cups >/dev/null 2>&1
  systemctl set-default "$(cat "$STATE/default-target")" >/dev/null 2>&1
}
