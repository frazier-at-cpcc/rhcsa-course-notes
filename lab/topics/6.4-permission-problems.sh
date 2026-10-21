# 6.4 Diagnose and correct file permission problems.

phase1() {
  setup "groupadd -f devops; id alice >/dev/null 2>&1 || useradd alice; echo alice:redhat | chpasswd; mkdir -p /srv/devops/releases && echo v1 > /srv/devops/releases/notes.txt && chown -R root:devops /srv/devops && chmod 750 /srv/devops && chmod 640 /srv/devops/releases/notes.txt"

  section "Reading the error"
  run "cat /srv/devops/releases/notes.txt"
  expect 'Permission denied'
  run "ls -ld /srv /srv/devops /srv/devops/releases"
  run "namei -l /srv/devops/releases/notes.txt"
  expect 'drwxr-x---'
  run "id"

  section "Group membership takes effect at the next login"
  run "sudo usermod -aG devops $LAB_USER"
  run "id"
  run "id $LAB_USER"
  expect 'devops'
  run "sg devops -c 'cat /srv/devops/releases/notes.txt'"
  expect 'v1'

  section "Execute on directories, read on files"
  run "sudo chmod 640 /srv/devops; sudo -u alice ls /srv/devops 2>&1; sudo chmod 750 /srv/devops"
  run "sudo chmod 710 /srv/devops; sg devops -c 'ls /srv/devops; cat /srv/devops/releases/notes.txt'"
  run "sudo chmod 750 /srv/devops"
  run "sg devops -c 'echo v2 >> /srv/devops/releases/notes.txt'"
  expect 'Permission denied'
  run "sudo chmod 660 /srv/devops/releases/notes.txt; sg devops -c 'echo v2 >> /srv/devops/releases/notes.txt'; cat /srv/devops/releases/notes.txt 2>&1 || sg devops -c 'cat /srv/devops/releases/notes.txt'"

  section "ACLs and the mask"
  run "sudo setfacl -m u:alice:rx /srv/devops /srv/devops/releases; sudo setfacl -m u:alice:r /srv/devops/releases/notes.txt"
  run "getfacl /srv/devops/releases/notes.txt 2>/dev/null || sudo getfacl /srv/devops/releases/notes.txt"
  run "ls -l /srv/devops/releases/"
  expect '\+'
  run "sudo chmod 600 /srv/devops/releases/notes.txt; sudo getfacl /srv/devops/releases/notes.txt"
  expect 'effective'
  run "sudo -u alice cat /srv/devops/releases/notes.txt"

  section "Attributes and SELinux can also say no"
  run "sudo chmod 666 /srv/devops/releases/notes.txt; sudo chattr +i /srv/devops/releases/notes.txt; sudo lsattr /srv/devops/releases/notes.txt"
  run "echo v3 | sudo tee -a /srv/devops/releases/notes.txt"
  expect 'Operation not permitted'
  run "sudo chattr -i /srv/devops/releases/notes.txt"
  run "ls -Z /srv/devops/releases/notes.txt"
}

cleanup() {
  chattr -i /srv/devops/releases/notes.txt 2>/dev/null
  rm -rf /srv/devops; gpasswd -d "$LAB_USER" devops >/dev/null 2>&1; groupdel devops 2>/dev/null; userdel -r alice 2>/dev/null
}
