#!/bin/bash
#
# Function to print a list of all aliases defined in .bash_profile
#
# @package profile
# @author  Martin Proffitt <mproffitt@jitsc.co.uk>
# @link    http://www.jitsc.co.uk/
#

! typeset -f inform &>/dev/null && source "$HOME/.bashprofile/function-modules/common-functions.bash"

##
# Prints a list of all defined aliases
#
# @return LAST_EXIT_STATUS
#
function aliases()
{
    cwd=$(pwd);
    cd ~/.bashprofile;

    for aliasFile in $(grep -r ^alias * | cut -d: -f1 | sort | uniq); do
        echo -n '#' ; fill 79 '#'; echo;
        if echo $aliasFile | grep -q disabled; then
            echo ${RED}'# Functionality DISABLED in '$aliasFile$RESET
        else
            echo "# From $aliasFile";
        fi

        for a in $(cat $aliasFile | grep ^alias | tr ' ' '_') ; do
            line=$(cat $aliasFile | grep -B1 "$(echo $a | tr '_' ' ' | cut -d= -f1)" | head -1);
            echo $line | grep -q '#';
            if [ $? -eq 0 ] ; then
                alias=$(cat $aliasFile | grep -A1 "$line" | tail -1 | cut -d= -f1 | cut -d\  -f2);
                echo "$alias $(fill $((20 - ${#alias})) ' ') $line";
            fi
        done
        echo;
    done | less -R;
    cd $cwd;
}

##
# Lists available functions
#
# @return LAST_EXIT_STATUS
#
function functions()
{
    local cwd=$(pwd);
    cd ~/.bashprofile;

    _functions=($(grep -r '^function' * | cut -d: -f1 | sort | uniq));

    for file in ${_functions[@]}; do
        echo -n '#'; fill 125 '#'; echo;
        if echo $aliasFile | grep -q disabled; then
            echo '# '${RED}DISABLED${RESET} in $aliasFile
        else
            echo "# From $file";
        fi

        oldIFS=$IFS; IFS=$'\n';
        for line in $(
            sed -n '/^##/{g;N;p;};/^function/p;' $file |
            sed 's/()//g; /^$/d; s/^function //g; s/ //; s/#/# /' |
            sed '1!G;h;$!d;' |
            sed 'N;s/\n/,/g'
        ); do
            func=$(echo $line | cut -d, -f1);
            desc=$(echo $line | cut -d, -f2-);
            if echo $func | grep -vq '^_'; then
                pad 35 "$func" ' '; echo $desc;
            fi
        done
        IFS=$oldIFS;
        echo;
    done | less -R;
    cd $cwd;
}

