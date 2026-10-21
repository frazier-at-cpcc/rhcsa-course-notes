# 5.1 List, create, and delete partitions on GPT disks.

phase1() {
  local p1 p2; p1=$(part "$DISK1" 1); p2=$(part "$DISK1" 2)
  section "Listing disks and partitions"
  run "lsblk"
  run "lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS $DISK1"
  run "sudo parted $DISK1 print"
  expect 'unrecognised disk label|unrecognized disk label'
  run "sudo fdisk -l $DISK1"

  section "Creating a GPT label and partitions with parted"
  run "sudo parted $DISK1 mklabel gpt"
  run "sudo parted $DISK1 mkpart data xfs 1MiB 1025MiB"
  run "sudo parted $DISK1 mkpart logs ext4 1025MiB 1537MiB"
  run "sudo parted $DISK1 print"
  expect 'Partition Table: gpt'
  run "sudo udevadm settle; lsblk $DISK1"
  expect "$(basename "$p2")"
  run "sudo parted -s $DISK1 unit MiB print free"

  section "Partition types and flags"
  run "sudo parted $DISK1 set 2 lvm on"
  run "sudo parted $DISK1 print | tail -4"
  run "sudo fdisk -l $DISK1 | tail -3"
  run "sudo blkid -p -s PART_ENTRY_NAME -s PART_ENTRY_TYPE $p1 $p2"

  section "Deleting a partition"
  run "sudo parted $DISK1 rm 2"
  run "sudo udevadm settle; lsblk $DISK1"
  run "sudo parted $DISK1 rm 1"
  run "sudo parted $DISK1 print | tail -3"

  section "fdisk, interactively, as a script"
  note "fdisk is menu driven; the same keystrokes a student types are fed on stdin here."
  run "printf 'g\nn\n1\n\n+512M\nw\n' | sudo fdisk $DISK1 | tail -6"
  run "sudo udevadm settle; lsblk $DISK1"
  expect "$(basename "$p1")"
  run "sudo partprobe $DISK1; echo \$?"
}

cleanup() { wipe "$DISK1"; }
