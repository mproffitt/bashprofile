#!/bin/bash
#
# Martin Proffitts bash profile
#
# @package profile
# @author  Martin Proffitt <mproffitt@jitsc.co.uk>
# @link    http://www.jitsc.co.uk/

if [ "$(whoami)" = 'root' ] ; then
    exit 0;
fi

reset;

[ "$TERM" = 'xterm' ] && export TERM='xterm-256color'
[ -z $HOME ] && HOME='/home/'$(whoami);
export HOME=$HOME;

# add application specific <bin> path
[ -d ${HOME}/bin                   ] && PATH="$PATH:${HOME}/bin"
[ -d ${HOME}/src/ZendFramework/bin ] && PATH="$PATH:${HOME}/src/ZendFramework/bin"
[ -d /git/repos/GitTools/bin       ] && PATH="$PATH:${HOME}/git/repos/GitTools/bin"
[ -d /var/lib/gems/1.8/bin         ] && PATH="$PATH:/var/lib/gems/1.8/bin"
[ -d /usr/local/mysql/bin          ] && PATH="$PATH:/usr/local/mysql/bin"
[ -d /usr/local/pear/bin           ] && PATH="$PATH:/usr/local/pear/bin"
[ -d /usr/local/gradle/bin         ] && PATH="$PATH:/usr/local/gradle/bin";
[ -d ${HOME}/.vim/local/bin        ] && PATH="$PATH:${HOME}/.vim/local/bin";
[ -d ${HOME}/bin/jmeter/bin        ] && PATH="$PATH:${HOME}/bin/jmeter/bin"
[ -d /usr/texbin                   ] && PATH="$PATH:/usr/texbin";
[ -d "$HOME/.local/bin"            ] && PATH="$HOME/.local/bin:$PATH"
export PATH=$PATH

# Setup the terminal
export CLICOLOR=1
export LSCOLORS=GxFxCxDxBxegedabagacad
export HISTSIZE=1000
export HISTFILESIZE=2000
export HISTCONTROL=ignoreboth
export EDITOR=vim
export GRADLE_HOME='/usr/local/gradle'
export CLEWNDIR=$HOME/.vim/bundle/pyclewn/macros

for file in $(ls $HOME/.profile | grep -v install) ; do
    if [ -f $HOME/.profile/$file ]  && ! echo $file | grep -q disabled ; then
        source $HOME/.profile/$file;
    fi
done

function _pwd()
{
    local cwd="$(pwd)";
    local prwd="$cwd";
    moduleroot &>/dev/null;
    if [ $? -eq 0 ] ; then
        prwd=$(echo $cwd | sed "s/$(pwd | sed 's/\//\\\//g')\///");
    fi
    echo -ne "\033]0;$(basename `pwd`)\007"
    cd "$cwd";

    echo $(echo $prwd | sed "s/$(echo $HOME | sed 's/\//\\\//g')\//~\//") | sed 's/^[ \t]*//g';
}

function fileEntries()
{
    local entries=$(ls -A | wc -l | awk '{print $1}');
    local hidden=$(( $( ls -A | wc -l ) - $( ls | wc -l)));

    local cmds=('clear' 'resource' 'go' 'goto');
    local found=1;
    case "${cmds[@]}" in *"$cmd"*) found=0; esac;
    if [ $found -eq 1 ] ; then
        echo;
        fill $(($(tput cols)-1)) '=';
        echo;
    fi

    echo $'\e[37m'"$(_pwd): "$'\e[32m'"$entries entries, $hidden hidden."
}

function getPrompt()
{
    local cmd=$(history 1 | awk '{print $2}');
    if ! echo $cmd | grep -qi '^[a-z0-9_-]\+=.*$'; then
        echo $(fileEntries);
        if isGitModule ; then
            echo $(gitBranch)$(getRemoteURL);
        elif isSvnModule ; then
            echo $(svnModule);
        fi
    fi
}

# Setup the prompt
# This is used if powerline is not available
export PS1='$(getPrompt)\n\[\033[35m\]\[\033[1m\D{%d-%m-%y @ %T} (\u)\[\033[00m\]\033[0m\] \$ ';
export PS1='$(getPrompt)\n\033[00m\$ '

if which powerline-daemon &>/dev/null ; then
    powerline-daemon -q
    export POWERLINE_BASH_CONTINUATION=1
    export POWERLINE_BASH_SELECT=1
    export POWERLINE_CONFIG_COMMAND=~/.local/bin/powerline-config

    if [ -f ~/.local/lib/python2.7/site-packages/powerline/bindings/bash/powerline.sh ]; then
        source ~/.local/lib/python2.7/site-packages/powerline/bindings/bash/powerline.sh
    fi
fi

# if tmux exists and is not currently running, load it.
if which tmux &>/dev/null && ! ps aux | grep -v grep | grep -q tmux; then
    tmux;
fi

[[ -d "$HOME/.rvm" ]] && [[ -s "$HOME/.rvm/scripts/rvm" ]] && source "$HOME/.rvm/scripts/rvm";
# suppress error code from last command as we don't care if .rvm doesn't exist.
[ $? -ne 0 ] && echo -n '';

