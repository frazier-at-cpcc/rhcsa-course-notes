# 8.2 Configure hostname resolution.

phase1() {
  setup "cp -a /etc/hosts $STATE/hosts.orig; hostname > $STATE/hostname"

  section "The host name"
  run "hostname; hostname -s; hostname -I"
  run "hostnamectl"
  run "sudo hostnamectl hostname serverx.lab.example.com; hostnamectl --static; cat /etc/hostname"
  expect 'serverx'
  run "sudo hostnamectl hostname servera.lab.example.com; cat /etc/hostname"

  section "Static entries and the lookup order"
  run "cat /etc/hosts"
  run "grep '^hosts:' /etc/nsswitch.conf"
  run "echo '192.0.2.20  serverb.lab.example.com serverb' | sudo tee -a /etc/hosts"
  run "getent hosts serverb"
  expect '192.0.2.20'
  run "getent ahosts servera.lab.example.com | head -2"
  run "ping -c1 -W1 serverb | head -1"
  run "host serverb 2>&1; dig +short serverb"

  section "DNS servers"
  run "cat /etc/resolv.conf"
  run "nmcli -g ipv4.dns,ipv4.dns-search,ipv4.ignore-auto-dns connection show \"\$(nmcli -g NAME connection show --active | head -1)\""
  run "host www.redhat.com | head -2"
  run "dig +short www.redhat.com | tail -2"
  run "getent hosts www.redhat.com"
  run "nmcli connection show --active"
  note "Changing DNS servers for the main connection would cut this machine off its network, so the commands are shown for the lab connection from 8.1: nmcli connection modify NAME ipv4.dns 192.0.2.53 ipv4.ignore-auto-dns yes ipv4.dns-search lab.example.com"
  run "sudo nmcli connection add type ethernet con-name dns-demo ifname $NIC ipv4.method manual ipv4.addresses 192.0.2.30/24 ipv4.dns 192.0.2.53 ipv4.dns-search lab.example.com ipv4.ignore-auto-dns yes ipv6.method disabled autoconnect no >/dev/null; nmcli -g ipv4.dns,ipv4.dns-search,ipv4.ignore-auto-dns connection show dns-demo"
  expect '192.0.2.53'
}

cleanup() {
  nmcli connection delete dns-demo >/dev/null 2>&1
  cp -a "$STATE/hosts.orig" /etc/hosts
  hostnamectl hostname "$(cat "$STATE/hostname")"
}
