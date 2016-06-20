#!/bin/bash
#
# Contains common functions for sharing between scripts
#
# @package profile
# @author  Martin Proffitt <mproffitt@jitsc.co.uk>
# @link    http://www.jitsc.co.uk/
#

RED=$(echo $'\033[31m');
GREEN=$(echo $'\033[32m');
YELLOW=$(echo $'\033[33m');
BLUE=$(echo $'\033[34m');
MAGENTA=$(echo $'\033[35m');
CYAN=$(echo $'\033[36m');
WHITE=$(echo $'\033[37m');

RESET=$(echo $'\033[00m');

BOLD=$(tput bold);
NORMAL=$(tput sgr0)

##
# Kill the script if a problem occurs
#
# @param string message - The reason the script died
#
# @return 0
#
# This function exits with an exist status of 1 if
# a problem has occurred.
#
function fatal()
{
    echo "$RED[FATAL]$RESET $@" 1>&2;
}

##
# Print informational messages
#
# @param string
#
# @return void
#
function inform()
{
    if [ "$1" = '-n' ] ; then
        shift
        echo -n "$WHITE[INFO]$RESET $@" 1>&2;
    else
        echo "$WHITE[INFO]$RESET $@" 1>&2;
    fi
}

##
# Print debug messages
#
# @param string
#
# @return void
#
function debug()
{
    echo "$CYAN[DEBUG]$RESET $@" 1>&2;
}

##
# Print warning messages
#
# @param string
#
# @return void
#
function warn()
{
    echo "$YELLOW[WARNING]$RESET $@" 1>&2;
}

##
# Prints error messages
#
# @param string
#
# @return void
#
function error()
{
    echo "$RED[ERROR]$RESET $@" 1>&2;
}

##
# Asks for an answer from the user
#
# @param message string
# @param ...     options
#
# @return void
#
# This method asks for an answer from the user then
# echo's their response in lowercase
#
# It is the responsibility of the calling function
# to parse the response
#
# If an invalid response is provided, the method
# recursively calls itself until a correct option
# is selected.
#
# @example
# response=$(query "Please give a yes or no answer" y n)
# case $response in
#     y) echo True;;
#     n) echo False;;
# esac
#
function query()
{
    message="$1";
    shift
    options="$@";

    inform -n "$message [$options] > ";
    read answer;
    if [ -z "$answer" ] || ! echo $options | grep -qi $answer ; then
        error "Invalid option selected"
        answer=$(query "$message" $options)
    fi
    echo $answer | tr "[:upper:]" "[:lower:]"
}

##
# executes the given command printing the command to be executed
#
# @param string
#
# @return void
#
function exec_command()
{
    inform "Executing $@";
    eval "$@";
}

##
# echos the command as if it were being run
#
# @param string
#
# @return void
#
function echo_command()
{
    inform "Executing $@";
    echo "$@";
}

##
# Fills the line with characters to column
#
# @param count     int
# @param character string
#
# This method does not print a newline character
#
function fill ()
{
    FILL="${2:- }"
    for ((c=0; c<=$1; c+=${#FILL}))
    do
        echo -n "${FILL:0:$1-$c}"
    done
}

##
# Pads the line with characters
#
# @param count     int    Number of characters to pad the line with
# @param character string The character to pad with
# @param message   string A message to add after the pad.
#
# This method does not print a newline character
#
function pad ()
{
    BACK=$(fill $1 "$3")
    let PAD=$1-${#2}
    if [ $PAD -lt 1 ]
    then
        echo -n ${2:0:$1-1}
    else
        echo -n "$2${BACK:${#2}}"
    fi
}
