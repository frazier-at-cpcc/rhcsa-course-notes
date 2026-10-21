# 5.3 Configure systems to mount file systems at boot by UUID or label; add
# new partitions, logical volumes, and swap to a system non-destructively.

phase1() {
  local a1 a2 a3 b1; a1=$(part "$DISK1" 1); a2=$(part "$DISK1" 2); a3=$(part "$DISK1" 3); b1=$(part "$DISK2" 1)
  setup "cp -a /etc/fstab $STATE/fstab.orig"

  section "Adding partitions without touching existing ones"
  run "sudo parted -s $DISK1 mklabel gpt"
  run "sudo parted -s $DISK1 mkpart archive xfs 1MiB 513MiB"
  run "sudo parted -s $DISK1 mkpart scratch ext4 513MiB 769MiB"
  run "sudo parted -s $DISK1 mkpart swap1 linux-swap 769MiB 1281MiB"
  run "sudo udevadm settle; lsblk $DISK1"

  section "File systems with labels, and their UUIDs"
  run "sudo mkfs.xfs -q -L archive $a1"
  run "sudo mkfs.ext4 -q -L scratch $a2"
  run "sudo blkid $a1 $a2"
  expect 'LABEL="archive"'
  run "lsblk -f $DISK1"

  section "Mounting at boot with /etc/fstab"
  run "sudo mkdir -p /archive /scratch"
  run "echo \"UUID=\$(sudo blkid -s UUID -o value $a1)  /archive  xfs  defaults  0 0\" | sudo tee -a /etc/fstab"
  run "echo 'LABEL=scratch  /scratch  ext4  defaults  0 2' | sudo tee -a /etc/fstab"
  run "sudo systemctl daemon-reload"
  run "sudo findmnt --verify"
  run "sudo mount -a"
  run "findmnt /archive; findmnt /scratch"
  expect '/scratch'
  run "df -hT /archive /scratch"

  section "A mistake in /etc/fstab"
  run "echo 'UUID=0000-bad  /broken  xfs  defaults  0 0' | sudo tee -a /etc/fstab"
  run "sudo findmnt --verify"
  expect 'not found|0000-bad'
  run "sudo sed -i '/0000-bad/d' /etc/fstab; sudo systemctl daemon-reload; sudo findmnt --verify"

  section "Adding swap: a partition and a logical volume"
  run "swapon --show; free -h | grep -i swap"
  run "sudo mkswap -L swap1 $a3"
  run "sudo swapon $a3"
  run "echo \"UUID=\$(sudo blkid -s UUID -o value $a3)  none  swap  defaults  0 0\" | sudo tee -a /etc/fstab"
  run "sudo parted -s $DISK2 mklabel gpt mkpart lvm 1MiB 100% set 1 lvm on; sudo udevadm settle"
  run "sudo vgcreate vg_swap $b1"
  run "sudo lvcreate -n lv_swap -L 256M vg_swap"
  run "sudo mkswap /dev/vg_swap/lv_swap"
  run "echo '/dev/vg_swap/lv_swap  none  swap  defaults  0 0' | sudo tee -a /etc/fstab"
  run "sudo systemctl daemon-reload; sudo swapon -a"
  run "swapon --show"
  expect 'lv_swap|dm-'
  run "free -h"
  run "tail -5 /etc/fstab"
}

phase2() {
  section "After a reboot"
  run "findmnt /archive; findmnt /scratch"
  expect '/archive'
  run "swapon --show"
  expect "$(basename "$(part "$DISK1" 3)")"
  run "lsblk -f $DISK1 $DISK2"
}

cleanup() {
  swapoff -a 2>/dev/null; umount /archive /scratch 2>/dev/null
  cp -a "$STATE/fstab.orig" /etc/fstab; systemctl daemon-reload; swapon -a 2>/dev/null
  vgremove -ff -y vg_swap >/dev/null 2>&1
  rmdir /archive /scratch 2>/dev/null
  wipe "$DISK1"; wipe "$DISK2"
}
