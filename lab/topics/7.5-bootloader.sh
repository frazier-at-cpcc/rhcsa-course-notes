# 7.5 Modify the system bootloader.

phase1() {
  setup "cp -a /etc/default/grub $STATE/default-grub.orig"

  section "What GRUB will boot"
  run "sudo grubby --default-kernel"
  run "sudo grubby --default-index"
  run "sudo grubby --info=ALL | grep -E '^(index|kernel|args|title)'"
  run "ls /boot/loader/entries/"
  run "sudo cat /boot/loader/entries/\$(ls /boot/loader/entries/ | grep -v rescue | tail -1)"
  run "cat /proc/cmdline"

  section "Changing kernel arguments with grubby"
  run "sudo grubby --update-kernel=ALL --args='audit=1 audit_backlog_limit=8192'"
  run "sudo grubby --info=DEFAULT | grep args"
  expect 'audit_backlog_limit=8192'

  section "Menu settings in /etc/default/grub"
  run "cat /etc/default/grub"
  run "sudo sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=10/' /etc/default/grub; grep TIMEOUT /etc/default/grub"
  run "sudo grub2-mkconfig -o /boot/grub2/grub.cfg 2>&1 | tail -3"
  run "sudo grep -m2 'timeout' /boot/grub2/grub.cfg"
  run "sudo grub2-editenv list"
  run "ls -l /boot/grub2/grub.cfg /boot/efi/EFI/*/grub.cfg 2>&1"
}

phase2() {
  section "After a reboot"
  run "cat /proc/cmdline"
  expect 'audit_backlog_limit=8192'
  run "sudo grubby --update-kernel=ALL --remove-args='audit=1 audit_backlog_limit=8192'"
  run "sudo grubby --info=DEFAULT | grep args"
}

cleanup() {
  grubby --update-kernel=ALL --remove-args='audit=1 audit_backlog_limit=8192' >/dev/null 2>&1
  cp -a "$STATE/default-grub.orig" /etc/default/grub
  grub2-mkconfig -o /boot/grub2/grub.cfg >/dev/null 2>&1
}
