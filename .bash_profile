#!/bin/bash
#
# Martin Proffitts bash profile
#
# @package bashprofile
# @author  Martin Proffitt <mproffitt@jitsc.co.uk>
# @link    http://www.jitsc.co.uk/

##
# Do not load if we're logging in as root, or if we're not in an
# interactive session.
if [ "$(whoami)" = 'root' ] || ! echo $- | grep -q i; then
    return;
fi
reset;

title=""

cat << EOF
*******************************************************************************
Please wait whilst I load the profile...

@package: BashProfile
@author : Martin Proffitt <mproffitt@jitsc.co.uk>
@license: GNU GPL V3 or later
*******************************************************************************
EOF

[ "$TERM" = 'xterm' ] && export TERM='xterm-256color'
[ -z $HOME ] && HOME='/home/'$(whoami);
export HOME=$HOME;

# add application specific <bin> path
[ -d ${HOME}/bin                   ] && PATH="${HOME}/bin:$PATH"
[ -d ${HOME}/src/ZendFramework/bin ] && PATH="$PATH:${HOME}/src/ZendFramework/bin"
[ -d /git/repos/GitTools/bin       ] && PATH="$PATH:${HOME}/git/repos/GitTools/bin"
[ -d /var/lib/gems/1.8/bin         ] && PATH="$PATH:/var/lib/gems/1.8/bin"
[ -d /usr/local/mysql/bin          ] && PATH="$PATH:/usr/local/mysql/bin"
[ -d /usr/local/pear/bin           ] && PATH="$PATH:/usr/local/pear/bin"
[ -d /usr/local/gradle/bin         ] && PATH="$PATH:/usr/local/gradle/bin"
[ -d ${HOME}/.vim/local/bin        ] && PATH="$PATH:${HOME}/.vim/local/bin"
[ -d ${HOME}/bin/jmeter/bin        ] && PATH="$PATH:${HOME}/bin/jmeter/bin"
[ -d /usr/texbin                   ] && PATH="$PATH:/usr/texbin"
[ -d ${HOME}/.local/bin            ] && PATH="$HOME/.local/bin:$PATH"
[ -d /usr/local/cuda/bin           ] && PATH="$PATH:/usr/local/cuda/bin"
[ -d /usr/local/go/bin             ] && PATH="$PATH:/usr/local/go/bin"
[ -d ${HOME}/work/bin              ] && PATH="$PATH:${HOME}/work/bin"
[ -d /opt/mssql-tools/bin          ] && PATH="$PATH:/opt/mssql-tools/bin"
[ -d ${HOME}/.bashprofile/bin      ] && PATH="$PATH:${HOME}/.bashprofile/bin"

# Windows specific paths
if [ "$(uname -o)" = 'Cygwin' ] ; then
    [ -d '/cygdrive/c/Program Files (x86)/MSBuild/14.0/Bin' ] && PATH=$PATH':/cygdrive/c/Program Files (x86)/MSBuild/14.0/Bin'
fi

export PATH=$PATH

# Setup the terminal
export CLICOLOR=1
export LSCOLORS=GxFxCxDxBxegedabagacad
export HISTSIZE=10000
export HISTFILESIZE=2000
export HISTCONTROL=ignoreboth
export EDITOR=vim
export GRADLE_HOME='/usr/local/gradle'
export CLEWNDIR=$HOME/.vim/bundle/pyclewn/macros

export GOPATH="$HOME/work"
export JAVA_HOME="/usr/lib/jvm/java-8-oracle"

for file in $(ls $HOME/.bashprofile | grep -v 'install\|README') ; do
    if [ -f $HOME/.bashprofile/$file ]  && ! echo $file | grep -q disabled ; then
        source $HOME/.bashprofile/$file;
    fi
done

##
# Gets the current working directory, changing the users home for ~ unless the current
# directory IS the users home.
#
function _pwd()
{
    local cwd="$(pwd)";
    local prwd="$cwd";
    moduleroot &>/dev/null;
    if [ $? -eq 0 ] ; then
        prwd=$(echo $cwd | sed "s/$(pwd | sed 's/\//\\\//g')\///");
    fi
    cd "$cwd";

    echo $(echo $prwd | sed "s/$(echo $HOME | sed 's/\//\\\//g')\//~\//") | sed 's/^[ \t]*//g';
}

##
# Lists the number of files in the current directory
#
function fileEntries()
{
    local entries=$(ls -A | wc -l | awk '{print $1}');
    local hidden=$(( $( ls -A | wc -l ) - $( ls | wc -l)));

    echo -n $'\e[1m\e[31m'$(hostname)$'\e[0m'' : '
    echo $'\e[37m'$(_pwd): $'\e[32m'$entries entries, $hidden hidden.$'\e[0m'
}

##
# Gets a prompt line for SSHSF
#
function sshfsPrompt()
{
    if grep -q "$(pwd)[^/]" /etc/mtab; then
        echo $'\e[37msshfs: \e[0m'$(grep $(pwd) /etc/mtab | cut -d\  -f1)
    fi
}

##
# Gets the shell prompt
#
function getPrompt()
{
    fileEntries;
    if isGitModule ; then
        echo $(gitBranch);
    elif isSvnModule ; then
        echo $(svnModule);
    fi
    if [ "$(uname -o)" != 'Cygwin' ] ; then
        sshfsPrompt
    fi
}

if which powerline-daemon &>/dev/null && [ ! -f ${HOME}/.bashprofile/function-modules/powerline.disabled ]; then
    powerline-daemon -q
    export POWERLINE_BASH_CONTINUATION=1
    export POWERLINE_BASH_SELECT=1
    export POWERLINE_CONFIG_COMMAND=~/.local/bin/powerline-config

    if [ -f ~/.local/lib/python2.7/site-packages/powerline/bindings/bash/powerline.sh ]; then
        source ~/.local/lib/python2.7/site-packages/powerline/bindings/bash/powerline.sh
    fi
else
    PS1='$(getPrompt)\n\[\033[00m\]\$ '
fi

SSH_ENV="$HOME/.keychain/${HOSTNAME}-sh"
function startAgent() {
    inform "Initialising new SSH agent..."
    for file in $(ls ${HOME}/.ssh | grep rsa | grep -v '\.pub$'); do
        /usr/bin/keychain ${HOME}/.ssh/$file &>/dev/null
    done
    source "${SSH_ENV}" > /dev/null
}

# Start the key agent before starting TMUX
if [ -f "${SSH_ENV}" ]; then
     source "${SSH_ENV}" > /dev/null
     if ! ps -ef | grep -v grep | grep ${SSH_AGENT_PID} > /dev/null; then
         startAgent;
     fi
else
     startAgent;
fi

# Do not run tmux if we are running cygwin - it's hellishly slow.
if [ "$(uname -o)" != 'Cygwin' ]; then
    # if tmux exists and is not currently running, load it.
    if which tmux &>/dev/null && ! ps aux | grep -v grep | grep -q tmux; then
        tmux;
    fi
fi

[[ -d "$HOME/.rvm" ]] && [[ -s "$HOME/.rvm/scripts/rvm" ]] && source "$HOME/.rvm/scripts/rvm";
# suppress error code from last command as we don't care if .rvm doesn't exist.
[ $? -ne 0 ] && echo -n '';

#THIS MUST BE AT THE END OF THE FILE FOR SDKMAN TO WORK!!!
export SDKMAN_DIR="${HOME}/.sdkman"
[[ -s "${HOME}/.sdkman/bin/sdkman-init.sh" ]] && source "${HOME}/.sdkman/bin/sdkman-init.sh"
