#!/bin/bash

##
# Runs a single python test case
#
# @param suppress string [optional] Suppress output from nosetests
# @param testcase string            The name of the testcase to execute
#
function pt()
{
    suppress=''
    if [ "$1" = 's' ] ; then
        suppress='-s'
        shift
    fi

    if [ "$1" = "" ] ; then
        echo "Arguments required for nosetests"
        return 1
    fi
    packages=$(sed '/package/,/\]/!d;/package/d;/\]/d;s/^\s\+//g;' setup.py | sed ':a;N;$!ba;s/\n//g' | tr -d \')
    nosetests-3.4 --with-coverage --cover-branches --cover-package=$packages $suppress $(find -P . -name test_${1}.py | sed 's/\.\///')
}

##
# Runs all found test cases in the current python module
#
# @param arguments string Additional arguments to pass to nosetests
#
function pytest()
{
    if [ "$1" == '' ] ; then
        echo "Arguments required for nosetests"
        return 1
    fi

    rm -f .coverage
    rm -rf cover

    find -P . -name *.pyc -exec rm -f {} \;
    clear;
    python3 setup.py nosetests -s --with-coverage --cover-branches --cover-html --cover-package "$@"
}

##
# Runs pylint over the provided package
#
function pylint()
{
    report=''
    if [ "$1" = 'r' ] ; then
        report=' -r n'
        shift;
    fi

    if [ "$1" = '' ] ; then
        echo "Please provide a package name"
        return 1
    fi
    clear;

    $(which pylint) $report "$1"
}

##
# Deletes all python cache and object files from the current module
#
function pyclean()
{
    if [ ! -d .git ] ; then
        echo "Must be run from git module root" 1>&2
        return 1;
    fi
    if [ -d cover ] ; then
        rm -rf cover;
    fi
    find -P . -type d -name __pycache__ -exec rm -rf {} \;
    find -P . -name *.pyc -exec rm -f {} \;
}

##
# Upgrades all pip modules which are out of date
#
function pyupgrade()
{
    #sudo -H pip list --outdated --format=freeze | cut -d= -f1  | xargs -n1 sudo -H pip install --upgrade
    sudo -H pip3 list --outdated --format=freeze | cut -d= -f1  | xargs -n1 sudo -H pip3 install --upgrade
}

##
# Builds/packages the current python application
#
function pybuild()
{
    local repository=''
    if [ ! -z "$1" ] ; then
        case "$1" in
            's')
                ;&
            'snapshots')
                repository="$(grep '\[.*snapshots\]' ~/.pypirc | sed 's/\[//;s/\]//')"
                ;;
            'r')
                ;&
            'releases')
                repository="$(grep '\[.*releases\]' ~/.pypirc | sed 's/\[//;s/\]//')"
                ;;
            *)
                repository="$1"
                ;;
        esac
    fi
    python3 setup.py sdist upload -r $repository
}
