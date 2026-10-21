# 1.4 Access remote systems using SSH; log in and switch users in
# multi-user targets. Interactive password prompts are not captured; key
# logins and sudo are.

phase1() {
  setup "useradd -m operator1 2>/dev/null; echo operator1:redhat | chpasswd"
  setup "runuser -l $LAB_USER -c 'rm -rf ~/.ssh; ssh-keygen -q -t ed25519 -N \"\" -f ~/.ssh/id_ed25519; ssh-keyscan -t ed25519 servera 2>/dev/null >> ~/.ssh/known_hosts'; install -d -o operator1 -g operator1 -m 700 /home/operator1/.ssh; cp /home/$LAB_USER/.ssh/id_ed25519.pub /home/operator1/.ssh/authorized_keys; chown operator1: /home/operator1/.ssh/authorized_keys; chmod 600 /home/operator1/.ssh/authorized_keys"

  section "Who is logged in, and on what"
  run "systemctl get-default"
  run "who"
  run "w -h | head -3"
  run "loginctl list-sessions --no-pager"
  run "tty"

  section "SSH to another account"
  run "ssh -o StrictHostKeyChecking=accept-new operator1@servera.lab.example.com 'hostname; whoami'"
  expect 'operator1'
  run "tail -1 ~/.ssh/known_hosts | cut -c1-60"
  run "ssh operator1@servera 'id; pwd'"
  run "ssh -o BatchMode=yes nobody@servera true"
  expect 'Permission denied'

  section "Switching users"
  run "sudo su - operator1 -c 'whoami; pwd; echo \$HOME'"
  run "sudo su operator1 -c 'whoami; pwd; echo \$HOME'"
  run "sudo -i -u operator1 whoami"
  run "sudo -i whoami"
  run "sudo grep -E '^(root|$LAB_USER|operator1):' /etc/passwd"
}

cleanup() {
  userdel -r operator1 2>/dev/null
  rm -rf "/home/$LAB_USER/.ssh"
}
