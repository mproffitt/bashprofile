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

    /usr/bin/pylint $report "$1"
}

##
# Deletes all python cache and object files from the current module
#
function pyclean()
{
    if [ ! -d .git ] ; then
        echo "Must be run from git module root" 1>&2
        exit 1;
    fi
    if [ -d cover ] ; then
        rm -rf cover;
    fi
    find -P . -type d -name __pycache__ -exec rm -rf {} \;
    find -P . -name *.pyc -exec rm -f {} \;
}

