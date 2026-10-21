# 4.4 Start, stop, and check the status of network services; securely transfer
# files between systems.

phase1() {
  setup "runuser -l $LAB_USER -c 'rm -rf ~/.ssh; ssh-keygen -q -t ed25519 -N \"\" -f ~/.ssh/id_ed25519; cat ~/.ssh/id_ed25519.pub >> ~/.ssh/authorized_keys; chmod 600 ~/.ssh/authorized_keys; ssh-keyscan -t ed25519 servera.lab.example.com servera localhost 2>/dev/null >> ~/.ssh/known_hosts'"
  setup "useradd bob 2>/dev/null; install -d -o bob -g bob -m 700 /home/bob/.ssh; cp /home/$LAB_USER/.ssh/id_ed25519.pub /home/bob/.ssh/authorized_keys; chown bob: /home/bob/.ssh/authorized_keys; chmod 600 /home/bob/.ssh/authorized_keys"

  section "Network services with systemctl"
  run "systemctl status sshd --no-pager | head -6"
  expect 'active \(running\)'
  run "systemctl is-active httpd"
  run "sudo systemctl start httpd"
  run "systemctl is-active httpd"
  expect '^active'
  run "sudo ss -tlnp | grep -E ':(22|80) '"
  run "curl -sI http://localhost/ | head -1"
  run "sudo systemctl stop httpd"
  run "systemctl status httpd --no-pager | head -3"
  run "sudo systemctl restart sshd; systemctl is-active sshd"
  run "sudo systemctl reload sshd; echo \$?"

  section "Copying files with scp"
  run "mkdir -p reports; echo 'q3 disk usage' > reports/q3.txt; dd if=/dev/urandom of=reports/backup.img bs=1M count=5 status=none; ls -l reports"
  run "scp reports/q3.txt bob@servera.lab.example.com:/home/bob/"
  run "ssh bob@servera.lab.example.com 'ls -l /home/bob'"
  expect 'q3.txt'
  run "scp -r reports bob@servera:/tmp/"
  run "scp bob@servera:/home/bob/q3.txt ./q3-copy.txt && cat q3-copy.txt"

  section "sftp"
  run "printf 'cd /tmp/reports\nls -l\nget backup.img fetched.img\nbye\n' > batch.sftp; sftp -b batch.sftp bob@servera"
  run "ls -l fetched.img"

  section "rsync over SSH"
  run "rsync -av reports/ bob@servera:/home/bob/reports/"
  expect 'sent'
  run "echo 'appended' >> reports/q3.txt; rsync -av reports/ bob@servera:/home/bob/reports/"
  run "rsync -av --delete --dry-run reports/ bob@servera:/home/bob/reports/"
}

cleanup() {
  systemctl stop httpd
  userdel -r bob 2>/dev/null
  rm -rf "/home/$LAB_USER/reports" "/home/$LAB_USER"/q3-copy.txt "/home/$LAB_USER"/fetched.img "/home/$LAB_USER"/batch.sftp /tmp/reports
}
