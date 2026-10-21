#!/usr/bin/env bash
# Verifies every command shown in 2.1 RPM Repositories and DNF.
# Builds two local repositories inside an AlmaLinux 10 container: one of
# signed AlmaLinux RPMs (with a comps group) and one holding an unsigned RPM
# built here, then configures, queries, installs, and removes from them.
# Commands run as the user student through sudo, the way the notes show them.
# Left out: Red Hat CDN access (subscription-manager), covered in 7.4.
# Needs: docker
set -euo pipefail
cd "$(dirname "$0")"
source lib/container.sh
CT=rh232-21
trap 'ct_down $CT' EXIT
ct_up $CT createrepo_c rpm-build sudo
ct 'useradd student && echo "student ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/student && chmod 440 /etc/sudoers.d/student'

say() { printf '\n== %s\n' "$*"; }
# run CMD: run as student, print a transcript, keep the output in $OUT
run() { printf '$ %s\n' "$1"; OUT=$(ct_as student "$1" 2>&1) || RC=$?; printf '%s\n' "$OUT"; }
has() { grep -qE -- "$1" <<<"$OUT" || { echo "MISSING: $1" >&2; exit 1; }; }
hasx() { grep -qxF -- "$1" <<<"$OUT" || { echo "MISSING LINE: $1" >&2; exit 1; }; }

say "dnf version and yum alias"
run 'dnf --version | head -1'; hasx '4.20.0'
run 'readlink /usr/bin/yum /usr/bin/dnf'; [ "$(grep -c dnf-3 <<<"$OUT")" = 2 ]

say "build a local repository with createrepo_c"
run 'sudo mkdir /srv/labrepo && cd /srv/labrepo && sudo dnf download -q tree zsh && ls'
hasx 'tree-2.1.0-8.el10.x86_64.rpm'; hasx 'zsh-5.9-15.el10.x86_64.rpm'
cat <<'EOF' | ct 'cat > /srv/comps.xml'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE comps PUBLIC "-//Red Hat, Inc.//DTD Comps info//EN" "comps.dtd">
<comps>
  <group>
    <id>lab-shells</id>
    <name>Lab Shells</name>
    <description>Shells and tools for the lab</description>
    <default>false</default>
    <uservisible>true</uservisible>
    <packagelist>
      <packagereq type="mandatory">zsh</packagereq>
      <packagereq type="default">tree</packagereq>
    </packagelist>
  </group>
</comps>
EOF
run 'sudo cp /etc/pki/rpm-gpg/RPM-GPG-KEY-AlmaLinux-10 /srv/labrepo/RPM-GPG-KEY'
run 'cd /srv/labrepo && sudo createrepo_c -g /srv/comps.xml .'
hasx 'Directory walk done - 2 packages'
run 'ls /srv/labrepo/repodata'; hasx 'repomd.xml'; has 'comps.xml'

say "hide the distribution repos so the lab repo stands alone"
ct 'mkdir -p /root/repos.bak && mv /etc/yum.repos.d/*.repo /root/repos.bak/'

say "write a .repo file by hand"
cat <<'EOF' | ct 'cat > /etc/yum.repos.d/labrepo.repo'
[labrepo]
name=Lab
baseurl=file:///srv/labrepo
enabled=1
gpgcheck=1
gpgkey=file:///srv/labrepo/RPM-GPG-KEY
EOF
run 'cat /etc/yum.repos.d/labrepo.repo'; hasx 'gpgkey=file:///srv/labrepo/RPM-GPG-KEY'
run 'dnf repolist'; has '^labrepo +Lab$'
run 'dnf -q repoinfo labrepo'
has 'Repo-id +: labrepo'; has 'Repo-status +: enabled'; has 'Repo-pkgs +: 2'

say "search, provides, info"
run 'dnf -q search shell'; hasx 'zsh.x86_64 : Powerful interactive shell'
run 'dnf -q provides /usr/bin/zsh'; has '^Repo +: labrepo'
run "dnf -q provides '*/bin/zsh' | head -1"; has '^zsh-5.9-15.el10.x86_64 : '
run 'dnf -q info zsh | head -8'; has '^Repository +: labrepo'

say "install and query with rpm"
run 'sudo dnf -y -q install tree'; hasx 'Installed:'; has '^  tree-2.1.0-8.el10.x86_64'
run 'rpm -q tree'; hasx 'tree-2.1.0-8.el10.x86_64'
run 'rpm --eval %_dbpath; readlink /var/lib/rpm'; hasx '/usr/lib/sysimage/rpm'; hasx '../../usr/lib/sysimage/rpm'
run 'rpm -qa | wc -l'; has '^[0-9]{3}$'
run "rpm -qa 'tree*'"; hasx 'tree-2.1.0-8.el10.x86_64'
run 'rpm -qi tree | head -4'; has '^Version +: 2.1.0'
run 'rpm -ql tree | grep -v build-id'; hasx '/usr/bin/tree'
run 'rpm -qf /usr/bin/tree'; hasx 'tree-2.1.0-8.el10.x86_64'
run 'rpm -qf /etc/dnf/dnf.conf'; has '^dnf-data-4.20.0'
run 'rpm -qc dnf-data'; hasx '/etc/dnf/dnf.conf'
run 'rpm -qd tree'; hasx '/usr/share/man/man1/tree.1.gz'
run 'cd /srv/labrepo && rpm -qip zsh-5.9-15.el10.x86_64.rpm'; has '^Name +: zsh'
run 'cd /srv/labrepo && rpm -qlp zsh-5.9-15.el10.x86_64.rpm | grep bin/zsh$'; hasx '/usr/bin/zsh'
run 'rpm -q zsh'; hasx 'package zsh is not installed'

say "remove"
run 'sudo dnf -y -q remove tree'
run 'rpm -q tree'; hasx 'package tree is not installed'

say "groups"
run 'dnf -q group list'; hasx '   Lab Shells'
run 'dnf -q group info "Lab Shells"'; hasx ' Mandatory Packages:'; hasx ' Default Packages:'
run 'sudo dnf -y -q group install "Lab Shells"'
run 'rpm -q zsh tree'; [ "$(grep -c el10 <<<"$OUT")" = 2 ]
run 'dnf -q group list --installed'; hasx '   Lab Shells'

say "history and undo"
run 'sudo dnf history info last'
has 'group install Lab Shells'; has 'Success'
run 'sudo dnf -y -q history undo last'
run 'rpm -q zsh'; hasx 'package zsh is not installed'
run 'sudo dnf -y -q install @lab-shells && rpm -q zsh'; hasx 'zsh-5.9-15.el10.x86_64'
run 'sudo dnf -y -q history undo last && rpm -q zsh'; hasx 'package zsh is not installed'

say "unsigned package from a repo added with config-manager"
cat <<'EOF' | ct 'mkdir -p /root/rpmbuild/SPECS && cat > /root/rpmbuild/SPECS/labtools.spec'
Name: labtools
Version: 1.0
Release: 1
Summary: Lab helper scripts
License: MIT
BuildArch: noarch
%description
Helper scripts for the lab.
%install
mkdir -p %{buildroot}/usr/local/bin
printf '#!/bin/bash\necho lab ready\n' > %{buildroot}/usr/local/bin/labcheck
chmod 755 %{buildroot}/usr/local/bin/labcheck
%files
/usr/local/bin/labcheck
EOF
ct 'rpmbuild -bb /root/rpmbuild/SPECS/labtools.spec >/dev/null 2>&1
    mkdir -p /srv/tools && cp /root/rpmbuild/RPMS/noarch/*.rpm /srv/tools/
    createrepo_c -q /srv/tools'
run 'sudo dnf config-manager --add-repo file:///srv/tools'
hasx 'Adding repo from: file:///srv/tools'
run 'cat /etc/yum.repos.d/srv_tools.repo'
hasx '[srv_tools]'; hasx 'baseurl=file:///srv/tools'; hasx 'enabled=1'
! grep -q gpgcheck <<<"$OUT"
run 'grep gpgcheck /etc/dnf/dnf.conf'; hasx 'gpgcheck=1'
RC=0; run 'sudo dnf -y install labtools 2>&1 | tail -2'
hasx 'Package labtools-1.0-1.noarch.rpm is not signed'
hasx 'Error: GPG check FAILED'
run 'sudo dnf config-manager --save --setopt=srv_tools.gpgcheck=0'
run 'tail -1 /etc/yum.repos.d/srv_tools.repo'; hasx 'gpgcheck=0'
run 'sudo dnf -y -q install labtools && labcheck'; hasx 'lab ready'
run 'rpm -qf /usr/local/bin/labcheck'; hasx 'labtools-1.0-1.noarch'
run "dnf -q provides '*/labcheck'"
hasx 'labtools-1.0-1.noarch : Lab helper scripts'; has '^Repo +: @System$'; has '^Repo +: srv_tools$'

say "disable and enable a repository"
run 'sudo dnf config-manager --disable srv_tools'
run 'grep enabled /etc/yum.repos.d/srv_tools.repo'; hasx 'enabled=0'
run 'dnf repolist'; ! grep -q srv_tools <<<"$OUT"
run 'dnf repolist --all'; has 'srv_tools.*disabled'
run 'sudo dnf config-manager --enable srv_tools'
run 'grep enabled /etc/yum.repos.d/srv_tools.repo'; hasx 'enabled=1'

say "modularity is gone in practice"
run 'dnf module list 2>&1 | head -1'; has 'modularity is deprecated'

echo
echo "ALL 2.1 RPM-AND-DNF CHECKS PASSED"
