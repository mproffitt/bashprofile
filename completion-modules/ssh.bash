#!/bin/bash
# SSH tab completion
#_SERVER_LIST=$(cat ~/.ssh/config | grep -v '#' | awk '{ print $NF; }' | grep '^[a-z]\+' | grep -v '\.' | sort | uniq | tr "\n" " ");
_SERVER_LIST=$(cat /etc/hosts | grep -v '#' | cut -d\  -f2- | sort | uniq | tr "\n" " ");

_ssh_complete () {
    COMPREPLY=();
    local cur="${COMP_WORDS[COMP_CWORD]}";
    COMPREPLY=( $(compgen -S ' ' -W "${_SERVER_LIST}" -- ${cur}) );
}

complete -o default -F _ssh_complete  ssh
complete -o default -F _ssh_complete  w
complete -o default -F _ssh_complete  ws
complete -o default -F _ssh_complete  waitssh
