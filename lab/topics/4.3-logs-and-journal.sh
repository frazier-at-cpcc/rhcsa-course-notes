# 4.3 Locate and interpret system log files and journals; preserve system
# journals.

phase1() {
  section "Log files under /var/log"
  run "sudo ls /var/log"
  run "sudo tail -3 /var/log/messages"
  run "sudo grep -c 'session opened' /var/log/secure"
  run "logger -p user.warning 'RHCSA lab: disk space check'"
  run "sudo grep 'RHCSA lab' /var/log/messages | tail -1"
  expect 'RHCSA lab'
  run "grep -v '^#' /etc/rsyslog.conf | grep -E 'messages|secure|cron'"

  section "Reading the journal"
  run "journalctl -n 3 --no-pager"
  run "sudo journalctl -u sshd -n 3 --no-pager"
  run "sudo journalctl -p err -b --no-pager | tail -3"
  run "sudo journalctl --since '10 min ago' -t $LAB_USER --no-pager || sudo journalctl --since '10 min ago' --no-pager | grep 'RHCSA lab'"
  run "sudo journalctl _COMM=sshd -o verbose -n 1 --no-pager | head -12"
  run "sudo journalctl -b -o short-iso -n 2 --no-pager"
  run "journalctl --disk-usage"

  section "Is the journal persistent?"
  run "grep -E '^#?Storage' /etc/systemd/journald.conf"
  run "ls -ld /var/log/journal /run/log/journal 2>&1"
  run "journalctl --list-boots --no-pager"

  section "Making it persistent"
  run "sudo mkdir -p /etc/systemd/journald.conf.d"
  run "printf '[Journal]\nStorage=persistent\n' | sudo tee /etc/systemd/journald.conf.d/persistent.conf"
  run "sudo systemctl restart systemd-journald"
  run "ls -ld /var/log/journal"
  expect 'journal'
  run "sudo ls /var/log/journal/"
  run "sudo journalctl --flush; journalctl --disk-usage"
}

phase2() {
  section "After a reboot"
  run "journalctl --list-boots --no-pager"
  expect '^ *-1 '
  run "sudo journalctl -b -1 -n 3 --no-pager"
  run "sudo journalctl -b -1 --no-pager | grep -c 'RHCSA lab'"
}

cleanup() {
  rm -f /etc/systemd/journald.conf.d/persistent.conf
  systemctl restart systemd-journald
}
