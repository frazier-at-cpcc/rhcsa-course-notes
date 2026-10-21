# 5.2 Create and remove physical volumes; assign physical volumes to volume
# groups; create and delete logical volumes.

phase1() {
  local a1 b1; a1=$(part "$DISK1" 1); b1=$(part "$DISK2" 1)
  setup "parted -s $DISK2 mklabel gpt mkpart lvm2 1MiB 100% set 1 lvm on && udevadm settle"

  section "Physical volumes"
  run "sudo parted -s $DISK1 mklabel gpt mkpart lvm1 1MiB 100% set 1 lvm on"
  run "sudo udevadm settle; lsblk $DISK1 $DISK2"
  run "sudo pvcreate $a1 $b1"
  expect 'successfully created'
  run "sudo pvs"
  run "sudo pvdisplay $a1"

  section "Volume groups"
  run "sudo vgcreate -s 8M vg_data $a1"
  expect 'successfully created'
  run "sudo vgs"
  run "sudo vgdisplay vg_data | grep -E 'VG Name|PE Size|Total PE|Free  PE'"
  run "sudo vgextend vg_data $b1"
  run "sudo vgs vg_data"
  run "sudo pvs"

  section "Logical volumes"
  run "sudo lvcreate -n lv_web -L 500M vg_data"
  expect 'created'
  run "sudo lvcreate -n lv_db -l 40 vg_data"
  run "sudo lvcreate -n lv_rest -l 50%FREE vg_data"
  run "sudo lvs"
  run "sudo lvdisplay /dev/vg_data/lv_db | grep -E 'LV Path|LV Size|Current LE'"
  run "ls -l /dev/vg_data/ /dev/mapper/ | grep vg_data"
  run "sudo lvcreate -n lv_big -L 20G vg_data"
  expect 'Insufficient free space'

  section "Removing logical volumes, volume groups, and physical volumes"
  run "sudo lvremove -y vg_data/lv_rest"
  run "sudo pvmove $b1"
  run "sudo vgreduce vg_data $b1"
  run "sudo pvremove $b1"
  run "sudo lvremove -y vg_data"
  run "sudo vgremove vg_data"
  run "sudo pvremove $a1"
  run "sudo pvs; sudo vgs"
}

cleanup() {
  vgremove -ff -y vg_data >/dev/null 2>&1
  pvremove -ff -y "$(part "$DISK1" 1)" "$(part "$DISK2" 1)" >/dev/null 2>&1
  wipe "$DISK1"; wipe "$DISK2"
}
