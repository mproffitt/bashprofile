#!/bin/bash
#
# Additional git functionality
#
# @package profile
# @author  Martin Proffitt <mproffitt@jitsc.co.uk>
# @link    http://www.jitsc.co.uk/
#

_DEFAULT_REMOTE='esspde-gitlab.ssn.hpe.com'

export _GIT_SERVER=$(git config --get host.address || echo $_DEFAULT_REMOTE)
export _GIT_USER=$(git config --get user.username  || whoami)

# Bash scripts to load
if [ -f /usr/local/git/contrib/completion/git-completion.bash ] ; then
    source /usr/local/git/contrib/completion/git-completion.bash;
elif [ "$(uname -o)" = "Cygwin" ] ; then
    if [ ! -f /usr/local/bin/git-prompt.sh ]; then
        cwd=$(pwd);
        cd /usr/local/bin;
        curl -k https://raw.githubusercontent.com/git/git/master/contrib/completion/git-prompt.sh > git-prompt.sh
        chmod +x git-prompt.sh
        cd $cwd;
    fi
    source /usr/share/bash-completion/completions/git;
    source /usr/local/bin/git-prompt.sh
elif [ -f /etc/bash_completion.d/git-prompt ] ; then
    source /etc/bash_completion.d/git-prompt
elif [ -f /usr/share/doc/git/contrib/completion/git-prompt.sh ] ; then
    source /usr/share/doc/git/contrib/completion/git-prompt.sh;
fi

if [ -f /usr/local/bin/git-flow-completion.bash ]; then
    source /usr/local/bin/git-flow-completion.bash;
fi

GIT_BRANCH=''
GIT_TAGGED=$'\u2605';
GIT_PULL=$'\u2193';
GIT_PUSH=$'\u2191';
GIT_STAGED='●';
GIT_UNMERGED='✖';
GIT_CHANGED='✚';
GIT_UNTRACKED=$'…'
GIT_STASHED=$'\u2691';


##
# Used by the __ps1 to determine if the current directory is a git module
#
# @return bool LAST_EXIT_STATUS
#
function isGitModule()
{
    git rev-parse --git-dir &>/dev/null;
}

###
# Opens the root of the current module
#
# @return bool 0 on success
#
function moduleroot()
{
    local wd="$(pwd)";
    while [ ! -d ".git" ]  && [ "$(pwd)" != "/" ] ; do
        cd ..;
    done

    local moduleName=$(basename `pwd`);
    if [ "$moduleName" = "/" ] ; then
        error "Cannot find root directory for current module. Are you sure it's a git repository?" >&2;
        cd "$wd";
        return 1;
    fi
    return 0;
}

##
# Gets the git remote origin url if it exists
#
# @echo string
#
function getRemoteURL()
{
    if isGitModule ; then
        url=$(git config --get remote.origin.url);
        if [ $? -eq 0 ] ; then
            remote=$(dirname "$url");
            echo ' '$'\e[37morigin: '$'\e[33m'"($remote)";
        fi
    fi
}

##
# Used by the __ps1 to determine if the current directory is an SVN module
#
# @return bool LAST_EXIT_STATUS
#
function isSvnModule()
{
    [ -d .svn ] && return 0 || return 1;
}

##
# Finds the root of the current svn module
#
# @echo string The topmost dir containing a .svn directory
#
function svnModuleRoot()
{
    if [ ! -d .svn ] ; then
        echo "Not an svn module";
        return 1;
    fi

    local lastCwd=$(pwd);
    while [ -d .svn ] ; do
        lastCwd=$(pwd);
        cd ..;
    done
    cd $lastCwd;
    return 0;
}

##
# Prints information about the current SVN module
#
# @echo string
#
function svnModule()
{
    local cwd=$(pwd);
    svnModuleRoot &>/dev/null;
    local svnUrl=$(svn info | grep '^URL:' | awk '{print $2}');
    local svnModule=$(
        echo $svnUrl | sed -e "s/$(
            svn info | grep '^Repository Root' | cut -d: -f2- | sed -e 's/^[ \t]*//g' -e 's/\//\\\//g'
        )//g" -e 's/\///' | awk -F\/ '{print $1}'
    );

    echo $'\e[37mSvn module: '$'\e[33m'$svnModule;
    local branch=$(echo $svnUrl | egrep -o '(tags|branches)/[^/]+|trunk' | egrep -o '[^/]+$');
    if [ $? -eq 1 ] ; then
        branch='no branch';
    fi
    echo ' '$'\e[37mbranch: '$'\e[33m'"($branch)";
    cd $cwd;
}

##
# Prints the current git branch
#
# @echo string
#
function gitBranch()
{
    local cwd=$(pwd);

    if git rev-parse --git-dir &>/dev/null ; then
        moduleName=$(basename $(dirname `git rev-parse --git-dir`));
        [ "$moduleName" = '.' ] && moduleName=$(basename `pwd`);
        moduleName=$(echo $moduleName | sed 's/^\.//g');
        git status --branch --porcelain 2>/dev/null | awk -v moduleName="$moduleName" '
            BEGIN {
                ORS="";
                behind=0;
                ahead=0
                staged=0;
                unmerged=0;
                changed=0;
                untracked=0;
            }
            /^##.*/{
                aheadIndex=index($0, "ahead")+length("ahead")+1;
                if (aheadIndex == length("ahead")+1) {
                    ahead=0
                } else {
                    behindIndex=index($0, "behind")+length("behind")+1;
                    if (behindIndex == length("behind")+1) {
                        ahead=substr($0, aheadIndex, (length($0)-aheadIndex));
                    } else {
                        ahead=substr($0, aheadIndex, ((behindIndex-9)-aheadIndex));
                        behind=substr($0, behindIndex, length($0)-behindIndex)
                    }
                }
                branch=substr($0, 4, index($0, "...")-4);
                if (!branch) {
                    "git rev-parse --short HEAD" | getline branch
                }
            }
            /^ ?([MRC]|(D[^D])|(A[^A]))/{
                staged++;
            }
            /^ ?(.?[U])|DD|AA/{
                unmerged++;
            }
            /^ ?((.?M)|([^D]D))/{
                changed++;
            }
            /^ ?[?]/{
                untracked++;
            }
            END {
                print "\033[33mgit:\033[0m ";
                print "module \033[36m"moduleName"\033[0m ";
                print "(\033[32m"branch"\033[0m) ";
                print "\033[33mA\033[0m("ahead") ";
                print "\033[33mB\033[0m("behind") ";
                print "\033[33ms\033[0m("staged") ";
                print "\033[33mu\033[0m("unmerged") ";
                print "\033[33mc\033[0m("changed") ";
                print "\033[33mU\033[0m("untracked") ";
            }'
    fi
    cd $cwd;
}

##
# Checks to see if the current branch requires a merge from origin
#
# @param string $branch The branch to check (default develop)
#
# @return bool TRUE if merge is required
#
function git_requires_merge()
{
    local branch=$1;
    if [ "$1" = "" ] ; then
        branch="develop"
    fi

    local fetch=$(git_do fetch origin 2>&1);
    if [ "$fetch" != "" ] ; then
        echo $fetch | awk -v BRANCH="$branch" '{ for (i=1; i<NF; i++) { if ($i == "origin/"$BRANCH") { exit 0; }} exit 1;}';
        # fetch may have already been done but still requires merge
        if [ $? -eq 1 ] && [ "$(git diff $branch...origin/$branch)" = "" ] ; then
            return $FLAG_FALSE;
        fi
    fi
    return $FLAG_TRUE;
}

##
# Clones a git or svn repository
#
# This function will clone a repository out and cd in to the directory created
#
function clone()
{
    local url="$1";
    local urlWords=$(echo $url | sed 's.[ /:.]. .g; s.  . .g');
    if [ $(echo $urlWords | wc -w | awk '{print $1}') -le 2 ] ; then
        echo "Please enter a valid git URL";
        return 1;
    fi

    echo $url | grep -q 'git';
    if [ $? -eq 0 ] ; then
        git clone $url;
        dir=$(basename $url | sed 's/.git//g');
        [ -d $dir ] && cd $dir;
        return $?;
    fi

    echo $url | grep -q 'svn';
    if [ $? -eq 0 ] ; then
        svn co $url;
        return $?;
    fi
    echo "Unknown repository type at $url";
    return 1;
}

##
# checks out onto a given branch regardless of type (git | svn)
#
# @param string $branch
#
function checkout()
{
    local branch="$1";
    local cwd=$(pwd);
    if isSvnModule ; then
        svnModuleRoot;
        local svnUrl=$(svn info | grep '^URL:' | awk '{print $2}');
        local oldBranch=$(echo $svnUrl | awk -F\/ '{print $NF}');
        local svnUrl=$(echo $svnUrl | sed -e 's/\/branches.*//' -e 's/\/trunk.*//' -e 's/\/tags.*//');
        if [ "$branch" = "trunk" ] ; then
            svn sw ${svnUrl}/trunk;
        else
            echo $(svn ls ${svnUrl}/branches | sed 's/\///') | grep -q $branch;
            if [ $? -eq 0 ] ; then
                svn sw ${svnUrl}/branches/$branch;
            else
                echo "Cloning $oldBranch to $branch";
                svn copy $currentBranchUrl ${svnUrl}/branches/$branch;
            fi
        fi
    elif isGitModule ; then
        git branch -a | grep -q $branch;
        if [ $? -eq 0 ] ; then
            git checkout $branch;
        else
            git checkout -b $branch;
        fi
    fi
}

##
# Updates both the master and develop branches for the current module
#
# @return void
#
function update()
{
    if isGitModule ; then
        branch=$(git rev-parse --abbrev-ref HEAD);
        git checkout master;
        git pull origin master;
        git checkout develop;
        git pull origin develop;
    fi
}

##
# Deletes the given repo
#
# @param string repo The name of the repo to delete
#
# @return void
#
function remove_repo()
{

    inform "Attempting removal of versioned repo from pwd =  `pwd`"
    module=$1;
    while [ ! -d '.git' ] ; do
        cd ..;
    done

    if [ "$(basename `pwd`)" = "$module" ] ; then
        cd ..;
    fi

    dir="$(pwd)/$module";
    inform "Removing $module";
    if [ ! -z $module ] && [ -d $dir ] ; then
        rm -rf $module;
    else
        warn 'Invalid module '$module' - cannot find module directory';
    fi

    inform "Removed $module. Now in `pwd`"
}

##
# Checks all git modules in the current directory have the correct remotes
#
function checkmodules()
{
    local failedModules="";

    fill 80 '#'; echo;
    echo "# 'checkmodule' function";
    echo "# checks modules have the correct remotes and the remote repo exists";
    fill 80 '-'; echo;
    for module in $(ls); do
        if [ ! -d $module ] ; then
            continue;
        fi
        cd $module;
        echo -n $'\e[32m'"# ";
        pad 78 $'\e[33m'$"Checking $module" ' ';
        local _git_remote=$(git remote show origin 2>&1 | tr "\n" "%");
        echo $_git_remote | grep -q '^fatal';
        if [ $? -eq 1 ] ; then
            numRemotes=$(
                echo $_git_remote | tr "%" "\n" | grep -A1 'Fetch URL' |
                sed 's/.*\(\/git\/\).*/\1/g' | wc -l | awk '{print $1}'
            );
            if [ $numRemotes -ge 2 ] ; then
                echo $'\e[32m''[OK]';
            else
                echo $'\e[31m''[FAIL]';
                failedModules="$failedModules|$module";
            fi
        else
            echo $'\e[31m'"[FAIL]";
            failedModules="$failedModules|$module";
        fi
        cd ..;
    done
    fill 80 '#'; echo;
    numErrors=$(echo $failedModules | sed 's/^\|//' | tr '|' "\n" | wc -l | awk '{print $1}');
    if [ $numErrors -gt 0 ] ; then
        echo "# Done but with with failed modules";
        echo "# Failed modules are:";
        fill 80 '-'; echo
        echo $failedModules | sed 's/^\|//' | tr '|' "\n" | sed 's/\(.*\)/# \1/';
        fill 80 '#'; echo;
    fi
}

##
# Fixes the git remotes to point at the correct git origin
#
# @return bool
#
function fixremote()
{
    local wd=$(pwd);
    # make sure we are in the base dir
    echo "Changing back to module root";
    moduleroot;
    if [ $? -eq 0 ] ; then
        moduleName=$(basename `pwd`);
        echo "Updating remote";
        git remote show origin &>/dev/null;
        if [ $? -eq 0 ] ; then
            git remote rm origin;
        fi
        git remote add origin "$_GIT_SERVER:/$_GIT_USER/$moduleName.git";

        echo "Adding $_GIT_USER as remote";
        git remote show $_GIT_USER &>/dev/null;
        if [ $? -eq 0 ] ; then
            git remote rm $_GIT_USER;
        fi
        git remote add $_GIT_USER "$_GIT_SERVER:/$_GIT_USER/$moduleName.git";
    else
        echo "Failed to update remote";
        return 1;
    fi
    cd $wd;
    echo "done";
    return 0;
}
