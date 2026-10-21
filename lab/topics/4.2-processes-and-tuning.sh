# 4.2 Identify CPU/memory intensive processes and kill processes; adjust
# process scheduling; manage tuning profiles.

phase1() {
  setup "runuser -l $LAB_USER -c 'nohup sha256sum /dev/zero >/dev/null 2>&1 & nohup sha1sum /dev/zero >/dev/null 2>&1 &'"
  setup "runuser -l $LAB_USER -c \"nohup python3 -c 'import time; a = bytearray(400*1024*1024); time.sleep(600)' >/dev/null 2>&1 &\""
  setup "sleep 8"

  section "Finding the busy processes"
  run "ps aux --sort=-%cpu | head -5"
  expect 'sha(256|1)sum'
  run "ps -eo pid,user,%cpu,%mem,rss,comm --sort=-%mem | head -5"
  expect 'python3'
  run "top -b -n 1 -o %CPU | head -12"
  run "pgrep -l sum"
  expect 'sha256sum'
  run "uptime"
  run "free -h"

  section "Nice and renice"
  run "ps -o pid,ni,pri,%cpu,comm -C sha256sum,sha1sum"
  run "renice -n 10 -p \$(pgrep sha256sum)"
  expect 'new priority 10'
  run "renice -n 5 -p \$(pgrep sha256sum)"
  run "sudo renice -n -5 -p \$(pgrep sha1sum)"
  run "ps -o pid,ni,pri,%cpu,comm -C sha256sum,sha1sum"
  run "nice -n 15 sleep 300 & ps -o pid,ni,comm -C sleep"
  expect '15'
  run "nice -n -5 sleep 1"

  section "Killing processes"
  run "kill -l | head -3"
  run "kill \$(pgrep sha1sum)"
  run "sudo kill \$(pgrep sha1sum)"
  run "pgrep -l sum"
  run "kill -SIGTERM \$(pgrep sha256sum); sleep 1; pgrep -l sum || echo 'no sum processes left'"
  run "pkill -f bytearray; sleep 1; pgrep -af bytearray || echo gone"
  run "pkill sleep; killall -v sleep 2>&1 | head -2"
  run "kill -9 999999"

  section "Tuning profiles"
  run "systemctl is-active tuned"
  run "tuned-adm list | head -20"
  run "tuned-adm active"
  run "tuned-adm recommend"
  run "sudo tuned-adm profile throughput-performance"
  run "tuned-adm active"
  expect 'throughput-performance'
  run "tuned-adm verify"
  run "sudo tuned-adm profile \$(tuned-adm recommend)"
  run "tuned-adm active"
  run "sudo tuned-adm off; tuned-adm active"
  run "sudo tuned-adm auto_profile; tuned-adm profile_mode"
}

cleanup() {
  pkill -u "$LAB_USER" -f 'sha256sum|sha1sum|bytearray|sleep 300' 2>/dev/null
  tuned-adm profile "$(tuned-adm recommend)" >/dev/null 2>&1
}
