#!/bin/bash
#
# Martin Proffitts bash profile
#
# @package bashprofile
# @author  Martin Proffitt <mproffitt@choclab.net>

##
# Do not load if we're logging in as root, or if we're not in an
# interactive session.
if [ "$(whoami)" = 'root' ] || ! echo $- | grep -q i; then
    return;
fi
reset

export CLICOLOR=1
export LSCOLORS=GxFxCxDxBxegedabagacad
export HISTSIZE=10000
export HISTFILESIZE=10000
export HISTCONTROL=ignoreboth
export EDITOR=vim

[ "$TERM" = 'xterm' ] && export TERM='xterm-256color'
[ -z "$HOME" ] && HOME='/home/'$(whoami);
export HOME=$HOME;
[ -z "${XDG_CONFIG_HOME}" ] && export XDG_CONFIG_HOME="${HOME}/.config"

# Setup the terminal

export GRADLE_HOME='/usr/local/gradle'
export GOPATH="$HOME/src/go"
export GOBIN="${GOPATH}/bin"
export JAVA_HOME="/usr/lib/jvm/java-8-oracle"

# add application specific <bin> path
[ -d "${HOME}/bin"                   ] && PATH="${HOME}/bin:$PATH"
[ -d "/git/repos/GitTools/bin"       ] && PATH="$PATH:${HOME}/git/repos/GitTools/bin"
[ -d "/var/lib/gems/1.8/bin"         ] && PATH="$PATH:/var/lib/gems/1.8/bin"
[ -d "/usr/local/mysql/bin"          ] && PATH="$PATH:/usr/local/mysql/bin"
[ -d "/usr/local/pear/bin"           ] && PATH="$PATH:/usr/local/pear/bin"
[ -d "/usr/local/gradle/bin"         ] && PATH="$PATH:/usr/local/gradle/bin"
[ -d "${HOME}/bin/jmeter/bin"        ] && PATH="$PATH:${HOME}/bin/jmeter/bin"
[ -d "/usr/texbin"                   ] && PATH="$PATH:/usr/texbin"
[ -d "${HOME}/.local/bin"            ] && PATH="$HOME/.local/bin:$PATH"
[ -d "/usr/local/cuda/bin"           ] && PATH="$PATH:/usr/local/cuda/bin"
[ -d "/usr/local/go/bin"             ] && PATH="$PATH:/usr/local/go/bin"
[ -d "${GOPATH}/bin"                 ] && PATH="$PATH:${GOPATH}/bin"
[ -d "/opt/mssql-tools/bin"          ] && PATH="$PATH:/opt/mssql-tools/bin"
[ -d "${HOME}/.bashprofile/bin"      ] && PATH="$PATH:${HOME}/.bashprofile/bin"

# Windows specific paths
if [ "$(uname -o)" = 'Cygwin' ] ; then
    [ -d '/cygdrive/c/Program Files (x86)/MSBuild/14.0/Bin' ] && PATH=$PATH':/cygdrive/c/Program Files (x86)/MSBuild/14.0/Bin'
fi

export PATH=$PATH

for file in $(ls "$HOME"/.bashprofile | grep -v 'install\|README\|bash_profile') ; do
    if [ -f "$HOME/.bashprofile/$file" ]  && ! echo "$file" | grep -q disabled ; then
        source "$HOME/.bashprofile/$file";
    fi
done

##
# Gets the current working directory, changing the users home for ~ unless the current
# directory IS the users home.
#
function _pwd()
{
    local cwd prwd
    cwd="$(pwd)";
    prwd="$cwd";
    moduleroot &>/dev/null;
    if [ $? -eq 0 ] ; then
        prwd=$(echo "$cwd" | sed "s/$(pwd | sed 's/\//\\\//g')\///");
    fi
    cd "$cwd" || return 1;

    sed 's/^[ \t]*//g' <<<"$(sed "s/$(sed 's/\//\\\//g' <<<"$HOME")\//~\//" <<<"$prwd")";
}

##
# Lists the number of files in the current directory
#
function fileEntries()
{
    local entries hidden
    entries=$(ls -A | wc -l | awk '{print $1}');
    hidden=$(( $( ls -A | wc -l ) - $( ls | wc -l)));

    echo -n $'\e[1m\e[31m'"$(hostname)"$'\e[0m'' : '
    echo $'\e[37m'"$(_pwd)": $'\e[32m'"$entries" entries, "$hidden" hidden.$'\e[0m'
}

##
# Gets a prompt line for SSHSF
#
function sshfsPrompt()
{
    if [ "$(pwd)" != '/' ] && grep -q "$(pwd)[^/]*fuse.sshfs*" /etc/mtab; then
        echo $'\e[37msshfs: \e[0m'"$(grep "$(pwd)" /etc/mtab | cut -d\  -f1)"
    fi
}

##
# Gets the shell prompt
#
function getPrompt()
{
    fileEntries;
    if isGitModule ; then
        gitBranch;
    elif isSvnModule ; then
        svnModule;
    fi
    if [ "$(uname -o)" != 'Cygwin' ] ; then
        sshfsPrompt
    fi
}

if [ -z "${POWERLINE_BASH_CONTINUATION}" ]; then
    PS1='$(getPrompt)\n\[\033[00m\]\$ '
fi

SSH_ENV="$HOME/.keychain/${HOSTNAME}-sh"
function startAgent() {
    inform "Initialising new SSH agent..."
    export BW_SESSION=$(
        bw unlock --raw $(kwalletcli -f 'accounts' -e bitwarden | grep master | cut -d: -f2- | awk '{print $NF}')
    )
    bw sync
    for f in $(ls ~/.ssh | grep id_rsa | grep -v pub); do if [ -d $f ]; then continue; fi;
        expect ${HOME}/.bashprofile/bin/keychain.expect ~/.ssh/$f $(
            bw list items --search $(basename $f) | jq -r '.[].fields[]|select(.name=="password").value'
        );
    done
    source "${SSH_ENV}" > /dev/null
}

# Start the key agent before starting TMUX
if [ -f "${SSH_ENV}" ]; then
     source "${SSH_ENV}" > /dev/null
     #if ! ps -ef | grep -v grep | grep "${SSH_AGENT_PID}" > /dev/null; then
     if ! ps aux | grep -v grep | grep -q ".*${SSH_AGENT_PID}.*ssh-agent$" ; then
         startAgent;
     fi
else
     startAgent;
fi
tunnels

# Do not run tmux if we are running cygwin - it's hellishly slow.
if [ "$(uname -o)" != 'Cygwin' ]; then
    # if tmux exists and is not currently running, load it.
    if which tmux &>/dev/null && ! pgrep tmux &>/dev/null ; then
        tmux;
    fi
fi

[[ -d "$HOME/.rvm" ]] && [[ -s "$HOME/.rvm/scripts/rvm" ]] && source "$HOME/.rvm/scripts/rvm";
# suppress error code from last command as we don't care if .rvm doesn't exist.
[ $? -ne 0 ] && echo -n '';

# Python virtualenv
export WORKON_HOME="${HOME}/.virtualenv"
export VIRTUALENVWRAPPER_PYTHON="/usr/bin/python3"
source /usr/local/bin/virtualenvwrapper.sh

#THIS MUST BE AT THE END OF THE FILE FOR SDKMAN TO WORK!!!
export SDKMAN_DIR="${HOME}/.sdkman"
[[ -s "${HOME}/.sdkman/bin/sdkman-init.sh" ]] && source "${HOME}/.sdkman/bin/sdkman-init.sh"
