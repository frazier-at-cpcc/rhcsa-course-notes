# 10.5 Restore default file contexts; manage SELinux port labels; use Boolean
# settings to modify system SELinux settings.

phase1() {
  setup "cp -a /etc/httpd/conf/httpd.conf $STATE/httpd.conf.orig"
  setup "mkdir -p /web && echo 'lab site' > /web/index.html && sed -i 's#DocumentRoot \"/var/www/html\"#DocumentRoot \"/web\"#' /etc/httpd/conf/httpd.conf && printf '<Directory \"/web\">\n  Require all granted\n</Directory>\n' > /etc/httpd/conf.d/web.conf && systemctl restart httpd"

  section "A wrong context: the symptom"
  run "curl -s -o /dev/null -w '%{http_code}\n' http://localhost/index.html"
  expect '403'
  run "ls -Zd /web /web/index.html"
  expect 'default_t'
  run "sudo ausearch -m AVC -ts recent -i | grep -m1 denied"
  run "sudo sealert -a /var/log/audit/audit.log 2>/dev/null | grep -m3 -E 'SELinux is preventing|semanage fcontext|restorecon'"

  section "Restoring and defining default file contexts"
  run "sudo restorecon -Rv /web"
  run "matchpathcon /web /var/www/html"
  run "sudo semanage fcontext -a -t httpd_sys_content_t '/web(/.*)?'"
  run "sudo semanage fcontext -l -C"
  expect '/web'
  run "sudo restorecon -Rv /web"
  expect 'httpd_sys_content_t'
  run "curl -s http://localhost/index.html"
  expect 'lab site'
  run "sudo chcon -t user_home_t /web/index.html; ls -Z /web/index.html; sudo restorecon -v /web/index.html"
  run "sudo touch /.autorelabel; ls -l /.autorelabel; sudo rm /.autorelabel"

  section "Port labels"
  run "sudo sed -i 's/^Listen 80$/Listen 82/' /etc/httpd/conf/httpd.conf"
  run "sudo systemctl restart httpd"
  expect 'failed|Job for httpd'
  run "sudo journalctl -u httpd -n 3 --no-pager | tail -2"
  run "sudo semanage port -l | grep -w http_port_t"
  run "sudo semanage port -a -t http_port_t -p tcp 82"
  run "sudo semanage port -l -C"
  expect '82'
  run "sudo systemctl restart httpd; systemctl is-active httpd"
  expect '^active'
  run "sudo firewall-cmd --permanent --add-port=82/tcp; sudo firewall-cmd --reload"
  run "curl -s http://servera:82/index.html"
  expect 'lab site'

  section "Booleans"
  run "getsebool -a | grep -E '^httpd_(enable_homedirs|can_network_connect|read_user_content) '"
  run "sudo semanage boolean -l | grep -E '^httpd_enable_homedirs '"
  run "sudo setsebool httpd_enable_homedirs on; getsebool httpd_enable_homedirs"
  run "sudo semanage boolean -l -C"
  run "sudo setsebool -P httpd_enable_homedirs on; sudo semanage boolean -l -C"
  expect 'httpd_enable_homedirs'
}

phase2() {
  section "After a reboot"
  run "getsebool httpd_enable_homedirs"
  expect '--> on'
  run "sudo semanage port -l -C; sudo semanage fcontext -l -C"
  run "systemctl is-active httpd || sudo systemctl start httpd; curl -s http://servera:82/index.html"
}

cleanup() {
  systemctl stop httpd
  cp -a "$STATE/httpd.conf.orig" /etc/httpd/conf/httpd.conf; rm -f /etc/httpd/conf.d/web.conf
  semanage fcontext -d '/web(/.*)?' 2>/dev/null; semanage port -d -t http_port_t -p tcp 82 2>/dev/null
  setsebool -P httpd_enable_homedirs off
  firewall-cmd -q --permanent --remove-port=82/tcp; firewall-cmd -q --reload
  rm -rf /web
}
