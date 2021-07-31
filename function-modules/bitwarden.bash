#!/bin/bash

function bwpass()
{
    (set -o pipefail && bwdetail $@ | jq -r .login.password)
}

function bwuser()
{
    (set -o pipefail && bwdetail $@ | jq -r .login.username)
}

function __bwargs()
{
    local path=''
    local credential=''
    local attrib=''
    local clip=''
    while [[ $# -gt 0 ]]; do
        if [ "$1" == '-x' ]; then
            clip='-x'
            shift
            continue
        fi

        if grep -swq $1 <<<"$(bw list folders | jq -r .[].name | sort | uniq)"; then
            path=$1
        elif grep -swq $1 <<<"$(bw list items | jq -r .[].name | sort | uniq)"; then
            credential="$1"
        else
            attrib=$1
        fi
        shift
    done

    if [ -z "${path}" ] && [ -z "${credential}" ] && grep -q '/' <<<${attrib}; then
        if grep -swq $(basename ${attrib}) <<<"$(bw list items | jq -r .[].name | sort | uniq)"; then
            credential=$(basename ${attrib})
            path=$(dirname ${attrib})
            attrib=''
        else
            local tmp=$(basename ${attrib})
            attrib=$(dirname ${attrib})
            if grep -swq $(basename ${attrib}) <<<"$(bw list items | jq -r .[].name | sort | uniq)"; then
                credential=$(basename ${attrib})
                path=$(dirname ${attrib})
                attrib=${tmp}
            else
                path=$(dirname $(dirname ${attrib}))
                credential=$(basename $(dirname ${attrib}))
                attrib=$(basename ${attrib})
            fi
        fi
    fi
    echo "([path]=${path} [credential]=${credential} [attrib]=${attrib} [clip]=${clip})"
}

function bwattr()
{
    declare -A dict="$(__bwargs $@)"
    bwdetail "${dict[path]}" "${dict[credential]}" "${dict[clip]}" | jq -r ".${dict[attrib]}"
}

function bwdetail()
{
    bw sync &>/dev/null
    declare -A dict="$(__bwargs $@)"
    local folderId=$(bw list folders --search "${dict[path]}" | jq -r '.[].id')
    if [ -z "${folderId}" ]; then
        error "Invalid path name"
        return 1
    fi

    local value=$(bw list items --folderid ${folderId} | jq -r '.[] | select(.name == "'${dict[credential]}'")')
    [ ${#value} != 0 ] || { error "Not found" ; return 1; }
    if [ "${dict[clip]}" == '-x' ]; then
        xclip -sel clip <<<${value}
    else
        echo ${value}
    fi
}

function bwattachment()
{
    local details="$(bwdetail $@)"
}
