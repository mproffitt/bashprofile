#!/bin/bash
#
# Adds functionality for jumping to a particular location
#
#
# @package profile
# @author  Martin Proffitt <mproffitt@jitsc.co.uk>
# @link    http://www.jitsc.co.uk/
#
# usage:
#   g|go|goto home         -- takes you to your home directory (equiv cd ~/)
#   g|go|goto moduleroot   -- jumps to the top level of a git repo. E.g. if your current
#                             path is "Repo/application/modules/Csv" this function
#                             jumps to "Repo"
#   g|go|goto <moduleName> -- Jumps to a particular module or content directory
#                             e.g. "goto Repo" will take you to ~/src/modules/Repo
#
# Offers tab completion for names previously loaded.
#
# If the location you specified does not exist, this script will ask to find it automatically or
# prompt you to enter the path manually.
#
# If automatic is chosen, the script will then ask if you wish to search from
#
# * root The root of your system
# * home Your home directory
# * Current location
#
# Once a location has been bookmarked in ~/.config/goto then the script changes to that location.
# If the location is identified to be a git repository, it updates the repo by executing
# $(git fetch -p) after first checking that the origin is available
#
# LINUX ONLY
# If a .sshfs.conf file exists, the script will attach a remote filesystem using SSHFS
# See https://github.com/libfuse/sshfs
#

_ORIGIN='';
_GOTO_PATH="$HOME/.config/goto"

! typeset -f inform &>/dev/null && source "$HOME/.bashprofile/function-parts/common-functions.bash"
! typeset -f moduleroot &>/dev/null && source "$HOME/.bashprofile/function-parts/git-helpers.bash"

[ ! -d "$_GOTO_PATH" ] && mkdir -p "$_GOTO_PATH";

##
# Creates a link from the current location in the ~/.config/goto folder
#
# If current directory is inside a version controlled repo, links from the module root
#
function goto_link()
{
    cwd=$(pwd)
    cd $1
    moduleroot &>/dev/null;
    dirname=$(basename $(pwd))
    if [ ! -f "$_GOTO_PATH/$dirname" ]; then
        inform "Linking $dirname in $_GOTO_PATH";
        ln -s $(pwd) "$_GOTO_PATH/"
    fi
    cd $cwd
}

##
# Asks the user to enter a path then checks that it exists
#
function enter_path()
{
    inform -n "path > ";
    read path;
    if [ "${path::1}" != '/' ] ; then
        path=$(pwd)/$path;
    fi
    local cwd=$(pwd);
    if ! cd $path &>/dev/null ; then
        error "Path $path does not exist";
        cd $cwd;
        path=$(enter_path);
    fi
    cd $cwd;
    echo $path;
}

##
# Automatically tries to find a given location
#
# Does not look in hidden directories
#
function find_path()
{
    local root=''
    from=$(query "From [r]oot, [c]urrent dir or [h]ome" 'r' 'c' 'h');
    case $from in
        'r')
            root='/'
        ;;
        'c')
            root=$(pwd)
        ;;
        'h')
            root=$HOME
        ;;
    esac
    location=$(find -P $root -maxdepth 5 -type d -name "$1" -not -path '*/\.*' 2>/dev/null | sed 's/^\.\///' | head -1);
    if [ -z $location ]; then
        warn "$1 could not be found under $root";
        echo $(enter_path)
        return
    fi
    inform "found path '$location'"
    answer=$(query "is this correct? > " y n)
    if [ $answer = 'n' ]; then
        echo $(enter_path)
    fi
    echo "$location";
}

function get_module_origin()
{
    origin=$(git config --get remote.origin.url);
    [ "$(echo $origin | cut -d: -f1)" = 'git' ] && origin=$_ORIGIN;
    [ "$(echo $origin | cut -d: -f1)" = "$_ORIGIN" ] && origin=$_ORIGIN;
    [ "$(echo $origin | cut -d@ -f1)" = 'git' ] && origin="$(echo $origin | cut -d@ -f2 | cut -d: -f1)";
    [ "$(echo $origin | cut -d: -f1)" = 'ssh' ] && origin="$(echo $origin | cut -d@ -f2 | cut -d\/ -f1)";
    [[ $(echo $origin | cut -d: -f1) =~ ^http ]] && origin="$(echo $origin | sed 's/http[s]*:\/\///g' | cut -d\/ -f1)";
    echo $origin;
}

##
# loads an ssh file-system if it exists
#
# if the given location contains a .sshfs.config file
# it will be passed as options to sshfs
#
# this can be useful for mounting ssh file systems
#
function _load_sshfs()
{
    local location=$1;
    if [ -f "$location/.sshfs.config" ]; then
        inform "Mounting remote file system";
        sshfs -o nonempty $(cat $location/.sshfs.config) $location
    fi
}

##
# Unload an sshfs filesystem
#
function unload()
{
    local cwd=$(pwd)
    local location=$(readlink -e $_GOTO_PATH/$1)
    if grep -q $location <(grep 'fuse.sshfs.*user_id='$(id -u) /etc/mtab | cut -d\  -f2); then
        # this is a mount point and it is owned by us
        fusermount -u $location &>/dev/null;
        if [ $? -ne 0 ] ; then
            cd "$location/../"
            fusermount -u $location &>/dev/null;
        fi
    fi
    cd $cwd &>/dev/null
    if [ $? -ne 0 ] ; then
        cd "$location/../";
    fi
}

##
# Opens a particular location on your machine
#
# @param $location string The location to open
#
# @return 0 on success
#
# The location can be one of "home", "moduleroot" or a location
# listed in bash variable "$_DIR_LIST".
#
# Type "echo $_DIR_LIST" for quick locations.
# Tab complete is available.
#
function goto () {
    clear;
    local retVal=0;
    local dir;

    case "$1" in
    home|$HOME)
        cd ~;
    ;;
    moduleroot)
        moduleroot;
        retVal=$?;
    ;;
    *)
        local location=$1
        if ! [[ -L "$_GOTO_PATH/$1" && -d "$_GOTO_PATH/$1" ]] ; then
            inform "$1 has not been linked before"
            answer=$(query "do you wish to locate it? [a]utomatic, [m]anual" a m);
            case $answer in
                "a")
                    path=$(find_path $location)
                    goto_link $path
                ;;
                "m")
                    path=$(enter_path)
                    goto_link $path
                ;;
            esac

        fi

        location=$(readlink -e $_GOTO_PATH/$location)
        _load_sshfs $location
        cd $location &>/dev/null;

        if [ -d .git ]; then
            origin=$(get_module_origin)
            echo "checking $origin is online";
            online=1;
            which fping &>/dev/null;
            if [ $? -ne 1 ] ; then
                fping -c1 $origin &>/dev/null;
                online=$?;
            else
                ping -c1 $origin &>/dev/null;
                online=$?;
            fi
            if [ $online -eq 1 ] ; then
                # maybe ping is turned off - try http
                curl -k https://$origin &>/dev/null
                [ $? -eq 0 ] && online=0 || online=2
            fi

            if [ $online -eq 0 ] ; then
                echo "Updating repo...";
                git fetch -p origin;
                clear;
            else
                echo "origin $origin is not available. skipping update" >&2;
                clear;
            fi
        fi
    ;;
    esac
}

##
# Completion function for goto method
#
_goto_complete () {
    COMPREPLY=();
    local cur="${COMP_WORDS[COMP_CWORD]}";
    COMPREPLY=( $(compgen -S ' ' -W "home moduleroot $(ls $_GOTO_PATH)" -- ${cur}) );
}

##
# Shortcut for the goto function
#
alias g='goto';

##
# Shortcut for the goto function
#
alias go='goto';

##
# shortcut for linking for goto
#
alias gl='goto_link'

complete -o default -F _goto_complete g
complete -o default -F _goto_complete go
complete -o default -F _goto_complete goto
