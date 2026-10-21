# 6.1 Create, mount, unmount, and use VFAT, ext4, and XFS file systems.

phase1() {
  local a1 a2 a3; a1=$(part "$DISK1" 1); a2=$(part "$DISK1" 2); a3=$(part "$DISK1" 3)
  setup "parted -s $DISK1 mklabel gpt mkpart usb fat32 1MiB 257MiB mkpart home ext4 257MiB 769MiB mkpart data xfs 769MiB 1281MiB && udevadm settle"

  section "Making the three file systems"
  run "lsblk $DISK1"
  run "sudo mkfs.vfat -n USBKEY $a1"
  run "sudo mkfs.ext4 -L homes $a2"
  expect 'Writing superblocks'
  run "sudo mkfs.xfs -L data $a3"
  expect 'meta-data='
  run "lsblk -f $DISK1"
  run "sudo mkfs.xfs $a3"
  expect 'existing|appears to contain'

  section "Mounting, using, and unmounting"
  run "sudo mkdir -p /mnt/usb /mnt/homes /mnt/data"
  run "sudo mount $a1 /mnt/usb; sudo mount $a2 /mnt/homes; sudo mount $a3 /mnt/data"
  run "df -hT /mnt/usb /mnt/homes /mnt/data"
  expect 'vfat'
  run "findmnt -t vfat,ext4,xfs"
  run "sudo cp /etc/hosts /mnt/usb/; ls -l /mnt/usb"
  run "sudo chown $LAB_USER /mnt/usb/hosts; ls -l /mnt/usb/hosts"
  run "sudo umount /mnt/usb; sudo mount -o uid=$LAB_USER,umask=022 $a1 /mnt/usb; ls -l /mnt/usb"
  run "ls /mnt/homes"
  run_in /mnt/data "sudo umount /mnt/data"
  expect 'busy'
  run "sudo fuser -vm /mnt/data 2>&1 | head -3"
  run "sudo umount /mnt/data; findmnt /mnt/data; echo \$?"

  section "Labels and tuning after the fact"
  run "sudo xfs_admin -L archive $a3; sudo blkid -s LABEL $a3"
  run "sudo e2label $a2 homes2; sudo blkid -s LABEL $a2"
  run "sudo tune2fs -l $a2 | grep -E 'volume name|Block count|Filesystem features'"
  run "sudo xfs_info $a3 2>&1 | head -2 || sudo mount $a3 /mnt/data"
  run "sudo fatlabel $a1"
}

cleanup() {
  umount /mnt/usb /mnt/homes /mnt/data 2>/dev/null
  rmdir /mnt/usb /mnt/homes /mnt/data 2>/dev/null
  wipe "$DISK1"
}
