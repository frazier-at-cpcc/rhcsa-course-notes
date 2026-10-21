# 8.3 Restrict network access using firewalld and firewall-cmd.

phase1() {
  section "Is it running, and what does it allow?"
  run "systemctl is-active firewalld; systemctl is-enabled firewalld"
  run "sudo firewall-cmd --state"
  run "sudo firewall-cmd --get-default-zone"
  run "sudo firewall-cmd --get-active-zones"
  run "sudo firewall-cmd --list-all"
  expect 'services:'
  run "sudo firewall-cmd --get-services | tr ' ' '\n' | grep -E '^(http|https|ssh|nfs|samba|dns)$'"
  run "sudo firewall-cmd --info-service=http"

  section "Allowing a service: runtime and permanent"
  run "sudo systemctl start httpd; curl -s -o /dev/null -w '%{http_code}\n' http://$MAIN_IP/"
  run "sudo firewall-cmd --add-service=http"
  run "sudo firewall-cmd --list-services"
  expect 'http'
  run "sudo firewall-cmd --list-services --permanent"
  run "sudo firewall-cmd --reload; sudo firewall-cmd --list-services"
  run "sudo firewall-cmd --permanent --add-service=http"
  run "sudo firewall-cmd --reload; sudo firewall-cmd --list-services"
  expect 'http'

  section "Allowing a port"
  run "sudo firewall-cmd --permanent --add-port=8080/tcp"
  run "sudo firewall-cmd --reload; sudo firewall-cmd --list-ports"
  expect '8080/tcp'
  run "sudo firewall-cmd --query-port=8080/tcp"

  section "Taking access away"
  run "sudo firewall-cmd --permanent --remove-port=8080/tcp; sudo firewall-cmd --permanent --remove-service=http"
  run "sudo firewall-cmd --reload; sudo firewall-cmd --list-all | grep -E 'services|ports'"
  run "sudo firewall-cmd --permanent --list-all | grep -E 'services|ports'"
  run "ls /etc/firewalld/zones/; sudo cat /etc/firewalld/zones/\$(sudo firewall-cmd --get-default-zone).xml"
}

cleanup() {
  systemctl stop httpd
  firewall-cmd -q --permanent --remove-service=http 2>/dev/null; firewall-cmd -q --permanent --remove-port=8080/tcp 2>/dev/null
  firewall-cmd -q --reload
}
