# 7.4 Install and update software packages from Red Hat Content Delivery
# Network, a remote repository, or from the local file system. On AlmaLinux
# or Rocky the CDN steps report that subscription-manager is absent; the
# notes then describe them from Red Hat's documentation.

phase1() {
  setup "rm -rf /srv/localrepo; mkdir -p /srv/localrepo"

  section "Where packages come from"
  run "cat /etc/redhat-release"
  run "dnf --version | head -2"
  run "sudo subscription-manager status 2>&1 | head -6"
  run "sudo subscription-manager repos --list-enabled 2>&1 | head -8"
  run "dnf repolist"
  run "grep -E '^\[|^(baseurl|metalink|mirrorlist|gpgcheck|enabled)' /etc/yum.repos.d/*.repo | head -12"

  section "Updates"
  run "sudo dnf check-update -q | head -5; echo exit=\$?"
  run "sudo dnf updateinfo summary 2>&1 | head -8"
  run "sudo dnf upgrade --assumeno 2>&1 | tail -4"
  run "sudo dnf upgrade -y tzdata 2>&1 | tail -3"
  run "sudo dnf history list | head -5"

  section "Installing an RPM file from the local file system"
  run "cd /tmp && dnf download tree 2>&1 | tail -1; ls /tmp/tree-*.rpm"
  run "rpm -qip /tmp/tree-*.rpm | head -6"
  run "sudo dnf install -y /tmp/tree-*.rpm 2>&1 | tail -3"
  run "rpm -q tree"
  expect '^tree-'
  run "sudo dnf remove -y tree 2>&1 | tail -2"

  section "A repository on the local file system"
  run "cd /srv/localrepo && sudo dnf download -q tree zsh 2>&1; ls /srv/localrepo"
  run "sudo createrepo_c /srv/localrepo | tail -1"
  run "ls /srv/localrepo/repodata | head -3"
  run "printf '[localrepo]\nname=Local packages\nbaseurl=file:///srv/localrepo\nenabled=1\ngpgcheck=0\n' | sudo tee /etc/yum.repos.d/localrepo.repo"
  run "dnf repolist"
  expect 'localrepo'
  run "sudo dnf --disablerepo='*' --enablerepo=localrepo install -y tree 2>&1 | tail -3"
  run "dnf info tree 2>/dev/null | grep -E '^(Name|Version|From repo|Repository)'"

  section "A remote repository by URL"
  run "sudo dnf config-manager --help 2>&1 | head -3"
  run "grep -h '^baseurl\|^mirrorlist\|^metalink' /etc/yum.repos.d/*.repo | head -2"
  run "sudo dnf config-manager --add-repo https://repo.almalinux.org/almalinux/10/extras/x86_64/os/ 2>&1 | tail -2"
  run "ls /etc/yum.repos.d/"
  run "sudo dnf --repo=repo.almalinux.org_almalinux_10_extras_x86_64_os_ makecache 2>&1 | tail -2"
  run "rpm -q gpg-pubkey --qf '%{NAME}-%{VERSION}  %{SUMMARY}\n'"
}

cleanup() {
  rpm -q tree >/dev/null && dnf -y -q remove tree
  rm -f /etc/yum.repos.d/localrepo.repo /etc/yum.repos.d/repo.almalinux.org_almalinux_10_extras_x86_64_os_.repo /tmp/tree-*.rpm
  rm -rf /srv/localrepo
}
