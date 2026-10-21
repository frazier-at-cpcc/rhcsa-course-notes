# 10.1 Configure firewall settings using firewall-cmd/firewalld: zones,
# sources, rich rules, port forwarding, and making runtime changes permanent.
# The SSH service in the default zone is never removed.

phase1() {
  setup "systemctl start httpd"

  section "Zones and what decides which zone a packet uses"
  run "sudo firewall-cmd --get-zones"
  run "sudo firewall-cmd --get-active-zones"
  run "sudo firewall-cmd --zone=internal --list-all"
  run "sudo firewall-cmd --get-zone-of-interface=$MAIN_NIC"

  section "A source-based zone"
  run "sudo firewall-cmd --permanent --zone=internal --add-source=192.0.2.0/24"
  run "sudo firewall-cmd --permanent --zone=internal --add-service=http"
  run "sudo firewall-cmd --reload"
  run "sudo firewall-cmd --get-active-zones"
  expect 'internal'
  run "sudo firewall-cmd --zone=internal --list-all"
  expect '192.0.2.0/24'

  section "Rich rules"
  run "sudo firewall-cmd --permanent --add-rich-rule='rule family=ipv4 source address=198.51.100.0/24 service name=ssh reject'"
  run "sudo firewall-cmd --permanent --add-rich-rule='rule family=ipv4 source address=203.0.113.5 port port=8443 protocol=tcp accept'"
  run "sudo firewall-cmd --reload; sudo firewall-cmd --list-rich-rules"
  expect '198.51.100.0/24'

  section "Port forwarding"
  run "sudo firewall-cmd --permanent --add-forward-port=port=8080:proto=tcp:toport=80"
  run "sudo firewall-cmd --reload; sudo firewall-cmd --list-forward-ports"
  expect 'toport=80'

  section "Runtime changes and --runtime-to-permanent"
  run "sudo firewall-cmd --add-port=9090/tcp; sudo firewall-cmd --list-ports; sudo firewall-cmd --permanent --list-ports"
  run "sudo firewall-cmd --runtime-to-permanent; sudo firewall-cmd --permanent --list-ports"
  expect '9090/tcp'
  run "sudo firewall-cmd --check-config"
  run "sudo ls /etc/firewalld/zones/"
  run "sudo nft list ruleset | grep -c 'tcp dport'"
}

phase2() {
  section "After a reboot"
  run "sudo firewall-cmd --get-active-zones"
  run "sudo firewall-cmd --list-rich-rules; sudo firewall-cmd --list-forward-ports; sudo firewall-cmd --list-ports"
  expect '9090/tcp'
}

cleanup() {
  systemctl stop httpd
  firewall-cmd -q --permanent --zone=internal --remove-source=192.0.2.0/24
  firewall-cmd -q --permanent --zone=internal --remove-service=http
  firewall-cmd -q --permanent --remove-rich-rule='rule family=ipv4 source address=198.51.100.0/24 service name=ssh reject'
  firewall-cmd -q --permanent --remove-rich-rule='rule family=ipv4 source address=203.0.113.5 port port=8443 protocol=tcp accept'
  firewall-cmd -q --permanent --remove-forward-port=port=8080:proto=tcp:toport=80
  firewall-cmd -q --permanent --remove-port=9090/tcp
  firewall-cmd -q --reload
}
