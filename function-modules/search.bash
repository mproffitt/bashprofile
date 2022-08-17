#!/bin/bash
#
# Adds dictionary search functionality to a bash shell.
#
# @package profile
# @author  Martin Proffitt <mproffitt@choclab.net>
# @link    http://www.choclab.net/#
#
# This script uses rhymezone.com to search for rhymes and definitions of words.
# It was developed to aid in the writing of poetic verse because I prefer to avoid
# using the browser too much when writing and I spend pretty much all my time
# in the vim editor.
#
# Functions:
# ==========
#
# rhymes [-n] <word>                   : Search for rhyming words. If -n is given, near rhymes are returned.
# define <word>                        : Define a word
# synonyms [-r] <word>                 : Find synonyms for a word. If -r is given, related words are returned instead
# antonyms <word>                      : Find antonyms for a word.
#
# [s|search] -[r|d|s|a] [-n|-r] <word> : Wrapper function for all the above.
#
# NOTE: This script is known to fail if pages are compressed in transit. Can often happen
#       if a HTTP proxy is in the way.
#

##
# Gets a list of words which rhyme with a given word
#
function rhymes()
{
    local t='perfect';
    local word="";
    if [ "$1" = '-n' ] ; then
        t='nry';
        shift;
    fi

    [ -z $1 ] && { echo "<word> is required" && return 1; };
    word=$1;
    oldIFS=$IFS;
    IFS=$'\n';
    list=$(curl -Ls "http://www.rhymezone.com/r/rhyme.cgi?Word=$word&typeofrhyme=$t"                           |
        sed -n 's/<[^>]*>//g;/^$/d; /1\ syllable\:/,$p;'                                                      |
        sed '/Words\ and\ phrases\ that\ almost\ rhyme\:/,$d; /function\ logfeed/,$d; s/&nbsp;/ /g; s/, /|/g' |
        sed "s/^\([0-9].*\)/\\`echo -e '\n\r'`\1\\`echo -e '\n\r'`------------/g"                             |
        sed '/var\ rz_snippets/,$d';
    );

    if echo $list | grep -q 'Sorry no results' ||
        [ $(echo $list | wc -w | awk '{print $1}') -eq 0 ];
    then
        IFS=$oldIFS;
        echo "Sorry. No $( [ $t = 'nry' ] && echo 'near ' )rhymes found for '$word'";
        return 1;
    fi

    local i=0;
    for line in $list; do
        if echo $line | grep -q '|$' && [ $i -le 6 ] ; then
            echo -n "$(echo $line | tr -d '|'), ";
            i=$(($i + 1));
        else
            echo $line | grep -q '^\r[0-9].*' && echo;
            echo $line | tr -d '|';
            i=0;
        fi
    done;
    IFS=$oldIFS;
    echo;
}

##
# Gets the definition of a word
#
function define()
{
    local word="";
    [ -z $1 ] && { echo "<word> is required" && return 1; };
    word=$1;
    oldIFS=$IFS;
    IFS=$'\n';
    list=$(curl -Ls "http://rhymezone.com/r/rhyme.cgi?Word=$word&typeofrhyme=def" |
        sed -n 's/<[^>]*>//g;/^$/d;/^Definitions\ of/,$p'                        |
        sed '/Related\ words/,$d; /Search for/,$d; s/&nbsp;/ /g;'
    );

    if echo $list | grep -q 'Sorry' ||
        [ $(echo $list | wc -w | awk '{print $1}') -eq 0 ];
    then
        IFS=$oldIFS;
        echo "Sorry. No definitions found for '$word'";
        return 1;
    fi

    for line in $list; do
        echo $line;
    done;
    IFS=$oldIFS;
    echo;
}

##
# Gets synonyms of a given word
#
function synonyms()
{
    local word="";
    local t='syn';
    if [ "$1" = '-r' ] ; then
        t='rel';
        shift;
    fi

    [ -z $1 ] && { echo "<word> is required" && return 1; };
    word=$1;
    oldIFS=$IFS;
    IFS=$'\n';

    if [ "$t" = 'syn' ] ; then
        list=$(curl -Ls "http://rhymezone.com/r/rhyme.cgi?Word=$word&typeofrhyme=syn" |
            sed -n 's/<[^>]*>//g;/^$/d;/^Words\ and\ phrases/,$p'                    |
            sed '/Want\ more\ ideas/,$d; s/&nbsp;/ /g; /(.*)/d; s/, /|/g'            |
            sed "/Antonyms.../d; s/^\(Words.*\)/\1\\`echo -e '\n\r'`/";
        );
    else
        list=$(curl -Ls "http://rhymezone.com/r/rhyme.cgi?Word=$word&typeofrhyme=rel" |
            sed -n 's/<[^>]*>//g;/^$/d;/^Words\ and\ phrases/,$p'                    |
            sed '/Appears\ in\ the/,$d; s/&nbsp;/ /g; /(.*)/d; s/, /|/g'            |
            sed "s/\(.*:\)/\\`echo -e '\n\r'`\1\\`echo -e '\n\r'`-------------------------------/g" |
            sed '/Words\ and\ phrases.*/{n;$!d;}';
        );
    fi

    if echo $list | grep -q 'Sorry' ||
        [ $(echo $list | wc -w | awk '{print $1}') -eq 0 ];
    then
        IFS=$oldIFS;
        echo "Sorry. No $( [ $t = 'rel' ] && echo 'related words' || echo 'synonyms' ) found for '$word'";
        return 1;
    fi

    local i=0;
    for line in $list; do
        if echo $line | grep -q '|$' && [ $i -le 6 ] ; then
            echo -n "$(echo $line | tr -d '|'), ";
            i=$(($i + 1));
        else
            echo $line | grep -q '^\r.*:' && echo;
            echo $line | tr -d '|';
            i=0;
        fi
    done;
    IFS=$oldIFS;
    echo;
}

##
# Gets antonyms of a word
#
function antonyms()
{
    local word="";
    [ -z $1 ] && { echo "<word> is required" && return 1; };
    word=$1;

    oldIFS=$IFS;
    IFS=$'\n';
    list=$(curl -Ls "http://rhymezone.com/r/rhyme.cgi?Word=$word&typeofrhyme=ant" |
        sed -n 's/<[^>]*>//g;/^$/d;/^Words\ and\ phrases/,$p'                    |
        sed '/Commonly\ searched/,$d; s/&nbsp;/ /g; /(.*)/d; s/,//g'             |
        sed "s/^\(Words.*\)/\1\\`echo -e '\n\r'`/";
    );

    if echo $list | grep -q 'Sorry no results' ||
        [ $(echo $list | wc -w | awk '{print $1}') -eq 0 ];
    then
        IFS=$oldIFS;
        echo "Sorry. No antonyms found for '$word'";
        return 1;
    fi

    local i=0;
    for line in $list; do
        if echo $line | grep -q '|$' && [ $i -le 6 ] ; then
            echo -n "$(echo $line | tr -d '|'), ";
            i=$(($i + 1));
        else
            echo $line | tr -d '|';
            i=0;
        fi
    done;
    IFS=$oldIFS;
    echo;
}

##
# How to use the search script
#
function search_usage()
{
    echo 'Usage: search -[r|d|s|a] [-n|-r] <word>' >&2;
    echo '    -r Search for rhyming words.'        >&2;
    echo '    -d Search for definition of a word.' >&2;
    echo '    -s Search for synonyms of a word.'   >&2;
    echo '    -a Search for antonyms of a word.'   >&2;
    echo;
    echo '-r takes an optional flag -n (search for near rhymes).'   >&2;
    echo '-s takes an optional flag -r (search for related words).' >&2;
    echo;
}

##
# Search wrapper
#
function search()
{
    if [ $# -eq 0 ] ; then
        search_usage;
        return 1;
    fi

    local action='';
    local subaction='';
    local word='';

    case $1 in
        '-r')
            action='rhymes';
        ;;
        '-d')
            action='define';
        ;;
        '-s')
            action='synonyms';
        ;;
        '-a')
            action='antonyms';
        ;;
        *)
            echo "Error: Invalid action defined $1" >&2;
            search_usage;
            return 2;
        ;;
    esac

    case $2 in
        '-n')
            [ "$action" != 'rhymes' ] && { echo "Error: Invalid subaction defined for $action" >&2 && search_usage && return 3; };
            subaction='-n';
        ;;
        '-r')
            [ "$action" != 'synonyms' ] && { echo "Error: Invalid subaction defined for $action" >&2 && search_usage && return 3; };
            subaction='-r';
        ;;
        *)
            if echo $2 | grep -q '^-'; then
                echo "Invalid subaction defined for $action." >&2;
                search_usage;
                return 3;
            fi
            word=$2;
        ;;
    esac

    if [ -z $word ]; then
        if [ ! -z $3 ] ; then
            word=$3;
        else
            echo "Error: <word> is required";
            search_usage;
            return 1;
        fi
    fi

    string='';
    if [ "$action" = 'rhymes' ] ; then
        if [ ! -z $subaction ] ; then
            string='near rhymes for';
        else
            string='rhymes for';
        fi
    elif [ "$action" = 'synonyms' ] ; then
        if [ ! -z $subaction ] ; then
            string='words related to';
        else
            string='synonyms for';
        fi
    elif [ "$action" = 'define' ] ; then
        string='definitions of';
    else
        string='antonyms for';
    fi

    echo "Finding $string $word";
    eval "$action $subaction $word";
    return $?;
}

