#!/usr/bin/env bash
# Verifies every command shown in 1.1 The Shell and Text Editing.
# Runs in a throwaway AlmaLinux 10 container. The terminal blocks are typed
# into an interactive bash (bash -i) as student, so aliases, history
# expansion, and the shell's own error messages match a real terminal.
# The vim keystroke table is proved by replaying the keys with vim -s.
# Not executed: nano keys and Tab completion (they need a real terminal).
# Needs: docker
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/lib/container.sh"
NAME=rh1a2-11
WORK=$(mktemp -d)
trap 'ct_down "$NAME"; rm -rf "$WORK"' EXIT

say() { printf '\n== %s\n' "$*"; }
# term <user>: type stdin into an interactive bash; print a clean
# transcript with the prompt shortened to "$ ", keep a copy for has()
term() {
  { ct_as "$1" 'bash -i 2>&1' || true; } | sed -e '/cannot set terminal process group/d' \
    -e '/no job control in this shell/d' -e 's/^\[[^]]*\][$#] /$ /' \
    -e '/^\$ exit$/d' -e '/^\$ $/d' | tee "$WORK/out"
}
has() { grep -qxF -- "$1" "$WORK/out" || { echo "MISSING: $1" >&2; exit 1; }; }

ct_up "$NAME" vim-enhanced
ct 'useradd student'

say "the prompt and who you are"
term student <<'EOF'
whoami; hostname; echo $SHELL
echo "$PS1"
EOF
has 'student'
has 'servera.lab.example.com'
has '/bin/bash'
has '[\u@\h \W]\$ '
# root's prompt ends in #
out=$(docker exec -i "$NAME" bash -ic 'echo "${PS1@P}"' 2>/dev/null)
[ "$out" = "[root@servera /]# " ]
ct 'bash --version | head -1' | grep -q 'version 5\.2\.'

say "command, options, arguments"
term student <<'EOF'
ls -l /etc/services
ls -lh /etc/services
ls -l -h /etc/services
ls -l --human-readable /etc/services
touch -notes.txt
touch -- -notes.txt; ls -- -notes.txt
mkdir -p reports && cd reports && pwd
ls /nope || echo "no such path"
EOF
has '-rw-r--r-- 1 root root 701707 Nov 29  2023 /etc/services'
[ "$(grep -c -- '-rw-r--r-- 1 root root 686K Nov 29  2023 /etc/services' "$WORK/out")" = 3 ]
has "touch: invalid option -- 'n'"
has "Try 'touch --help' for more information."
has '-notes.txt'
has '/home/student/reports'
has "ls: cannot access '/nope': No such file or directory"
has 'no such path'

say "builtin, alias, or program: type"
term student <<'EOF'
type cd grep useradd vi
EOF
has 'cd is a shell builtin'
has "grep is aliased to \`grep --color=auto'"
has 'useradd is /usr/sbin/useradd'
has 'vi is /usr/bin/vi'
# vi is vim-minimal; vim is vim-enhanced; RHEL 10 no longer aliases vi=vim
[ "$(ct 'rpm -qf --qf "%{NAME}\n" /usr/bin/vi')" = "vim-minimal" ]
[ "$(ct 'rpm -qf --qf "%{NAME}\n" /usr/bin/vim')" = "vim-enhanced" ]
ct '[ ! -e /etc/profile.d/vim.sh ]'
# No EDITOR or VISUAL is set, so crontab -e and visudo fall back to vi
[ -z "$(ct_as student 'echo $EDITOR$VISUAL')" ]

say "quoting and expansion"
term student <<'EOF'
echo "Home is $HOME"
echo 'Home is $HOME'
echo "Host: $(hostname -s)"
cd /etc; echo host*; echo "host*"
cd; mkdir -p web/{html,logs,conf}; echo web/*
touch "q3 report.txt"
ls q3 report.txt
wc -c "q3 report.txt"
EOF
has 'Home is /home/student'
has 'Home is $HOME'
has 'Host: servera'
has 'host.conf hostname hosts'
has 'host*'
has 'web/conf web/html web/logs'
has "ls: cannot access 'q3': No such file or directory"
has "ls: cannot access 'report.txt': No such file or directory"
has '0 q3 report.txt'

say "history"
term student <<'EOF'
hostname
id -un
history 3
!host
echo $HISTSIZE $HISTFILE
EOF
# Earlier shells in this test already wrote history, so numbers vary
grep -qE '^ +[0-9]+  hostname$' "$WORK/out"
grep -qE '^ +[0-9]+  id -un$' "$WORK/out"
grep -qE '^ +[0-9]+  history 3$' "$WORK/out"
grep -A2 -xF '$ !host' "$WORK/out" | sed -n 2,3p > "$WORK/bang"
[ "$(cat "$WORK/bang")" = $'hostname\nservera.lab.example.com' ]
has '1000 /home/student/.bash_history'
# history is written to the file when the shell exits
ct_as student 'tail -1 ~/.bash_history' | grep -qxF 'echo $HISTSIZE $HISTFILE'

say "vim keystrokes from the table, replayed for real"
ct_as student 'printf "ServerName servera\nListen 80\nDocumentRoot /var/www/html\n" > web.conf'
v() { ct_as student "printf '$1' > keys; TERM=xterm vim -N -u NONE -i NONE -n -s keys web.conf >/dev/null 2>&1 </dev/null"; }
v '/Listen\rccListen 8080\033:wq\r'          # search, change line, write+quit
[ "$(ct_as student 'sed -n 2p web.conf')" = "Listen 8080" ]
v 'ggyyGp:wq\r'                                # yank line 1, put after last
[ "$(ct_as student 'tail -1 web.conf')" = "ServerName servera" ]
v 'Gdd:x\r'                                    # delete last line, :x saves
[ "$(ct_as student 'wc -l < web.conf')" = 3 ]
v ':%%s/servera/serverb/g\r:wq\r'              # substitute everywhere
ct_as student 'grep -qx "ServerName serverb" web.conf'
v 'Goinclude conf.d/*.conf\033u:wq\r'         # o opens a line; u undoes
[ "$(ct_as student 'wc -l < web.conf')" = 3 ]
v 'dddd:q!\r'                                 # :q! throws changes away
[ "$(ct_as student 'wc -l < web.conf')" = 3 ]
v 'ggOServerAdmin root@localhost\033:w\r:q\r' # O opens a line above
[ "$(ct_as student 'head -1 web.conf')" = "ServerAdmin root@localhost" ]
v 'GI# \033:wq\r'                             # I inserts at line start
[ "$(ct_as student 'tail -1 web.conf')" = "# DocumentRoot /var/www/html" ]
v 'GA # web root\033:wq\r'                    # A appends at line end
[ "$(ct_as student 'tail -1 web.conf')" = "# DocumentRoot /var/www/html # web root" ]
v ':3\rcwPort\033:wq\r'                       # :3 goes to line 3; cw changes a word
[ "$(ct_as student 'sed -n 3p web.conf')" = "Port 8080" ]
v ':3\rcwListen\033:wq\r'
v 'G0xx:wq\r'                                 # x deletes one character
[ "$(ct_as student 'tail -1 web.conf')" = "DocumentRoot /var/www/html # web root" ]
v 'G$xu\x12:wq\r'                             # u undoes; Ctrl+R redoes
[ "$(ct_as student 'tail -1 web.conf')" = "DocumentRoot /var/www/html # web roo" ]
v 'gg2ddGp:wq\r'                              # 2dd deletes two lines; p puts below
[ "$(ct_as student 'cat web.conf | tr "\n" "|"')" = "Listen 8080|DocumentRoot /var/www/html # web roo|ServerAdmin root@localhost|ServerName serverb|" ]
v 'ggyyP:wq\r'                                # P puts above the cursor
[ "$(ct_as student 'head -2 web.conf | uniq | wc -l')" = 1 ]
ct_as student 'cat web.conf'

say "the try-it task, end to end"
ct_as student 'printf "ServerName servera\nListen 80\nDocumentRoot /var/www/html\n" > try.conf'
# Keys replayed with -s form one undo block; ":let &ul=&ul" ends a block
# the way a pause between keystrokes does when a person types them
ct_as student "printf ':%%s/Listen 80/Listen 8080/\r:let &ul=&ul\rggyyp:let &ul=&ul\ru:wq\r' > k; TERM=xterm vim -N -u NONE -i NONE -n -s k try.conf >/dev/null 2>&1 </dev/null"
[ "$(ct_as student 'cat try.conf')" = $'ServerName servera\nListen 8080\nDocumentRoot /var/www/html' ]

echo; echo "ALL 1.1 SHELL-AND-EDITING CHECKS PASSED"
