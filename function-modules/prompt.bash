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
