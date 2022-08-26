#!/bin/bash -xe
#
# Martin Proffitts bash profile
#
# @package bashprofile
# @author  Martin Proffitt <mproffitt@choclab.net>

##
# Do not load if we're logging in as root, or if we're not in an
# interactive session.
if [ "$(whoami)" = 'root' ] || ! grep -q i <<< $-; then
    return;
fi
reset

export CLICOLOR=1
export LSCOLORS=GxFxCxDxBxegedabagacad
export HISTSIZE=10000
export HISTFILESIZE=10000
export HISTCONTROL=ignoreboth
export HISTTIMEFORMAT="%F:%T "
export EDITOR=vim

[ "$TERM" = 'xterm' ] && export TERM='xterm-256color'
[ -z "${XDG_CONFIG_HOME}" ] && export XDG_CONFIG_HOME="${HOME}/.config"

# Setup the terminal
export JAVA_HOME="/usr/lib/jvm/java-11-openjdk-amd64/"
export GRADLE_HOME='/usr/local/gradle'
export GOPATH="$HOME"
export GOBIN="${GOPATH}/bin"

export GOROOT=""
if grep -q snap <<<$(which go); then
    export GOROOT=/snap/go/current
fi

if [ -z "${TMUX}" ] ; then
    # reset PATH to system default - useful when re-sourcing the profile
    # so path doesn't fill with duplicates
    source /etc/environment
    # add application specific <bin> path
    # We load these from outside TMuX to ensure they are loaded only once and
    # shared across sessions instead of attempting to load on each and every session
    [ -d "/var/lib/gems/1.8/bin"          ] && PATH="$PATH:/var/lib/gems/1.8/bin"
    [ -d "/usr/local/mysql/bin"           ] && PATH="$PATH:/usr/local/mysql/bin"
    [ -d "/usr/local/pear/bin"            ] && PATH="$PATH:/usr/local/pear/bin"
    [ -d "/usr/local/gradle/bin"          ] && PATH="$PATH:/usr/local/gradle/bin"
    [ -d "/usr/texbin"                    ] && PATH="$PATH:/usr/texbin"
    [ -d "/usr/local/cuda/bin"            ] && PATH="$PATH:/usr/local/cuda/bin"
    [ -d "/usr/local/go/bin"              ] && PATH="$PATH:/usr/local/go/bin"
    [ -d "/opt/mssql-tools/bin"           ] && PATH="$PATH:/opt/mssql-tools/bin"

    [ -d "${HOME}/bin"                    ] && PATH="$PATH:${HOME}/bin" # meteor
    [ -d "${HOME}/bin/jmeter/bin"         ] && PATH="$PATH:${HOME}/bin/jmeter/bin"
    [ -d "${HOME}/git/repos/GitTools/bin" ] && PATH="$PATH:${HOME}/git/repos/GitTools/bin"
    [ -d "${HOME}/.local/bin"             ] && PATH="$PATH:$HOME/.local/bin"
    [ -d "${HOME}/.bashprofile/bin"       ] && PATH="$PATH:${HOME}/.bashprofile/bin"
    [ -d "${HOME}/.krew/bin"              ] && PATH="$PATH:${HOME}/.krew/bin"
    export PATH=$PATH
fi


for file in $(ls "$HOME"/.bashprofile | grep -v 'install\|README\|bash_profile') ; do
    if [ -f "$HOME/.bashprofile/$file" ]  && ! grep -q disabled <<< ${file}; then
        source "$HOME/.bashprofile/$file";
    fi
done

if [ -z "${POWERLINE_BASH_CONTINUATION}" ]; then
    PS1='$(getPrompt)\n\[\033[00m\]\$ '
fi

function addKeys() {
    for f in $(ls ~/.ssh | grep id_rsa | grep -v pub); do if [ -d $f ]; then continue; fi;
        expect ${HOME}/.bashprofile/bin/keychain.expect ~/.ssh/$f $(
            bwv "keys/$(basename ${f})?field=password" | jq -r .value
        );
    done
}

SSH_ENV="$HOME/.keychain/${HOSTNAME}-sh"
function startAgent() {
    inform "Initialising new SSH agent..."
    # wait for bitwarden to come up fully
    inform "Waiting for bwv to become available"
    while [ -z "$(bwv 'example/test?property=username' | jq -r .value 2>/dev/null)" ]; do
        sleep 1;
    done
    inform "Loading ssh keys"
    addKeys;
    source "${SSH_ENV}" > /dev/null
}

# Start the key agent before starting TMUX
if [ -f "${SSH_ENV}" ]; then
    source "${SSH_ENV}"
fi

if [ -z ${SSH_AGENT_PID} ] || [ -z "$(pgrep ssh-agent | awk '/'${SSH_AGENT_PID}'/{print}')" ]; then
    startAgent;
fi
tunnels

[[ -d "$HOME/.rvm" ]] && [[ -s "$HOME/.rvm/scripts/rvm" ]] && source "$HOME/.rvm/scripts/rvm";
# suppress error code from last command as we don't care if .rvm doesn't exist.
[ $? -ne 0 ] && echo -n '';

# Python virtualenv
export WORKON_HOME="${HOME}/.virtualenv"
export VIRTUALENVWRAPPER_PYTHON="/usr/bin/python3"
source $(which virtualenvwrapper.sh)

export SDKMAN_DIR="${HOME}/.sdkman"
[[ -s "${HOME}/.sdkman/bin/sdkman-init.sh" ]] && source "${HOME}/.sdkman/bin/sdkman-init.sh"

if ! grep -q 'history' <<<${PROMPT_COMMAND}; then
    export PROMPT_COMMAND="${PROMPT_COMMAND}"$'\n'"history -a"
fi

export NVM_DIR="$HOME/.config/nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"

