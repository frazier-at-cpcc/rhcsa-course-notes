# 4.1 Boot, reboot, and shut down normally; boot into different targets
# manually; interrupt the boot process (the GRUB/rd.break steps themselves
# need a console, so they are not captured; the commands around them are).

phase1() {
  section "Targets"
  run "systemctl get-default"
  expect 'target'
  run "systemctl list-units --type=target --state=active --no-pager"
  expect 'multi-user.target'
  run "systemctl list-unit-files --type=target --no-pager | grep -E 'rescue|emergency|multi-user|graphical'"
  run "systemctl cat rescue.target --no-pager | grep -E '^(Requires|After|AllowIsolate)'"
  expect 'AllowIsolate=yes'
  run "who -r"
  expect 'run-level'

  section "Shutting down and rebooting"
  run "sudo shutdown -r +15 'Maintenance reboot'"
  run "sudo shutdown -c"
  run "systemctl is-system-running"
  run "last -x reboot shutdown | head -4"

  section "Choosing a target for one boot"
  note "Kernel arguments for one boot, as typed at the GRUB menu with e: systemd.unit=rescue.target, systemd.unit=emergency.target, rd.break. Shown here: the default entry they are added to."
  run "sudo grubby --info=DEFAULT | grep -E '^(kernel|args)'"
  expect 'args='
  run "ls -lZ /etc/shadow"
  expect 'shadow_t'
  run "ls /.autorelabel 2>&1"
  run "cat /proc/cmdline"
  run "sudo journalctl -b -o short-precise --no-pager | grep -m1 -E 'Reached target.*Multi-User|Reached target multi-user'"
}

phase2() {
  section "After a normal reboot"
  run "uptime"
  run "last -x reboot | head -3"
  expect 'reboot'
  run "journalctl --list-boots --no-pager | tail -3"
  run "systemctl is-system-running"
}
