# RHCSA Lab Capture: Build Plan

This kit runs every command the RHCSA notes need from a full RHEL 10 system
(storage, LVM, systemd, the journal, NetworkManager, firewalld, SELinux, the
boot loader) on a real machine, and records the exact output. The author
writes the notes from that output, so every terminal block in the PDF comes
from a real run.

The run is unattended. It reboots the machine about ten times to prove that
changes persist, and resumes itself after each boot. You start it, wait, and
send back one archive.

## For an AI agent running this

Paste this to the agent on the machine that will host the VM:

> Build a disposable RHEL 10 VM to the spec in lab/README.md of
> https://github.com/frazier-at-cpcc/rhcsa-course-notes (branch
> build/1.0-notes). In the VM, clone the repo, run
> `sudo lab/run.sh --preflight`, fix anything it reports, then run
> `sudo lab/run.sh`. The VM reboots itself several times; reconnect after
> each reboot and check `sudo lab/run.sh --status` until it says `done`.
> Copy `lab/results.tar.gz` out of the VM and report back with: the
> archive, the full text of `lab/results/SUMMARY.md`, the first 20 lines of
> `lab/results/environment.txt`, and a short note on anything you had to
> change or work around. Do not edit the result files.

## 1. The VM

Use a VM you can throw away; the run repartitions disks and changes system
settings.

| Item | Requirement |
|---|---|
| OS | RHEL 10.x, registered (preferred: the software-sources topic then shows the CDN). AlmaLinux 10 or Rocky Linux 10 also work. Minimal or Server install, no GUI. |
| CPU, memory | 2 vCPUs, 4 GiB RAM |
| System disk | 20 GiB or more |
| Spare disks | **Two extra blank disks of 5 GiB each** (virtio, so they appear as /dev/vdb and /dev/vdc). No partitions, no file systems. |
| NICs | **Two.** The first gets the normal network with DHCP and internet access. The second is attached to an isolated network (or any network) and left **unconfigured**: no NetworkManager connection, no address. |
| SELinux | Enforcing (the default) |
| Network access | The distribution's package repositories, dl.flathub.org, and outbound NTP (UDP 123) to time.cloudflare.com |
| Accounts | A user with sudo, or root. The kit creates its own `student` user (password `redhat`, passwordless sudo) and runs every captured command as that user. |
| Host name | Anything; the kit sets it to servera.lab.example.com. |

Example with libvirt (adjust the ISO or cloud image path and OS variant):

```sh
virsh net-define /dev/stdin <<'EOF'
<network><name>rhcsa-iso</name><bridge name='virbr-rhcsa'/></network>
EOF
virsh net-start rhcsa-iso
virt-install --name rhcsa-lab --memory 4096 --vcpus 2 \
  --os-variant rhel10.0 --cdrom /var/lib/libvirt/images/rhel-10.1-x86_64-dvd.iso \
  --disk size=20 --disk size=5 --disk size=5 \
  --network network=default --network network=rhcsa-iso \
  --graphics none --console pty,target_type=serial
```

On Proxmox: create the VM with a 20 GiB scsi0 or virtio0 disk plus two 5 GiB
virtio disks, net0 on your normal bridge, and net1 on a bridge with no
DHCP. If the spare disks appear under other names (for example /dev/sdb
and /dev/sdc), set `LAB_DISKS="/dev/sdb /dev/sdc"` when you run the kit.

## 2. Run it

Inside the VM:

```sh
sudo dnf -y install git
git clone -b build/1.0-notes https://github.com/frazier-at-cpcc/rhcsa-course-notes
cd rhcsa-course-notes
sudo lab/run.sh --preflight      # checks OS, SELinux, spare disks, spare NIC, repos
sudo lab/run.sh                  # starts the run; the VM will reboot
```

Preflight picks the spare disks and NIC automatically. To choose them
yourself: `sudo LAB_DISKS="/dev/vdb /dev/vdc" LAB_NIC=enp7s0 lab/run.sh`.
Disks and a NIC you name get the same checks: two different blank whole
disks other than the system disk, and an Ethernet device that is not the
main NIC and has no active connection.

After each reboot, a systemd timer resumes the run about a minute after boot.
Reconnect and watch progress:

```sh
sudo lab/run.sh --status
sudo tail -f ~/rhcsa-course-notes/lab/results/run.log
```

Expect 45 to 90 minutes in total; most of it is reboots, the Flathub
download, and the scheduling topic, which waits for its timers to fire.

To run or rerun only some topics: `sudo lab/run.sh 5.2 10.5` (by topic
number). Each topic cleans up after itself, so topics can run in any order.

## 3. What to send back

When `--status` reports `done`:

1. `lab/results.tar.gz` (everything below, in one file).
2. The text of `lab/results/SUMMARY.md`: machine, check counts, failed
   checks, and every command that exited non-zero. Some non-zero exits are
   deliberate (the notes show error messages on purpose); report them as
   they are.
3. Any change you made to the plan, and why (a different disk name, a
   missing repository, a topic you had to skip).

Do not edit the result files; the notes are written from them as captured.

| File | Contents |
|---|---|
| `results/<topic>.md` | The captured session for each topic: sections, `$ command` lines, and their output |
| `results/SUMMARY.md` | Check counts, failed checks, non-zero exits |
| `results/checks.tsv` | Every PASS/FAIL check |
| `results/commands.tsv` | Every command with its exit status |
| `results/phases.tsv` | Any topic phase or cleanup that exited non-zero |
| `results/environment.txt` | OS release, kernel, package versions, disks, NICs |
| `results/setup.log` | Output of the hidden setup steps |
| `results/run.log` | Timeline of the run, including reboots |

## 4. What the run covers

| Topic | Captures | Reboots |
|---|---|---|
| 1.4 | who/w/loginctl, SSH between accounts, su and sudo -i | |
| 2.2 | Flatpak remotes, install, run, user vs system, uninstall | |
| 4.1 | targets, shutdown scheduling, GRUB entry arguments | yes |
| 4.2 | finding CPU and memory hogs, nice/renice, kill/pkill, tuned profiles | |
| 4.3 | /var/log files, journalctl filters, persistent journal | yes |
| 4.4 | service start/stop/status, scp, sftp, rsync | |
| 5.1 | GPT labels, parted and fdisk partitions, deleting | |
| 5.2 | PVs, VGs, LVs, extents, removal | |
| 5.3 | fstab by UUID and label, findmnt --verify, swap partition and LV | yes |
| 6.1 | VFAT, ext4, XFS: create, mount, busy unmount, labels | |
| 6.2 | NFS mounts, fstab _netdev, autofs indirect and wildcard maps | yes |
| 6.3 | lvextend -r for XFS and ext4, vgextend, shrink limits | |
| 6.4 | namei, group membership, ACL masks, immutable files | |
| 7.1 | at, cron, systemd timers | |
| 7.2 | enable/disable/mask, default target | yes |
| 7.3 | timedatectl, chronyd sources | |
| 7.4 | CDN status, updates, local RPM, local and remote repositories | |
| 7.5 | grubby, kernel arguments, /etc/default/grub, grub2-mkconfig | yes |
| 8.1 | nmcli static IPv4 and IPv6 on the spare NIC, keyfiles | yes |
| 8.2 | hostnamectl, /etc/hosts, nsswitch, DNS settings | |
| 8.3 | firewall-cmd services and ports, runtime vs permanent | |
| 10.1 | zones, sources, rich rules, port forwarding, runtime-to-permanent | yes |
| 10.4 | SELinux modes, file and process contexts, permissive at boot | yes |
| 10.5 | restorecon, semanage fcontext, port labels, Booleans | yes |

Topics that need no full system (shell tools, scripting, users and groups,
permissions) are captured in containers by the tests in `tests/`.

## 5. If something goes wrong

- `--status` shows what is left. `results/run.log` shows the last step;
  `results/setup.log` shows hidden setup output.
- If the run stopped (for example the timer did not fire after a reboot),
  start it again where it left off with `sudo lab/run.sh --resume`.
- Never interrupt it during a disk topic (5.x, 6.x) unless you are going to
  rebuild the VM; cleanup runs at the end of each topic.
- The SSH service and the main NIC's connection are never changed, so your
  session survives every topic except the deliberate reboots.
