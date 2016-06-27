#!/bin/bash
#
# Functionality for working with XML files from the command line
#
# @package profile
# @author  Martin Proffitt <mproffitt@jitsc.co.uk>
# @link    http://www.jitsc.co.uk/
#

##
# Strips all xml tags from a file
#
function stripxml()
{
    file=$1;
    if [ ! -f $file ] ; then
        echo "$file is invalid" >&2;
        exit;
    fi
    sed 's/^[ \t]*//g;s/\<.*\>\(.*\)\<.*\>/\1/g;s/\<\/.*>$//g;s/^\<.*\>//g' $file;
}

