# 7.1 Schedule tasks using at, cron, and systemd timer units.

phase1() {
  section "One-time jobs with at"
  run "systemctl is-active atd"
  run "echo 'date >> /tmp/at-demo.txt' | at now + 1 minute"
  expect 'job [0-9]+ at'
  run "echo 'tar czf /tmp/etc-backup.tgz /etc 2>/dev/null' | at 23:30"
  run "atq"
  run "at -c \$(atq | sort -n | tail -1 | cut -f1) | tail -3"
  run "atrm \$(atq | sort -n | tail -1 | cut -f1); atq"
  run "sleep 75; cat /tmp/at-demo.txt"
  expect '20[0-9][0-9]'

  section "Recurring jobs with cron"
  run "systemctl is-active crond"
  run "printf '*/5 * * * * df -h / >> /tmp/df.log\n30 2 * * 1-5 /usr/local/bin/backup.sh\n' > mycron; crontab mycron"
  run "crontab -l"
  expect 'df -h'
  run "sudo crontab -u $LAB_USER -l | head -1"
  run "sudo ls -l /var/spool/cron/"
  run "echo '0 1 * * 0 root /usr/bin/dnf -y -q makecache' | sudo tee /etc/cron.d/weekly-cache"
  run "ls /etc/cron.daily /etc/cron.hourly"
  run "grep -v '^#' /etc/anacrontab | grep -v '^$'"
  run "crontab -r; crontab -l"
  expect 'no crontab'

  section "systemd timer units"
  run "printf '[Unit]\nDescription=Record disk usage\n\n[Service]\nType=oneshot\nExecStart=/usr/bin/sh -c \"df -h / >> /var/log/disk-usage.log\"\n' | sudo tee /etc/systemd/system/disk-usage.service"
  run "printf '[Unit]\nDescription=Record disk usage every minute\n\n[Timer]\nOnCalendar=*-*-* *:*:00\nPersistent=true\n\n[Install]\nWantedBy=timers.target\n' | sudo tee /etc/systemd/system/disk-usage.timer"
  run "sudo systemctl daemon-reload"
  run "sudo systemctl enable --now disk-usage.timer"
  expect 'Created symlink'
  run "systemctl list-timers disk-usage.timer --no-pager"
  run "sleep 65; sudo tail -2 /var/log/disk-usage.log"
  expect 'Filesystem|/'
  run "journalctl -u disk-usage.service -n 3 --no-pager"
  run "systemd-analyze calendar 'Mon..Fri 02:30' 'daily' '*:0/15' --iterations=2"
  run "systemctl list-timers --all --no-pager | head -8"
}

cleanup() {
  systemctl disable --now disk-usage.timer >/dev/null 2>&1
  rm -f /etc/systemd/system/disk-usage.service /etc/systemd/system/disk-usage.timer /var/log/disk-usage.log /etc/cron.d/weekly-cache /tmp/at-demo.txt "/home/$LAB_USER/mycron"
  systemctl daemon-reload
  for j in $(atq | cut -f1); do atrm "$j"; done
  crontab -u "$LAB_USER" -r 2>/dev/null
}
