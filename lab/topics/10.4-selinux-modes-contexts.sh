# 10.4 Set enforcing and permissive modes for SELinux; list and identify
# SELinux file and process context.

phase1() {
  setup "cp -a /etc/selinux/config $STATE/selinux-config.orig; systemctl start httpd"

  section "Modes"
  run "getenforce"
  expect 'Enforcing'
  run "sestatus"
  run "grep -E '^SELINUX(TYPE)?=' /etc/selinux/config"
  run "sudo setenforce 0; getenforce"
  expect 'Permissive'
  run "sudo setenforce 1; getenforce"
  run "setenforce 0"
  run "cat /sys/fs/selinux/enforce"

  section "File contexts"
  run "ls -Z /etc/passwd /etc/shadow"
  run "ls -dZ /var/www/html /home/$LAB_USER /tmp"
  expect 'httpd_sys_content_t'
  run "stat -c '%n %C' /etc/ssh/sshd_config"
  run "echo hello > notes.txt; ls -Z notes.txt"
  run "sudo cp notes.txt /var/www/html/; sudo mv /home/$LAB_USER/notes.txt /var/www/html/moved.txt; ls -Z /var/www/html/"
  expect 'user_home_t'

  section "Process and user contexts"
  run "ps -eZ | grep -E 'httpd|sshd' | head -4"
  expect 'httpd_t'
  run "ps -Zp \$\$"
  run "id -Z"
  run "sudo semanage login -l | head -6"

  section "Permissive at boot"
  run "sudo sed -i 's/^SELINUX=.*/SELINUX=permissive/' /etc/selinux/config; grep ^SELINUX= /etc/selinux/config"
}

phase2() {
  section "After a reboot"
  run "getenforce"
  expect 'Permissive'
  run "sudo sed -i 's/^SELINUX=.*/SELINUX=enforcing/' /etc/selinux/config; sudo setenforce 1; getenforce"
  expect 'Enforcing'
  run "grep ^SELINUX= /etc/selinux/config"
  run "cat /proc/cmdline | tr ' ' '\n' | grep -E 'selinux|enforcing' || echo 'no selinux arguments on the kernel command line'"
}

cleanup() {
  cp -a "$STATE/selinux-config.orig" /etc/selinux/config; setenforce 1
  rm -f /var/www/html/notes.txt /var/www/html/moved.txt; systemctl stop httpd
}
