# 6.3 Extend existing logical volumes.

phase1() {
  local a1 b1; a1=$(part "$DISK1" 1); b1=$(part "$DISK2" 1)
  setup "parted -s $DISK1 mklabel gpt mkpart lvm 1MiB 1025MiB set 1 lvm on && parted -s $DISK2 mklabel gpt mkpart lvm 1MiB 1025MiB set 1 lvm on && udevadm settle"
  setup "vgcreate -q vg_app $a1 && lvcreate -q -y -n lv_web -L 300M vg_app && lvcreate -q -y -n lv_logs -L 200M vg_app && mkfs.xfs -q /dev/vg_app/lv_web && mkfs.ext4 -q /dev/vg_app/lv_logs && mkdir -p /srv/web /srv/logs && mount /dev/vg_app/lv_web /srv/web && mount /dev/vg_app/lv_logs /srv/logs"

  section "Where the space is"
  run "df -h /srv/web /srv/logs"
  run "sudo lvs vg_app; sudo vgs vg_app"

  section "Growing an XFS logical volume and its file system together"
  run "sudo lvextend -r -L +200M /dev/vg_app/lv_web"
  expect 'resized|data blocks changed'
  run "df -h /srv/web"

  section "Growing an ext4 logical volume in two steps"
  run "sudo lvextend -L 350M /dev/vg_app/lv_logs"
  run "df -h /srv/logs"
  run "sudo resize2fs /dev/vg_app/lv_logs"
  expect 'is now'
  run "df -h /srv/logs"

  section "When the volume group is full"
  run "sudo vgs vg_app"
  run "sudo lvextend -r -L +500M /dev/vg_app/lv_web"
  expect 'Insufficient free space'
  run "sudo pvcreate $b1"
  run "sudo vgextend vg_app $b1"
  run "sudo vgs vg_app"
  run "sudo lvextend -r -l +100%FREE /dev/vg_app/lv_web"
  run "df -h /srv/web; sudo lvs vg_app"

  section "Shrinking"
  run "sudo lvreduce -r -L 300M /dev/vg_app/lv_web"
  expect '[Ss]hrink|not supported|XFS|xfs'
  run "sudo xfs_growfs /srv/web | tail -1"
}

cleanup() {
  umount /srv/web /srv/logs 2>/dev/null
  vgremove -ff -y vg_app >/dev/null 2>&1
  pvremove -ff -y "$(part "$DISK1" 1)" "$(part "$DISK2" 1)" >/dev/null 2>&1
  rmdir /srv/web /srv/logs 2>/dev/null
  wipe "$DISK1"; wipe "$DISK2"
}
