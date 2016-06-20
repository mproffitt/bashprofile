#!/bin/bash
#
# Function to print a list of all aliases defined in .bash_profile
#
# @package profile
# @author  Martin Proffitt <mproffitt@jitsc.co.uk>
# @link    http://www.jitsc.co.uk/
#

! typeset -f inform &>/dev/null && source "$HOME/.profile/function-parts/common-functions.bash"
##
# Prints a list of all defined aliases
#
# @return LAST_EXIT_STATUS
#
function aliases()
{
    cwd=$(pwd);
    cd ~/.profile;

    for aliasFile in $(grep -r ^alias * | cut -d: -f1 | sort | uniq); do
        echo -n '#' ; fill 79 '#'; echo;
        echo "# From $aliasFile";

        for a in $(cat $aliasFile | grep ^alias | tr ' ' '_') ; do
            line=$(cat $aliasFile | grep -B1 "$(echo $a | tr '_' ' ' | cut -d= -f1)" | head -1);
            echo $line | grep -q '#';
            if [ $? -eq 0 ] ; then
                alias=$(cat $aliasFile | grep -A1 "$line" | tail -1 | cut -d= -f1 | cut -d\  -f2);
                echo "$alias $(fill $((20 - ${#alias})) ' ') $line";
            fi
        done
        echo;
    done
}
