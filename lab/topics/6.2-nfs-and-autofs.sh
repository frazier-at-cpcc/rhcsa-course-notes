# 6.2 Mount and unmount network file systems using NFS; configure autofs.
# The NFS server is the same machine (servera exports to itself); the exam
# provides a server, so its setup is scaffolding and is not shown.

phase1() {
  setup "mkdir -p /exports/projects /exports/guests/alice /exports/guests/bob && echo 'quarterly plan' > /exports/projects/plan.txt && echo 'alice notes' > /exports/guests/alice/notes.txt && chmod -R a+rX /exports"
  setup "printf '/exports/projects  *(rw,sync,no_root_squash)\n/exports/guests  *(rw,sync)\n' > /etc/exports.d/lab.exports && systemctl enable --now nfs-server && exportfs -ra"
  setup "firewall-cmd -q --add-service=nfs --add-service=mountd --add-service=rpc-bind"
  setup "cp -a /etc/fstab $STATE/fstab.orig"

  section "Finding what a server exports"
  run "showmount -e servera"
  expect '/exports/projects'
  run "rpm -q nfs-utils"

  section "Mounting by hand"
  run "sudo mkdir -p /mnt/projects"
  run "sudo mount -t nfs servera:/exports/projects /mnt/projects"
  run "findmnt -t nfs4,nfs /mnt/projects"
  expect 'nfs'
  run "nfsstat -m | head -3"
  run "ls -l /mnt/projects; cat /mnt/projects/plan.txt"
  run "sudo umount /mnt/projects"

  section "Mounting at boot with /etc/fstab"
  run "echo 'servera:/exports/projects  /mnt/projects  nfs  defaults,_netdev  0 0' | sudo tee -a /etc/fstab"
  run "sudo systemctl daemon-reload; sudo mount -a; findmnt /mnt/projects"
  expect 'servera:/exports/projects'

  section "autofs: an indirect map"
  run "rpm -q autofs"
  run "echo '/shares  /etc/auto.shares' | sudo tee /etc/auto.master.d/shares.autofs"
  run "echo 'projects  -rw,sync  servera:/exports/projects' | sudo tee /etc/auto.shares"
  run "sudo systemctl enable --now autofs"
  run "ls /shares"
  run "ls /shares/projects"
  expect 'plan.txt'
  run "findmnt -t nfs4,nfs | grep shares"
  run "mount | grep -E 'autofs.*shares'"

  section "autofs: a wildcard map for home directories"
  run "echo '/home/guests  /etc/auto.guests' | sudo tee /etc/auto.master.d/guests.autofs"
  run "echo '*  -rw,sync  servera:/exports/guests/&' | sudo tee /etc/auto.guests"
  run "sudo systemctl reload autofs"
  run "cat /home/guests/alice/notes.txt"
  expect 'alice notes'
  run "ls /home/guests"
  run "findmnt /home/guests/alice"
  run "grep -E '^(timeout|browse_mode)' /etc/autofs.conf"
}

phase2() {
  section "After a reboot"
  run "findmnt /mnt/projects"
  expect 'nfs'
  run "systemctl is-enabled autofs; systemctl is-active autofs"
  run "ls /shares/projects; cat /home/guests/alice/notes.txt"
  expect 'alice notes'
}

cleanup() {
  systemctl disable --now autofs >/dev/null 2>&1
  rm -f /etc/auto.master.d/shares.autofs /etc/auto.master.d/guests.autofs /etc/auto.shares /etc/auto.guests
  umount -l /mnt/projects 2>/dev/null
  cp -a "$STATE/fstab.orig" /etc/fstab; systemctl daemon-reload
  rm -f /etc/exports.d/lab.exports; exportfs -ra; systemctl disable --now nfs-server >/dev/null 2>&1
  firewall-cmd -q --reload
  rm -rf /exports; rmdir /mnt/projects 2>/dev/null
}
