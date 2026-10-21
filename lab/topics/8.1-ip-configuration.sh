# 8.1 Configure IPv4 and IPv6 addresses; configure network services to start
# automatically at boot. Works on the spare NIC only, so the machine's own
# connection (and your SSH session) is never touched. Addresses come from the
# documentation ranges 192.0.2.0/24 and 2001:db8::/32.

phase1() {
  section "Looking at the current configuration"
  run "nmcli device status"
  run "nmcli connection show"
  run "ip -br addr"
  run "ip route"
  run "nmcli -f GENERAL.DEVICE,GENERAL.HWADDR,IP4.ADDRESS device show $MAIN_NIC"
  run "ls /etc/NetworkManager/system-connections/ /etc/sysconfig/network-scripts/ 2>&1"

  section "A static IPv4 and IPv6 connection"
  run "sudo nmcli connection add type ethernet con-name lab-static ifname $NIC ipv4.method manual ipv4.addresses 192.0.2.10/24 ipv4.dns 192.0.2.53 ipv6.method manual ipv6.addresses 2001:db8::10/64 connection.autoconnect yes"
  expect 'successfully added'
  run "sudo nmcli connection up lab-static"
  run "ip -br addr show $NIC"
  expect '192.0.2.10/24'
  run "ip -6 addr show $NIC | grep inet6"
  expect '2001:db8::10/64'
  run "nmcli -g ipv4.method,ipv4.addresses,ipv6.addresses,connection.autoconnect connection show lab-static"
  run "sudo cat /etc/NetworkManager/system-connections/lab-static.nmconnection"
  run "ping -c 1 192.0.2.10 | tail -2; ping -6 -c 1 2001:db8::10 | tail -2"

  section "Changing it"
  run "sudo nmcli connection modify lab-static +ipv4.addresses 192.0.2.11/24"
  run "sudo nmcli connection up lab-static; ip -br addr show $NIC"
  expect '192.0.2.11/24'
  run "sudo nmcli connection modify lab-static -ipv4.addresses 192.0.2.11/24"
  run "sudo nmcli connection reload; sudo nmcli connection up lab-static; ip -br addr show $NIC"

  section "Starting at boot"
  run "systemctl is-enabled NetworkManager"
  run "nmcli -g connection.autoconnect connection show lab-static"
  run "nmcli general status"
}

phase2() {
  section "After a reboot"
  run "nmcli connection show --active"
  expect 'lab-static'
  run "ip -br addr show $NIC"
  expect '192.0.2.10/24'
}

cleanup() {
  nmcli connection delete lab-static >/dev/null 2>&1
}
