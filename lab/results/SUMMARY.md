# RHCSA lab capture summary

- Machine: Rocky Linux 10.2 (Red Quartz), kernel 6.12.0-211.67.1.el10_2.x86_64
- Finished: 2026-10-21T19:18:05+00:00
- Checks: 112 passed, 5 failed

## Failed checks

- FAIL	1.4-logins-and-users	expect Permission denied
- FAIL	4.3-logs-and-journal	expect RHCSA lab
- FAIL	4.4-services-and-transfer	expect sent
- FAIL	5.2-lvm	expect Insufficient free space
- FAIL	6.3-extend-lvs	expect is now

## Commands that exited non-zero

Some are expected (the notes show errors on purpose); review each.

- 1.4-logins-and-users: exit 1: `tty`
- 1.4-logins-and-users: exit 255: `ssh operator1@servera 'id; pwd'`
- 1.4-logins-and-users: exit 255: `ssh -o BatchMode=yes nobody@servera true`
- 4.1-boot-and-targets: exit 2: `ls /.autorelabel 2>&1`
- 4.2-processes-and-tuning: exit 1: `renice -n 5 -p $(pgrep sha256sum)`
- 4.2-processes-and-tuning: exit 1: `sudo kill $(pgrep sha1sum)`
- 4.2-processes-and-tuning: exit 143: `pkill -f bytearray; sleep 1; pgrep -af bytearray || echo gone`
- 4.2-processes-and-tuning: exit 1: `kill -9 999999`
- 4.2-processes-and-tuning: exit 1: `tuned-adm verify`
- 4.2-processes-and-tuning: exit 1: `sudo tuned-adm off; tuned-adm active`
- 4.3-logs-and-journal: exit 2: `grep -E '^#?Storage' /etc/systemd/journald.conf`
- 4.4-services-and-transfer: exit 3: `systemctl is-active httpd`
- 4.4-services-and-transfer: exit 255: `scp -r reports bob@servera:/tmp/`
- 4.4-services-and-transfer: exit 255: `scp bob@servera:/home/bob/q3.txt ./q3-copy.txt && cat q3-copy.txt`
- 4.4-services-and-transfer: exit 255: `printf 'cd /tmp/reports\nls -l\nget backup.img fetched.img\nbye\n' > batch.sftp; sftp -b batch.sftp bob@servera`
- 4.4-services-and-transfer: exit 2: `ls -l fetched.img`
- 4.4-services-and-transfer: exit 12: `rsync -av reports/ bob@servera:/home/bob/reports/`
- 4.4-services-and-transfer: exit 12: `echo 'appended' >> reports/q3.txt; rsync -av reports/ bob@servera:/home/bob/reports/`
- 4.4-services-and-transfer: exit 12: `rsync -av --delete --dry-run reports/ bob@servera:/home/bob/reports/`
- 6.2-nfs-and-autofs: exit 1: `findmnt -t nfs4,nfs | grep shares`
- 6.2-nfs-and-autofs: exit 1: `mount | grep -E 'autofs.*shares'`
- 7.1-scheduling: exit 1: `crontab -r; crontab -l`
- 7.2-services-and-targets: exit 3: `systemctl is-enabled httpd; systemctl is-active httpd`
- 7.2-services-and-targets: exit 1: `sudo systemctl start nfs-server`
- 7.2-services-and-targets: exit 1: `systemctl is-enabled nfs-server`
- 7.5-bootloader: exit 2: `ls /boot/loader/entries/`
- 7.5-bootloader: exit 1: `sudo cat /boot/loader/entries/$(ls /boot/loader/entries/ | grep -v rescue | tail -1)`
- 7.5-bootloader: exit 2: `ls -l /boot/grub2/grub.cfg /boot/efi/EFI/*/grub.cfg 2>&1`
- 8.1-ip-configuration: exit 2: `ls /etc/NetworkManager/system-connections/ /etc/sysconfig/network-scripts/ 2>&1`
- 10.4-selinux-modes-contexts: exit 2: `setenforce 0`
- 5.2-lvm: exit 5: `sudo lvcreate -n lv_big -L 20G vg_data`
- 5.2-lvm: exit 5: `sudo pvmove /dev/vdc1`
- 5.3-persistent-mounts-and-swap: exit 1: `sudo findmnt --verify`
- 6.1-local-file-systems: exit 1: `sudo mkfs.xfs /dev/vdb3`
- 6.1-local-file-systems: exit 32: `sudo umount /mnt/data`
- 6.3-extend-lvs: exit 5: `sudo lvextend -L 450M /dev/vg_app/lv_logs`
- 6.3-extend-lvs: exit 5: `sudo lvextend -r -L +500M /dev/vg_app/lv_web`
- 6.3-extend-lvs: exit 5: `sudo lvreduce -r -L 300M /dev/vg_app/lv_web`
- 10.5-selinux-troubleshooting: exit 1: `sudo systemctl restart httpd`
- 6.4-permission-problems: exit 1: `cat /srv/devops/releases/notes.txt`
- 6.4-permission-problems: exit 2: `ls -ld /srv /srv/devops /srv/devops/releases`
- 6.4-permission-problems: exit 1: `namei -l /srv/devops/releases/notes.txt`
- 6.4-permission-problems: exit 1: `sg devops -c 'echo v2 >> /srv/devops/releases/notes.txt'`
- 6.4-permission-problems: exit 1: `sudo -u alice cat /srv/devops/releases/notes.txt`
- 6.4-permission-problems: exit 1: `echo v3 | sudo tee -a /srv/devops/releases/notes.txt`
