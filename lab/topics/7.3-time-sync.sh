# 7.3 Configure time service clients.

phase1() {
  setup "cp -a /etc/chrony.conf $STATE/chrony.conf.orig; timedatectl show -p Timezone --value > $STATE/timezone"

  section "Time zone and status"
  run "timedatectl"
  expect 'NTP service'
  run "timedatectl list-timezones | grep -E 'America/(New_York|Chicago)'"
  run "sudo timedatectl set-timezone America/New_York"
  run "timedatectl | grep 'Time zone'"
  expect 'America/New_York'
  run "ls -l /etc/localtime"

  section "chronyd as an NTP client"
  run "systemctl is-active chronyd; systemctl is-enabled chronyd"
  run "grep -E '^(pool|server)' /etc/chrony.conf"
  run "chronyc sources"
  run "sudo sed -i 's/^pool /#pool /' /etc/chrony.conf"
  run "echo 'server time.cloudflare.com iburst' | sudo tee -a /etc/chrony.conf"
  run "grep -E '^(pool|server|#pool)' /etc/chrony.conf"
  run "sudo systemctl restart chronyd"
  run "sleep 20; chronyc sources -v | tail -4"
  expect 'cloudflare|\^'
  run "chronyc tracking | head -6"
  run "timedatectl show -p NTPSynchronized"
  run "sudo timedatectl set-ntp false; timedatectl | grep NTP"
  run "sudo timedatectl set-ntp true; timedatectl | grep NTP"
}

cleanup() {
  cp -a "$STATE/chrony.conf.orig" /etc/chrony.conf; systemctl restart chronyd
  timedatectl set-timezone "$(cat "$STATE/timezone")"
}
