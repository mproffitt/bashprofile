# bash completion for opsctl                               -*- shell-script -*-

__opsctl_debug()
{
    if [[ -n ${BASH_COMP_DEBUG_FILE:-} ]]; then
        echo "$*" >> "${BASH_COMP_DEBUG_FILE}"
    fi
}

# Homebrew on Macs have version 1.3 of bash-completion which doesn't include
# _init_completion. This is a very minimal version of that function.
__opsctl_init_completion()
{
    COMPREPLY=()
    _get_comp_words_by_ref "$@" cur prev words cword
}

__opsctl_index_of_word()
{
    local w word=$1
    shift
    index=0
    for w in "$@"; do
        [[ $w = "$word" ]] && return
        index=$((index+1))
    done
    index=-1
}

__opsctl_contains_word()
{
    local w word=$1; shift
    for w in "$@"; do
        [[ $w = "$word" ]] && return
    done
    return 1
}

__opsctl_handle_go_custom_completion()
{
    __opsctl_debug "${FUNCNAME[0]}: cur is ${cur}, words[*] is ${words[*]}, #words[@] is ${#words[@]}"

    local shellCompDirectiveError=1
    local shellCompDirectiveNoSpace=2
    local shellCompDirectiveNoFileComp=4
    local shellCompDirectiveFilterFileExt=8
    local shellCompDirectiveFilterDirs=16

    local out requestComp lastParam lastChar comp directive args

    # Prepare the command to request completions for the program.
    # Calling ${words[0]} instead of directly opsctl allows to handle aliases
    args=("${words[@]:1}")
    requestComp="${words[0]} __completeNoDesc ${args[*]}"

    lastParam=${words[$((${#words[@]}-1))]}
    lastChar=${lastParam:$((${#lastParam}-1)):1}
    __opsctl_debug "${FUNCNAME[0]}: lastParam ${lastParam}, lastChar ${lastChar}"

    if [ -z "${cur}" ] && [ "${lastChar}" != "=" ]; then
        # If the last parameter is complete (there is a space following it)
        # We add an extra empty parameter so we can indicate this to the go method.
        __opsctl_debug "${FUNCNAME[0]}: Adding extra empty parameter"
        requestComp="${requestComp} \"\""
    fi

    __opsctl_debug "${FUNCNAME[0]}: calling ${requestComp}"
    # Use eval to handle any environment variables and such
    out=$(eval "${requestComp}" 2>/dev/null)

    # Extract the directive integer at the very end of the output following a colon (:)
    directive=${out##*:}
    # Remove the directive
    out=${out%:*}
    if [ "${directive}" = "${out}" ]; then
        # There is not directive specified
        directive=0
    fi
    __opsctl_debug "${FUNCNAME[0]}: the completion directive is: ${directive}"
    __opsctl_debug "${FUNCNAME[0]}: the completions are: ${out[*]}"

    if [ $((directive & shellCompDirectiveError)) -ne 0 ]; then
        # Error code.  No completion.
        __opsctl_debug "${FUNCNAME[0]}: received error from custom completion go code"
        return
    else
        if [ $((directive & shellCompDirectiveNoSpace)) -ne 0 ]; then
            if [[ $(type -t compopt) = "builtin" ]]; then
                __opsctl_debug "${FUNCNAME[0]}: activating no space"
                compopt -o nospace
            fi
        fi
        if [ $((directive & shellCompDirectiveNoFileComp)) -ne 0 ]; then
            if [[ $(type -t compopt) = "builtin" ]]; then
                __opsctl_debug "${FUNCNAME[0]}: activating no file completion"
                compopt +o default
            fi
        fi
    fi

    if [ $((directive & shellCompDirectiveFilterFileExt)) -ne 0 ]; then
        # File extension filtering
        local fullFilter filter filteringCmd
        # Do not use quotes around the $out variable or else newline
        # characters will be kept.
        for filter in ${out[*]}; do
            fullFilter+="$filter|"
        done

        filteringCmd="_filedir $fullFilter"
        __opsctl_debug "File filtering command: $filteringCmd"
        $filteringCmd
    elif [ $((directive & shellCompDirectiveFilterDirs)) -ne 0 ]; then
        # File completion for directories only
        local subdir
        # Use printf to strip any trailing newline
        subdir=$(printf "%s" "${out[0]}")
        if [ -n "$subdir" ]; then
            __opsctl_debug "Listing directories in $subdir"
            __opsctl_handle_subdirs_in_dir_flag "$subdir"
        else
            __opsctl_debug "Listing directories in ."
            _filedir -d
        fi
    else
        while IFS='' read -r comp; do
            COMPREPLY+=("$comp")
        done < <(compgen -W "${out[*]}" -- "$cur")
    fi
}

__opsctl_handle_reply()
{
    __opsctl_debug "${FUNCNAME[0]}"
    local comp
    case $cur in
        -*)
            if [[ $(type -t compopt) = "builtin" ]]; then
                compopt -o nospace
            fi
            local allflags
            if [ ${#must_have_one_flag[@]} -ne 0 ]; then
                allflags=("${must_have_one_flag[@]}")
            else
                allflags=("${flags[*]} ${two_word_flags[*]}")
            fi
            while IFS='' read -r comp; do
                COMPREPLY+=("$comp")
            done < <(compgen -W "${allflags[*]}" -- "$cur")
            if [[ $(type -t compopt) = "builtin" ]]; then
                [[ "${COMPREPLY[0]}" == *= ]] || compopt +o nospace
            fi

            # complete after --flag=abc
            if [[ $cur == *=* ]]; then
                if [[ $(type -t compopt) = "builtin" ]]; then
                    compopt +o nospace
                fi

                local index flag
                flag="${cur%=*}"
                __opsctl_index_of_word "${flag}" "${flags_with_completion[@]}"
                COMPREPLY=()
                if [[ ${index} -ge 0 ]]; then
                    PREFIX=""
                    cur="${cur#*=}"
                    ${flags_completion[${index}]}
                    if [ -n "${ZSH_VERSION:-}" ]; then
                        # zsh completion needs --flag= prefix
                        eval "COMPREPLY=( \"\${COMPREPLY[@]/#/${flag}=}\" )"
                    fi
                fi
            fi

            if [[ -z "${flag_parsing_disabled}" ]]; then
                # If flag parsing is enabled, we have completed the flags and can return.
                # If flag parsing is disabled, we may not know all (or any) of the flags, so we fallthrough
                # to possibly call handle_go_custom_completion.
                return 0;
            fi
            ;;
    esac

    # check if we are handling a flag with special work handling
    local index
    __opsctl_index_of_word "${prev}" "${flags_with_completion[@]}"
    if [[ ${index} -ge 0 ]]; then
        ${flags_completion[${index}]}
        return
    fi

    # we are parsing a flag and don't have a special handler, no completion
    if [[ ${cur} != "${words[cword]}" ]]; then
        return
    fi

    local completions
    completions=("${commands[@]}")
    if [[ ${#must_have_one_noun[@]} -ne 0 ]]; then
        completions+=("${must_have_one_noun[@]}")
    elif [[ -n "${has_completion_function}" ]]; then
        # if a go completion function is provided, defer to that function
        __opsctl_handle_go_custom_completion
    fi
    if [[ ${#must_have_one_flag[@]} -ne 0 ]]; then
        completions+=("${must_have_one_flag[@]}")
    fi
    while IFS='' read -r comp; do
        COMPREPLY+=("$comp")
    done < <(compgen -W "${completions[*]}" -- "$cur")

    if [[ ${#COMPREPLY[@]} -eq 0 && ${#noun_aliases[@]} -gt 0 && ${#must_have_one_noun[@]} -ne 0 ]]; then
        while IFS='' read -r comp; do
            COMPREPLY+=("$comp")
        done < <(compgen -W "${noun_aliases[*]}" -- "$cur")
    fi

    if [[ ${#COMPREPLY[@]} -eq 0 ]]; then
        if declare -F __opsctl_custom_func >/dev/null; then
            # try command name qualified custom func
            __opsctl_custom_func
        else
            # otherwise fall back to unqualified for compatibility
            declare -F __custom_func >/dev/null && __custom_func
        fi
    fi

    # available in bash-completion >= 2, not always present on macOS
    if declare -F __ltrim_colon_completions >/dev/null; then
        __ltrim_colon_completions "$cur"
    fi

    # If there is only 1 completion and it is a flag with an = it will be completed
    # but we don't want a space after the =
    if [[ "${#COMPREPLY[@]}" -eq "1" ]] && [[ $(type -t compopt) = "builtin" ]] && [[ "${COMPREPLY[0]}" == --*= ]]; then
       compopt -o nospace
    fi
}

# The arguments should be in the form "ext1|ext2|extn"
__opsctl_handle_filename_extension_flag()
{
    local ext="$1"
    _filedir "@(${ext})"
}

__opsctl_handle_subdirs_in_dir_flag()
{
    local dir="$1"
    pushd "${dir}" >/dev/null 2>&1 && _filedir -d && popd >/dev/null 2>&1 || return
}

__opsctl_handle_flag()
{
    __opsctl_debug "${FUNCNAME[0]}: c is $c words[c] is ${words[c]}"

    # if a command required a flag, and we found it, unset must_have_one_flag()
    local flagname=${words[c]}
    local flagvalue=""
    # if the word contained an =
    if [[ ${words[c]} == *"="* ]]; then
        flagvalue=${flagname#*=} # take in as flagvalue after the =
        flagname=${flagname%=*} # strip everything after the =
        flagname="${flagname}=" # but put the = back
    fi
    __opsctl_debug "${FUNCNAME[0]}: looking for ${flagname}"
    if __opsctl_contains_word "${flagname}" "${must_have_one_flag[@]}"; then
        must_have_one_flag=()
    fi

    # if you set a flag which only applies to this command, don't show subcommands
    if __opsctl_contains_word "${flagname}" "${local_nonpersistent_flags[@]}"; then
      commands=()
    fi

    # keep flag value with flagname as flaghash
    # flaghash variable is an associative array which is only supported in bash > 3.
    if [[ -z "${BASH_VERSION:-}" || "${BASH_VERSINFO[0]:-}" -gt 3 ]]; then
        if [ -n "${flagvalue}" ] ; then
            flaghash[${flagname}]=${flagvalue}
        elif [ -n "${words[ $((c+1)) ]}" ] ; then
            flaghash[${flagname}]=${words[ $((c+1)) ]}
        else
            flaghash[${flagname}]="true" # pad "true" for bool flag
        fi
    fi

    # skip the argument to a two word flag
    if [[ ${words[c]} != *"="* ]] && __opsctl_contains_word "${words[c]}" "${two_word_flags[@]}"; then
        __opsctl_debug "${FUNCNAME[0]}: found a flag ${words[c]}, skip the next argument"
        c=$((c+1))
        # if we are looking for a flags value, don't show commands
        if [[ $c -eq $cword ]]; then
            commands=()
        fi
    fi

    c=$((c+1))

}

__opsctl_handle_noun()
{
    __opsctl_debug "${FUNCNAME[0]}: c is $c words[c] is ${words[c]}"

    if __opsctl_contains_word "${words[c]}" "${must_have_one_noun[@]}"; then
        must_have_one_noun=()
    elif __opsctl_contains_word "${words[c]}" "${noun_aliases[@]}"; then
        must_have_one_noun=()
    fi

    nouns+=("${words[c]}")
    c=$((c+1))
}

__opsctl_handle_command()
{
    __opsctl_debug "${FUNCNAME[0]}: c is $c words[c] is ${words[c]}"

    local next_command
    if [[ -n ${last_command} ]]; then
        next_command="_${last_command}_${words[c]//:/__}"
    else
        if [[ $c -eq 0 ]]; then
            next_command="_opsctl_root_command"
        else
            next_command="_${words[c]//:/__}"
        fi
    fi
    c=$((c+1))
    __opsctl_debug "${FUNCNAME[0]}: looking for ${next_command}"
    declare -F "$next_command" >/dev/null && $next_command
}

__opsctl_handle_word()
{
    if [[ $c -ge $cword ]]; then
        __opsctl_handle_reply
        return
    fi
    __opsctl_debug "${FUNCNAME[0]}: c is $c words[c] is ${words[c]}"
    if [[ "${words[c]}" == -* ]]; then
        __opsctl_handle_flag
    elif __opsctl_contains_word "${words[c]}" "${commands[@]}"; then
        __opsctl_handle_command
    elif [[ $c -eq 0 ]]; then
        __opsctl_handle_command
    elif __opsctl_contains_word "${words[c]}" "${command_aliases[@]}"; then
        # aliashash variable is an associative array which is only supported in bash > 3.
        if [[ -z "${BASH_VERSION:-}" || "${BASH_VERSINFO[0]:-}" -gt 3 ]]; then
            words[c]=${aliashash[${words[c]}]}
            __opsctl_handle_command
        else
            __opsctl_handle_noun
        fi
    else
        __opsctl_handle_noun
    fi
    __opsctl_handle_word
}

_opsctl_completion_bash()
{
    last_command="opsctl_completion_bash"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--help")
    flags+=("-h")
    local_nonpersistent_flags+=("--help")
    local_nonpersistent_flags+=("-h")
    flags+=("--no-cache")
    flags+=("--sso")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_opsctl_completion_fish()
{
    last_command="opsctl_completion_fish"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--alias=")
    two_word_flags+=("--alias")
    flags+=("--no-cache")
    flags+=("--sso")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_opsctl_completion_zsh()
{
    last_command="opsctl_completion_zsh"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--no-cache")
    flags+=("--sso")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_opsctl_completion()
{
    last_command="opsctl_completion"

    command_aliases=()

    commands=()
    commands+=("bash")
    commands+=("fish")
    commands+=("zsh")

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--no-cache")
    flags+=("--sso")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_opsctl_create_draughtsman()
{
    last_command="opsctl_create_draughtsman"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--installation=")
    two_word_flags+=("--installation")
    two_word_flags+=("-i")
    flags+=("--installations-branch=")
    two_word_flags+=("--installations-branch")
    two_word_flags+=("-b")
    flags+=("--releases-branch=")
    two_word_flags+=("--releases-branch")
    two_word_flags+=("-e")
    flags+=("--repository=")
    two_word_flags+=("--repository")
    two_word_flags+=("-r")
    flags+=("--no-cache")
    flags+=("--sso")

    must_have_one_flag=()
    must_have_one_flag+=("--installation=")
    must_have_one_flag+=("-i")
    must_have_one_noun=()
    noun_aliases=()
}

_opsctl_create_etcdbackup()
{
    last_command="opsctl_create_etcdbackup"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--installation=")
    two_word_flags+=("--installation")
    two_word_flags+=("-i")
    flags+=("--installations-branch=")
    two_word_flags+=("--installations-branch")
    two_word_flags+=("-b")
    flags+=("--level=")
    two_word_flags+=("--level")
    two_word_flags+=("-l")
    flags+=("--managementcluster")
    flags+=("--repository=")
    two_word_flags+=("--repository")
    two_word_flags+=("-r")
    flags+=("--user=")
    two_word_flags+=("--user")
    flags+=("--wait")
    flags+=("--workloadcluster=")
    two_word_flags+=("--workloadcluster")
    flags+=("--no-cache")
    flags+=("--sso")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_opsctl_create_kubeconfig()
{
    last_command="opsctl_create_kubeconfig"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--certificate-common-name-prefix=")
    two_word_flags+=("--certificate-common-name-prefix")
    flags+=("--certificate-organizations=")
    two_word_flags+=("--certificate-organizations")
    flags+=("--installation=")
    two_word_flags+=("--installation")
    two_word_flags+=("-i")
    flags+=("--installations-branch=")
    two_word_flags+=("--installations-branch")
    two_word_flags+=("-b")
    flags+=("--keep-context")
    flags+=("--kubie")
    flags+=("--level=")
    two_word_flags+=("--level")
    two_word_flags+=("-l")
    flags+=("--repository=")
    two_word_flags+=("--repository")
    two_word_flags+=("-r")
    flags+=("--ttl=")
    two_word_flags+=("--ttl")
    flags+=("--user=")
    two_word_flags+=("--user")
    flags+=("--no-cache")
    flags+=("--sso")

    must_have_one_flag=()
    must_have_one_flag+=("--installation=")
    must_have_one_flag+=("-i")
    must_have_one_noun=()
    noun_aliases=()
}

_opsctl_create_opslog()
{
    last_command="opsctl_create_opslog"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--component=")
    two_word_flags+=("--component")
    flags+=("--customer=")
    two_word_flags+=("--customer")
    flags+=("--installation=")
    two_word_flags+=("--installation")
    flags+=("--no-browser")
    flags+=("--provider=")
    two_word_flags+=("--provider")
    flags+=("--release=")
    two_word_flags+=("--release")
    flags+=("--team=")
    two_word_flags+=("--team")
    flags+=("--tenant=")
    two_word_flags+=("--tenant")
    flags+=("--title=")
    two_word_flags+=("--title")
    flags+=("--no-cache")
    flags+=("--sso")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_opsctl_create_routingrule()
{
    last_command="opsctl_create_routingrule"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--cluster=")
    two_word_flags+=("--cluster")
    two_word_flags+=("-c")
    flags+=("--conditions=")
    two_word_flags+=("--conditions")
    two_word_flags+=("-r")
    flags+=("--name=")
    two_word_flags+=("--name")
    two_word_flags+=("-n")
    flags+=("--ttl=")
    two_word_flags+=("--ttl")
    flags+=("--type=")
    two_word_flags+=("--type")
    two_word_flags+=("-t")
    flags+=("--user=")
    two_word_flags+=("--user")
    two_word_flags+=("-u")
    flags+=("--no-cache")
    flags+=("--sso")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_opsctl_create_silence()
{
    last_command="opsctl_create_silence"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--expiration-time=")
    two_word_flags+=("--expiration-time")
    two_word_flags+=("-e")
    flags+=("--installation=")
    two_word_flags+=("--installation")
    two_word_flags+=("-i")
    flags+=("--installations-branch=")
    two_word_flags+=("--installations-branch")
    two_word_flags+=("-b")
    flags+=("--level=")
    two_word_flags+=("--level")
    two_word_flags+=("-l")
    flags+=("--matchers=")
    two_word_flags+=("--matchers")
    two_word_flags+=("-m")
    flags+=("--quiet")
    flags+=("-q")
    flags+=("--repository=")
    two_word_flags+=("--repository")
    two_word_flags+=("-r")
    flags+=("--user=")
    two_word_flags+=("--user")
    flags+=("--no-cache")
    flags+=("--sso")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_opsctl_create_terraform()
{
    last_command="opsctl_create_terraform"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--dir=")
    two_word_flags+=("--dir")
    two_word_flags+=("-d")
    flags+=("--installation=")
    two_word_flags+=("--installation")
    two_word_flags+=("-i")
    flags+=("--installations-branch=")
    two_word_flags+=("--installations-branch")
    two_word_flags+=("-b")
    flags+=("--repository=")
    two_word_flags+=("--repository")
    two_word_flags+=("-r")
    flags+=("--no-cache")
    flags+=("--sso")

    must_have_one_flag=()
    must_have_one_flag+=("--installation=")
    must_have_one_flag+=("-i")
    must_have_one_noun=()
    noun_aliases=()
}

_opsctl_create_vaultconfig()
{
    last_command="opsctl_create_vaultconfig"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--installation=")
    two_word_flags+=("--installation")
    two_word_flags+=("-i")
    flags+=("--installations-branch=")
    two_word_flags+=("--installations-branch")
    two_word_flags+=("-b")
    local_nonpersistent_flags+=("--installations-branch")
    local_nonpersistent_flags+=("--installations-branch=")
    local_nonpersistent_flags+=("-b")
    flags+=("--level=")
    two_word_flags+=("--level")
    two_word_flags+=("-l")
    local_nonpersistent_flags+=("--level")
    local_nonpersistent_flags+=("--level=")
    local_nonpersistent_flags+=("-l")
    flags+=("--output=")
    two_word_flags+=("--output")
    two_word_flags+=("-o")
    local_nonpersistent_flags+=("--output")
    local_nonpersistent_flags+=("--output=")
    local_nonpersistent_flags+=("-o")
    flags+=("--user=")
    two_word_flags+=("--user")
    local_nonpersistent_flags+=("--user")
    local_nonpersistent_flags+=("--user=")
    flags+=("--vault=")
    two_word_flags+=("--vault")
    local_nonpersistent_flags+=("--vault")
    local_nonpersistent_flags+=("--vault=")
    flags+=("--no-cache")
    flags+=("--sso")

    must_have_one_flag=()
    must_have_one_flag+=("--installation=")
    must_have_one_flag+=("-i")
    must_have_one_noun=()
    noun_aliases=()
}

_opsctl_create()
{
    last_command="opsctl_create"

    command_aliases=()

    commands=()
    commands+=("draughtsman")
    commands+=("etcdbackup")
    commands+=("kubeconfig")
    commands+=("opslog")
    commands+=("routingrule")
    commands+=("silence")
    commands+=("terraform")
    commands+=("vaultconfig")

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--no-cache")
    flags+=("--sso")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_opsctl_debug_app()
{
    last_command="opsctl_debug_app"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--helm=")
    two_word_flags+=("--helm")
    flags+=("--level=")
    two_word_flags+=("--level")
    two_word_flags+=("-l")
    flags+=("--namespace=")
    two_word_flags+=("--namespace")
    two_word_flags+=("-n")
    flags+=("--no-cache")
    flags+=("--sso")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_opsctl_debug()
{
    last_command="opsctl_debug"

    command_aliases=()

    commands=()
    commands+=("app")

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--no-cache")
    flags+=("--sso")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_opsctl_decrypt()
{
    last_command="opsctl_decrypt"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--dir=")
    two_word_flags+=("--dir")
    flags+=("--ignore-fields=")
    two_word_flags+=("--ignore-fields")
    flags+=("--in=")
    two_word_flags+=("--in")
    flags+=("--out=")
    two_word_flags+=("--out")
    flags+=("--select-fields=")
    two_word_flags+=("--select-fields")
    flags+=("--no-cache")
    flags+=("--sso")

    must_have_one_flag=()
    must_have_one_flag+=("--in=")
    must_have_one_flag+=("--out=")
    must_have_one_noun=()
    noun_aliases=()
}

_opsctl_delete_cis3buckets()
{
    last_command="opsctl_delete_cis3buckets"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--region=")
    two_word_flags+=("--region")
    two_word_flags+=("-r")
    flags+=("--no-cache")
    flags+=("--sso")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_opsctl_delete_crs()
{
    last_command="opsctl_delete_crs"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--cluster=")
    two_word_flags+=("--cluster")
    two_word_flags+=("-c")
    flags+=("--dry-run")
    flags+=("-d")
    flags+=("--force")
    flags+=("--installation=")
    two_word_flags+=("--installation")
    two_word_flags+=("-i")
    flags+=("--level=")
    two_word_flags+=("--level")
    two_word_flags+=("-l")
    flags+=("--user=")
    two_word_flags+=("--user")
    flags+=("--no-cache")
    flags+=("--sso")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_opsctl_delete_routingrule()
{
    last_command="opsctl_delete_routingrule"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--id=")
    two_word_flags+=("--id")
    two_word_flags+=("-i")
    flags+=("--outdated")
    flags+=("-o")
    flags+=("--no-cache")
    flags+=("--sso")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_opsctl_delete_silence()
{
    last_command="opsctl_delete_silence"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--installation=")
    two_word_flags+=("--installation")
    two_word_flags+=("-i")
    flags+=("--installations-branch=")
    two_word_flags+=("--installations-branch")
    two_word_flags+=("-b")
    flags+=("--level=")
    two_word_flags+=("--level")
    two_word_flags+=("-l")
    flags+=("--repository=")
    two_word_flags+=("--repository")
    two_word_flags+=("-r")
    flags+=("--silence-id=")
    two_word_flags+=("--silence-id")
    two_word_flags+=("-s")
    flags+=("--user=")
    two_word_flags+=("--user")
    flags+=("--no-cache")
    flags+=("--sso")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_opsctl_delete()
{
    last_command="opsctl_delete"

    command_aliases=()

    commands=()
    commands+=("cis3buckets")
    commands+=("crs")
    commands+=("routingrule")
    if [[ -z "${BASH_VERSION:-}" || "${BASH_VERSINFO[0]:-}" -gt 3 ]]; then
        command_aliases+=("oncallrule")
        aliashash["oncallrule"]="routingrule"
    fi
    commands+=("silence")

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--no-cache")
    flags+=("--sso")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_opsctl_deploy()
{
    last_command="opsctl_deploy"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--2cp")
    flags+=("--cluster=")
    two_word_flags+=("--cluster")
    two_word_flags+=("-c")
    flags+=("--config-branch=")
    two_word_flags+=("--config-branch")
    flags+=("--deployment-status-check-interval=")
    two_word_flags+=("--deployment-status-check-interval")
    flags+=("--deployment-status-check-timeout=")
    two_word_flags+=("--deployment-status-check-timeout")
    flags+=("--installation=")
    two_word_flags+=("--installation")
    two_word_flags+=("-i")
    flags+=("--jumphost-user=")
    two_word_flags+=("--jumphost-user")
    flags+=("--konfigure-binary=")
    two_word_flags+=("--konfigure-binary")
    flags+=("--level=")
    two_word_flags+=("--level")
    two_word_flags+=("-l")
    flags+=("--machine-user=")
    two_word_flags+=("--machine-user")
    flags+=("--use-kubeconfig")
    flags+=("--wait-for-deployment-statuses")
    flags+=("-w")
    flags+=("--no-cache")
    flags+=("--sso")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_opsctl_diff_draughtsman()
{
    last_command="opsctl_diff_draughtsman"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--installation=")
    two_word_flags+=("--installation")
    two_word_flags+=("-i")
    flags+=("--installations-branch=")
    two_word_flags+=("--installations-branch")
    two_word_flags+=("-b")
    flags+=("--level=")
    two_word_flags+=("--level")
    two_word_flags+=("-l")
    flags+=("--releases-branch=")
    two_word_flags+=("--releases-branch")
    two_word_flags+=("-e")
    flags+=("--repository=")
    two_word_flags+=("--repository")
    two_word_flags+=("-r")
    flags+=("--silent")
    flags+=("-s")
    flags+=("--user=")
    two_word_flags+=("--user")
    flags+=("--no-cache")
    flags+=("--sso")

    must_have_one_flag=()
    must_have_one_flag+=("--installation=")
    must_have_one_flag+=("-i")
    must_have_one_noun=()
    noun_aliases=()
}

_opsctl_diff()
{
    last_command="opsctl_diff"

    command_aliases=()

    commands=()
    commands+=("draughtsman")

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--no-cache")
    flags+=("--sso")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_opsctl_drain()
{
    last_command="opsctl_drain"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--cert-based")
    flags+=("--delay-master-worker=")
    two_word_flags+=("--delay-master-worker")
    flags+=("--delay-reboot=")
    two_word_flags+=("--delay-reboot")
    flags+=("--installation=")
    two_word_flags+=("--installation")
    two_word_flags+=("-i")
    flags+=("--installations-branch=")
    two_word_flags+=("--installations-branch")
    two_word_flags+=("-b")
    flags+=("--jumphost-user=")
    two_word_flags+=("--jumphost-user")
    flags+=("--level=")
    two_word_flags+=("--level")
    two_word_flags+=("-l")
    flags+=("--machine-user=")
    two_word_flags+=("--machine-user")
    flags+=("--node=")
    two_word_flags+=("--node")
    two_word_flags+=("-n")
    flags+=("--repository=")
    two_word_flags+=("--repository")
    two_word_flags+=("-r")
    flags+=("--vault=")
    two_word_flags+=("--vault")
    flags+=("--no-cache")
    flags+=("--sso")

    must_have_one_flag=()
    must_have_one_flag+=("--installation=")
    must_have_one_flag+=("-i")
    must_have_one_noun=()
    noun_aliases=()
}

_opsctl_encrypt()
{
    last_command="opsctl_encrypt"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--dir=")
    two_word_flags+=("--dir")
    flags+=("--ignore-fields=")
    two_word_flags+=("--ignore-fields")
    flags+=("--in=")
    two_word_flags+=("--in")
    flags+=("--out=")
    two_word_flags+=("--out")
    flags+=("--select-fields=")
    two_word_flags+=("--select-fields")
    flags+=("--no-cache")
    flags+=("--sso")

    must_have_one_flag=()
    must_have_one_flag+=("--in=")
    must_have_one_flag+=("--out=")
    must_have_one_noun=()
    noun_aliases=()
}

_opsctl_ensure_catalogs()
{
    last_command="opsctl_ensure_catalogs"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--all")
    flags+=("-a")
    flags+=("--helm=")
    two_word_flags+=("--helm")
    flags+=("--helm-client-timeout=")
    two_word_flags+=("--helm-client-timeout")
    flags+=("--in-cluster")
    flags+=("--installation=")
    two_word_flags+=("--installation")
    two_word_flags+=("-i")
    flags+=("--installations-branch=")
    two_word_flags+=("--installations-branch")
    two_word_flags+=("-b")
    flags+=("--kubeconfig=")
    two_word_flags+=("--kubeconfig")
    two_word_flags+=("-k")
    flags+=("--level=")
    two_word_flags+=("--level")
    two_word_flags+=("-l")
    flags+=("--ns=")
    two_word_flags+=("--ns")
    flags+=("--repository=")
    two_word_flags+=("--repository")
    two_word_flags+=("-r")
    flags+=("--user=")
    two_word_flags+=("--user")
    flags+=("--version=")
    two_word_flags+=("--version")
    two_word_flags+=("-v")
    flags+=("--no-cache")
    flags+=("--sso")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_opsctl_ensure_crds()
{
    last_command="opsctl_ensure_crds"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--all")
    flags+=("-a")
    flags+=("--apiextensions-reference=")
    two_word_flags+=("--apiextensions-reference")
    flags+=("--crds=")
    two_word_flags+=("--crds")
    flags+=("--dry-run")
    flags+=("--installation=")
    two_word_flags+=("--installation")
    two_word_flags+=("-i")
    flags+=("--installations-branch=")
    two_word_flags+=("--installations-branch")
    two_word_flags+=("-b")
    flags+=("--kubeconfig=")
    two_word_flags+=("--kubeconfig")
    two_word_flags+=("-k")
    flags+=("--level=")
    two_word_flags+=("--level")
    two_word_flags+=("-l")
    flags+=("--provider=")
    two_word_flags+=("--provider")
    two_word_flags+=("-p")
    flags+=("--repository=")
    two_word_flags+=("--repository")
    two_word_flags+=("-r")
    flags+=("--user=")
    two_word_flags+=("--user")
    flags+=("--no-cache")
    flags+=("--sso")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_opsctl_ensure()
{
    last_command="opsctl_ensure"

    command_aliases=()

    commands=()
    commands+=("catalogs")
    commands+=("crds")

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--no-cache")
    flags+=("--sso")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_opsctl_get_etcdbackup()
{
    last_command="opsctl_get_etcdbackup"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--bucket=")
    two_word_flags+=("--bucket")
    two_word_flags+=("-b")
    flags+=("--filename=")
    two_word_flags+=("--filename")
    two_word_flags+=("-f")
    flags+=("--region=")
    two_word_flags+=("--region")
    two_word_flags+=("-r")
    flags+=("--no-cache")
    flags+=("--sso")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_opsctl_get()
{
    last_command="opsctl_get"

    command_aliases=()

    commands=()
    commands+=("etcdbackup")

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--no-cache")
    flags+=("--sso")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_opsctl_gsctl_login()
{
    last_command="opsctl_gsctl_login"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--installation=")
    two_word_flags+=("--installation")
    two_word_flags+=("-i")
    flags+=("--no-cache")
    flags+=("--sso")

    must_have_one_flag=()
    must_have_one_flag+=("--installation=")
    must_have_one_flag+=("-i")
    must_have_one_noun=()
    noun_aliases=()
}

_opsctl_gsctl()
{
    last_command="opsctl_gsctl"

    command_aliases=()

    commands=()
    commands+=("login")

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--no-cache")
    flags+=("--sso")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_opsctl_help()
{
    last_command="opsctl_help"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--no-cache")
    flags+=("--sso")

    must_have_one_flag=()
    must_have_one_noun=()
    has_completion_function=1
    noun_aliases=()
}

_opsctl_history()
{
    last_command="opsctl_history"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--component=")
    two_word_flags+=("--component")
    flags+=("--customer=")
    two_word_flags+=("--customer")
    flags+=("--format=")
    two_word_flags+=("--format")
    two_word_flags+=("-o")
    flags+=("--full")
    flags+=("--installation=")
    two_word_flags+=("--installation")
    flags+=("--level=")
    two_word_flags+=("--level")
    two_word_flags+=("-l")
    flags+=("--provider=")
    two_word_flags+=("--provider")
    flags+=("--release=")
    two_word_flags+=("--release")
    flags+=("--team=")
    two_word_flags+=("--team")
    flags+=("--tenant=")
    two_word_flags+=("--tenant")
    flags+=("--no-cache")
    flags+=("--sso")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_opsctl_kgs_login()
{
    last_command="opsctl_kgs_login"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--cluster-admin")
    flags+=("--installation=")
    two_word_flags+=("--installation")
    two_word_flags+=("-i")
    flags+=("--level=")
    two_word_flags+=("--level")
    flags+=("--no-cache")
    flags+=("--sso")

    must_have_one_flag=()
    must_have_one_flag+=("--installation=")
    must_have_one_flag+=("-i")
    must_have_one_noun=()
    noun_aliases=()
}

_opsctl_kgs()
{
    last_command="opsctl_kgs"

    command_aliases=()

    commands=()
    commands+=("login")

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--no-cache")
    flags+=("--sso")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_opsctl_kubectl()
{
    last_command="opsctl_kubectl"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--installation=")
    two_word_flags+=("--installation")
    two_word_flags+=("-i")
    flags+=("--jumphost-user=")
    two_word_flags+=("--jumphost-user")
    flags+=("--level=")
    two_word_flags+=("--level")
    two_word_flags+=("-l")
    flags+=("--machine-user=")
    two_word_flags+=("--machine-user")
    flags+=("--no-cache")
    flags+=("--sso")

    must_have_one_flag=()
    must_have_one_flag+=("--installation=")
    must_have_one_flag+=("-i")
    must_have_one_noun=()
    noun_aliases=()
}

_opsctl_list_alertdefinitions()
{
    last_command="opsctl_list_alertdefinitions"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--no-cache")
    flags+=("--sso")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_opsctl_list_alerts()
{
    last_command="opsctl_list_alerts"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--filter=")
    two_word_flags+=("--filter")
    two_word_flags+=("-f")
    flags+=("--inhibited")
    flags+=("--installation=")
    two_word_flags+=("--installation")
    two_word_flags+=("-i")
    flags+=("--installations-branch=")
    two_word_flags+=("--installations-branch")
    two_word_flags+=("-b")
    flags+=("--level=")
    two_word_flags+=("--level")
    two_word_flags+=("-l")
    flags+=("--port-forward-retry=")
    two_word_flags+=("--port-forward-retry")
    flags+=("--repository=")
    two_word_flags+=("--repository")
    two_word_flags+=("-r")
    flags+=("--short")
    flags+=("-s")
    flags+=("--silenced")
    flags+=("--user=")
    two_word_flags+=("--user")
    flags+=("--no-cache")
    flags+=("--sso")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_opsctl_list_crs()
{
    last_command="opsctl_list_crs"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--cluster=")
    two_word_flags+=("--cluster")
    two_word_flags+=("-c")
    flags+=("--installation=")
    two_word_flags+=("--installation")
    two_word_flags+=("-i")
    flags+=("--level=")
    two_word_flags+=("--level")
    two_word_flags+=("-l")
    flags+=("--no-cache")
    flags+=("--sso")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_opsctl_list_etcdbackups()
{
    last_command="opsctl_list_etcdbackups"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--bucket=")
    two_word_flags+=("--bucket")
    two_word_flags+=("-b")
    flags+=("--installation=")
    two_word_flags+=("--installation")
    two_word_flags+=("-i")
    flags+=("--region=")
    two_word_flags+=("--region")
    two_word_flags+=("-r")
    flags+=("--workload-cluster=")
    two_word_flags+=("--workload-cluster")
    flags+=("--no-cache")
    flags+=("--sso")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_opsctl_list_installations()
{
    last_command="opsctl_list_installations"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--all")
    flags+=("-a")
    flags+=("--customer=")
    two_word_flags+=("--customer")
    flags+=("--installations-branch=")
    two_word_flags+=("--installations-branch")
    two_word_flags+=("-b")
    flags+=("--level=")
    two_word_flags+=("--level")
    flags+=("--pipeline=")
    two_word_flags+=("--pipeline")
    flags+=("--provider=")
    two_word_flags+=("--provider")
    two_word_flags+=("-p")
    flags+=("--short")
    flags+=("-s")
    flags+=("--no-cache")
    flags+=("--sso")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_opsctl_list_portforwardings()
{
    last_command="opsctl_list_portforwardings"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--level=")
    two_word_flags+=("--level")
    two_word_flags+=("-l")
    flags+=("--no-cache")
    flags+=("--sso")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_opsctl_list_postmortems()
{
    last_command="opsctl_list_postmortems"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--all")
    flags+=("--assignee=")
    two_word_flags+=("--assignee")
    flags+=("--author=")
    two_word_flags+=("--author")
    flags+=("--component=")
    two_word_flags+=("--component")
    flags+=("--customer=")
    two_word_flags+=("--customer")
    flags+=("--format=")
    two_word_flags+=("--format")
    two_word_flags+=("-o")
    flags+=("--full")
    flags+=("--installation=")
    two_word_flags+=("--installation")
    flags+=("--installations-branch=")
    two_word_flags+=("--installations-branch")
    two_word_flags+=("-b")
    flags+=("--level=")
    two_word_flags+=("--level")
    two_word_flags+=("-l")
    flags+=("--provider=")
    two_word_flags+=("--provider")
    flags+=("--release=")
    two_word_flags+=("--release")
    flags+=("--repository=")
    two_word_flags+=("--repository")
    two_word_flags+=("-r")
    flags+=("--team=")
    two_word_flags+=("--team")
    flags+=("--no-cache")
    flags+=("--sso")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_opsctl_list_roadmap()
{
    last_command="opsctl_list_roadmap"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--all")
    flags+=("--assignee=")
    two_word_flags+=("--assignee")
    flags+=("--author=")
    two_word_flags+=("--author")
    flags+=("--component=")
    two_word_flags+=("--component")
    flags+=("--customer=")
    two_word_flags+=("--customer")
    flags+=("--format=")
    two_word_flags+=("--format")
    two_word_flags+=("-o")
    flags+=("--full")
    flags+=("--installations-branch=")
    two_word_flags+=("--installations-branch")
    two_word_flags+=("-b")
    flags+=("--level=")
    two_word_flags+=("--level")
    two_word_flags+=("-l")
    flags+=("--mission=")
    two_word_flags+=("--mission")
    flags+=("--no-mission")
    flags+=("--no-team")
    flags+=("--provider=")
    two_word_flags+=("--provider")
    flags+=("--repository=")
    two_word_flags+=("--repository")
    two_word_flags+=("-r")
    flags+=("--team=")
    two_word_flags+=("--team")
    flags+=("--no-cache")
    flags+=("--sso")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_opsctl_list_routingrules()
{
    last_command="opsctl_list_routingrules"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--no-cache")
    flags+=("--sso")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_opsctl_list_silences()
{
    last_command="opsctl_list_silences"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--expired")
    flags+=("--filter=")
    two_word_flags+=("--filter")
    two_word_flags+=("-f")
    flags+=("--installation=")
    two_word_flags+=("--installation")
    two_word_flags+=("-i")
    flags+=("--installations-branch=")
    two_word_flags+=("--installations-branch")
    two_word_flags+=("-b")
    flags+=("--level=")
    two_word_flags+=("--level")
    two_word_flags+=("-l")
    flags+=("--repository=")
    two_word_flags+=("--repository")
    two_word_flags+=("-r")
    flags+=("--user=")
    two_word_flags+=("--user")
    flags+=("--no-cache")
    flags+=("--sso")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_opsctl_list()
{
    last_command="opsctl_list"

    command_aliases=()

    commands=()
    commands+=("alertdefinitions")
    if [[ -z "${BASH_VERSION:-}" || "${BASH_VERSINFO[0]:-}" -gt 3 ]]; then
        command_aliases+=("alertdef")
        aliashash["alertdef"]="alertdefinitions"
        command_aliases+=("alf")
        aliashash["alf"]="alertdefinitions"
    fi
    commands+=("alerts")
    if [[ -z "${BASH_VERSION:-}" || "${BASH_VERSINFO[0]:-}" -gt 3 ]]; then
        command_aliases+=("alert")
        aliashash["alert"]="alerts"
    fi
    commands+=("crs")
    commands+=("etcdbackups")
    commands+=("installations")
    if [[ -z "${BASH_VERSION:-}" || "${BASH_VERSINFO[0]:-}" -gt 3 ]]; then
        command_aliases+=("ins")
        aliashash["ins"]="installations"
        command_aliases+=("inst")
        aliashash["inst"]="installations"
        command_aliases+=("insta")
        aliashash["insta"]="installations"
        command_aliases+=("installs")
        aliashash["installs"]="installations"
    fi
    commands+=("portforwardings")
    commands+=("postmortems")
    if [[ -z "${BASH_VERSION:-}" || "${BASH_VERSINFO[0]:-}" -gt 3 ]]; then
        command_aliases+=("postmortem")
        aliashash["postmortem"]="postmortems"
    fi
    commands+=("roadmap")
    commands+=("routingrules")
    if [[ -z "${BASH_VERSION:-}" || "${BASH_VERSINFO[0]:-}" -gt 3 ]]; then
        command_aliases+=("routingrule")
        aliashash["routingrule"]="routingrules"
    fi
    commands+=("silences")
    if [[ -z "${BASH_VERSION:-}" || "${BASH_VERSINFO[0]:-}" -gt 3 ]]; then
        command_aliases+=("silence")
        aliashash["silence"]="silences"
    fi

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--no-cache")
    flags+=("--sso")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_opsctl_login()
{
    last_command="opsctl_login"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--callback-port=")
    two_word_flags+=("--callback-port")
    flags+=("--keep-context")
    flags+=("--level=")
    two_word_flags+=("--level")
    two_word_flags+=("-l")
    flags+=("--method=")
    two_word_flags+=("--method")
    flags+=("--self-contained=")
    two_word_flags+=("--self-contained")
    flags+=("--no-cache")
    flags+=("--sso")

    must_have_one_flag=()
    must_have_one_noun=()
    has_completion_function=1
    noun_aliases=()
}

_opsctl_notify_incident()
{
    last_command="opsctl_notify_incident"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--channel=")
    two_word_flags+=("--channel")
    two_word_flags+=("-c")
    local_nonpersistent_flags+=("--channel")
    local_nonpersistent_flags+=("--channel=")
    local_nonpersistent_flags+=("-c")
    flags+=("--customers")
    local_nonpersistent_flags+=("--customers")
    flags+=("--dry-run")
    local_nonpersistent_flags+=("--dry-run")
    flags+=("--file=")
    two_word_flags+=("--file")
    two_word_flags+=("-f")
    local_nonpersistent_flags+=("--file")
    local_nonpersistent_flags+=("--file=")
    local_nonpersistent_flags+=("-f")
    flags+=("--installations-branch=")
    two_word_flags+=("--installations-branch")
    two_word_flags+=("-b")
    local_nonpersistent_flags+=("--installations-branch")
    local_nonpersistent_flags+=("--installations-branch=")
    local_nonpersistent_flags+=("-b")
    flags+=("--level=")
    two_word_flags+=("--level")
    two_word_flags+=("-l")
    local_nonpersistent_flags+=("--level")
    local_nonpersistent_flags+=("--level=")
    local_nonpersistent_flags+=("-l")
    flags+=("--md-to-slack")
    local_nonpersistent_flags+=("--md-to-slack")
    flags+=("--provider=")
    two_word_flags+=("--provider")
    two_word_flags+=("-p")
    local_nonpersistent_flags+=("--provider")
    local_nonpersistent_flags+=("--provider=")
    local_nonpersistent_flags+=("-p")
    flags+=("--no-cache")
    flags+=("--sso")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_opsctl_notify_release()
{
    last_command="opsctl_notify_release"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--channel=")
    two_word_flags+=("--channel")
    two_word_flags+=("-c")
    local_nonpersistent_flags+=("--channel")
    local_nonpersistent_flags+=("--channel=")
    local_nonpersistent_flags+=("-c")
    flags+=("--customers")
    local_nonpersistent_flags+=("--customers")
    flags+=("--dry-run")
    local_nonpersistent_flags+=("--dry-run")
    flags+=("--file=")
    two_word_flags+=("--file")
    two_word_flags+=("-f")
    local_nonpersistent_flags+=("--file")
    local_nonpersistent_flags+=("--file=")
    local_nonpersistent_flags+=("-f")
    flags+=("--installations-branch=")
    two_word_flags+=("--installations-branch")
    two_word_flags+=("-b")
    local_nonpersistent_flags+=("--installations-branch")
    local_nonpersistent_flags+=("--installations-branch=")
    local_nonpersistent_flags+=("-b")
    flags+=("--level=")
    two_word_flags+=("--level")
    two_word_flags+=("-l")
    local_nonpersistent_flags+=("--level")
    local_nonpersistent_flags+=("--level=")
    local_nonpersistent_flags+=("-l")
    flags+=("--md-to-slack")
    local_nonpersistent_flags+=("--md-to-slack")
    flags+=("--provider=")
    two_word_flags+=("--provider")
    two_word_flags+=("-p")
    local_nonpersistent_flags+=("--provider")
    local_nonpersistent_flags+=("--provider=")
    local_nonpersistent_flags+=("-p")
    flags+=("--no-cache")
    flags+=("--sso")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_opsctl_notify_weekly()
{
    last_command="opsctl_notify_weekly"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--channel=")
    two_word_flags+=("--channel")
    two_word_flags+=("-c")
    local_nonpersistent_flags+=("--channel")
    local_nonpersistent_flags+=("--channel=")
    local_nonpersistent_flags+=("-c")
    flags+=("--customers")
    local_nonpersistent_flags+=("--customers")
    flags+=("--dry-run")
    local_nonpersistent_flags+=("--dry-run")
    flags+=("--file=")
    two_word_flags+=("--file")
    two_word_flags+=("-f")
    local_nonpersistent_flags+=("--file")
    local_nonpersistent_flags+=("--file=")
    local_nonpersistent_flags+=("-f")
    flags+=("--installations-branch=")
    two_word_flags+=("--installations-branch")
    two_word_flags+=("-b")
    local_nonpersistent_flags+=("--installations-branch")
    local_nonpersistent_flags+=("--installations-branch=")
    local_nonpersistent_flags+=("-b")
    flags+=("--level=")
    two_word_flags+=("--level")
    two_word_flags+=("-l")
    local_nonpersistent_flags+=("--level")
    local_nonpersistent_flags+=("--level=")
    local_nonpersistent_flags+=("-l")
    flags+=("--no-cache")
    flags+=("--sso")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_opsctl_notify()
{
    last_command="opsctl_notify"

    command_aliases=()

    commands=()
    commands+=("incident")
    commands+=("release")
    commands+=("weekly")

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--no-cache")
    flags+=("--sso")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_opsctl_open()
{
    last_command="opsctl_open"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--app=")
    two_word_flags+=("--app")
    two_word_flags+=("-a")
    flags+=("--installation=")
    two_word_flags+=("--installation")
    two_word_flags+=("-i")
    flags+=("--installations-branch=")
    two_word_flags+=("--installations-branch")
    two_word_flags+=("-b")
    flags+=("--level=")
    two_word_flags+=("--level")
    two_word_flags+=("-l")
    flags+=("--no-browser")
    flags+=("--repository=")
    two_word_flags+=("--repository")
    two_word_flags+=("-r")
    flags+=("--user=")
    two_word_flags+=("--user")
    flags+=("--workload-cluster=")
    two_word_flags+=("--workload-cluster")
    flags+=("--no-cache")
    flags+=("--sso")

    must_have_one_flag=()
    must_have_one_flag+=("--installation=")
    must_have_one_flag+=("-i")
    must_have_one_noun=()
    noun_aliases=()
}

_opsctl_ping()
{
    last_command="opsctl_ping"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--installation=")
    two_word_flags+=("--installation")
    two_word_flags+=("-i")
    flags+=("--response-header-timeout=")
    two_word_flags+=("--response-header-timeout")
    flags+=("--timeout=")
    two_word_flags+=("--timeout")
    two_word_flags+=("-t")
    flags+=("--tls-handshake-timeout=")
    two_word_flags+=("--tls-handshake-timeout")
    flags+=("--no-cache")
    flags+=("--sso")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_opsctl_reconcile_app()
{
    last_command="opsctl_reconcile_app"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--level=")
    two_word_flags+=("--level")
    two_word_flags+=("-l")
    flags+=("--namespace=")
    two_word_flags+=("--namespace")
    two_word_flags+=("-n")
    flags+=("--no-cache")
    flags+=("--sso")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_opsctl_reconcile()
{
    last_command="opsctl_reconcile"

    command_aliases=()

    commands=()
    commands+=("app")

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--no-cache")
    flags+=("--sso")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_opsctl_reinstall()
{
    last_command="opsctl_reinstall"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--installation=")
    two_word_flags+=("--installation")
    two_word_flags+=("-i")
    flags+=("--installations-branch=")
    two_word_flags+=("--installations-branch")
    two_word_flags+=("-b")
    flags+=("--level=")
    two_word_flags+=("--level")
    two_word_flags+=("-l")
    flags+=("--repository=")
    two_word_flags+=("--repository")
    two_word_flags+=("-r")
    flags+=("--user=")
    two_word_flags+=("--user")
    flags+=("--no-cache")
    flags+=("--sso")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_opsctl_release_deploy()
{
    last_command="opsctl_release_deploy"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--app=")
    two_word_flags+=("--app")
    two_word_flags+=("-a")
    flags+=("--base-release=")
    two_word_flags+=("--base-release")
    two_word_flags+=("-b")
    flags+=("--component=")
    two_word_flags+=("--component")
    two_word_flags+=("-c")
    flags+=("--installation=")
    two_word_flags+=("--installation")
    two_word_flags+=("-i")
    flags+=("--jumphost-user=")
    two_word_flags+=("--jumphost-user")
    flags+=("--level=")
    two_word_flags+=("--level")
    two_word_flags+=("-l")
    flags+=("--name=")
    two_word_flags+=("--name")
    two_word_flags+=("-n")
    flags+=("--releases-repo=")
    two_word_flags+=("--releases-repo")
    two_word_flags+=("-r")
    flags+=("--no-cache")
    flags+=("--sso")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_opsctl_release_undeploy()
{
    last_command="opsctl_release_undeploy"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--all")
    flags+=("-a")
    flags+=("--installation=")
    two_word_flags+=("--installation")
    two_word_flags+=("-i")
    flags+=("--jumphost-user=")
    two_word_flags+=("--jumphost-user")
    flags+=("--level=")
    two_word_flags+=("--level")
    two_word_flags+=("-l")
    flags+=("--name=")
    two_word_flags+=("--name")
    two_word_flags+=("-n")
    flags+=("--no-cache")
    flags+=("--sso")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_opsctl_release()
{
    last_command="opsctl_release"

    command_aliases=()

    commands=()
    commands+=("deploy")
    commands+=("undeploy")

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--no-cache")
    flags+=("--sso")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_opsctl_scp()
{
    last_command="opsctl_scp"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--cert-based")
    flags+=("--installations-branch=")
    two_word_flags+=("--installations-branch")
    two_word_flags+=("-b")
    flags+=("--jumphost-only")
    flags+=("--jumphost-user=")
    two_word_flags+=("--jumphost-user")
    flags+=("--level=")
    two_word_flags+=("--level")
    two_word_flags+=("-l")
    flags+=("--machine-user=")
    two_word_flags+=("--machine-user")
    flags+=("--vault=")
    two_word_flags+=("--vault")
    flags+=("--no-cache")
    flags+=("--sso")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_opsctl_secret_decrypt()
{
    last_command="opsctl_secret_decrypt"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--dir=")
    two_word_flags+=("--dir")
    flags+=("--ignore-fields=")
    two_word_flags+=("--ignore-fields")
    flags+=("--in=")
    two_word_flags+=("--in")
    flags+=("--out=")
    two_word_flags+=("--out")
    flags+=("--select-fields=")
    two_word_flags+=("--select-fields")
    flags+=("--installation=")
    two_word_flags+=("--installation")
    two_word_flags+=("-i")
    flags+=("--installations-branch=")
    two_word_flags+=("--installations-branch")
    two_word_flags+=("-b")
    flags+=("--level=")
    two_word_flags+=("--level")
    two_word_flags+=("-l")
    flags+=("--no-cache")
    flags+=("--sso")
    flags+=("--user=")
    two_word_flags+=("--user")
    flags+=("--vault=")
    two_word_flags+=("--vault")

    must_have_one_flag=()
    must_have_one_flag+=("--in=")
    must_have_one_flag+=("--out=")
    must_have_one_noun=()
    noun_aliases=()
}

_opsctl_secret_encrypt()
{
    last_command="opsctl_secret_encrypt"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--dir=")
    two_word_flags+=("--dir")
    flags+=("--ignore-fields=")
    two_word_flags+=("--ignore-fields")
    flags+=("--in=")
    two_word_flags+=("--in")
    flags+=("--out=")
    two_word_flags+=("--out")
    flags+=("--select-fields=")
    two_word_flags+=("--select-fields")
    flags+=("--installation=")
    two_word_flags+=("--installation")
    two_word_flags+=("-i")
    flags+=("--installations-branch=")
    two_word_flags+=("--installations-branch")
    two_word_flags+=("-b")
    flags+=("--level=")
    two_word_flags+=("--level")
    two_word_flags+=("-l")
    flags+=("--no-cache")
    flags+=("--sso")
    flags+=("--user=")
    two_word_flags+=("--user")
    flags+=("--vault=")
    two_word_flags+=("--vault")

    must_have_one_flag=()
    must_have_one_flag+=("--in=")
    must_have_one_flag+=("--out=")
    must_have_one_noun=()
    noun_aliases=()
}

_opsctl_secret_show()
{
    last_command="opsctl_secret_show"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--in=")
    two_word_flags+=("--in")
    flags+=("--key=")
    two_word_flags+=("--key")
    two_word_flags+=("-k")
    flags+=("--installation=")
    two_word_flags+=("--installation")
    two_word_flags+=("-i")
    flags+=("--installations-branch=")
    two_word_flags+=("--installations-branch")
    two_word_flags+=("-b")
    flags+=("--level=")
    two_word_flags+=("--level")
    two_word_flags+=("-l")
    flags+=("--no-cache")
    flags+=("--sso")
    flags+=("--user=")
    two_word_flags+=("--user")
    flags+=("--vault=")
    two_word_flags+=("--vault")

    must_have_one_flag=()
    must_have_one_flag+=("--in=")
    must_have_one_flag+=("--key=")
    must_have_one_flag+=("-k")
    must_have_one_noun=()
    noun_aliases=()
}

_opsctl_secret_update()
{
    last_command="opsctl_secret_update"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--file=")
    two_word_flags+=("--file")
    two_word_flags+=("-f")
    flags+=("--in=")
    two_word_flags+=("--in")
    flags+=("--key=")
    two_word_flags+=("--key")
    two_word_flags+=("-k")
    flags+=("--installation=")
    two_word_flags+=("--installation")
    two_word_flags+=("-i")
    flags+=("--installations-branch=")
    two_word_flags+=("--installations-branch")
    two_word_flags+=("-b")
    flags+=("--level=")
    two_word_flags+=("--level")
    two_word_flags+=("-l")
    flags+=("--no-cache")
    flags+=("--sso")
    flags+=("--user=")
    two_word_flags+=("--user")
    flags+=("--vault=")
    two_word_flags+=("--vault")

    must_have_one_flag=()
    must_have_one_flag+=("--in=")
    must_have_one_flag+=("--key=")
    must_have_one_flag+=("-k")
    must_have_one_noun=()
    noun_aliases=()
}

_opsctl_secret()
{
    last_command="opsctl_secret"

    command_aliases=()

    commands=()
    commands+=("decrypt")
    commands+=("encrypt")
    commands+=("show")
    commands+=("update")

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--installation=")
    two_word_flags+=("--installation")
    two_word_flags+=("-i")
    flags+=("--installations-branch=")
    two_word_flags+=("--installations-branch")
    two_word_flags+=("-b")
    flags+=("--level=")
    two_word_flags+=("--level")
    two_word_flags+=("-l")
    flags+=("--user=")
    two_word_flags+=("--user")
    flags+=("--vault=")
    two_word_flags+=("--vault")
    flags+=("--no-cache")
    flags+=("--sso")

    must_have_one_flag=()
    must_have_one_flag+=("--installation=")
    must_have_one_flag+=("-i")
    must_have_one_noun=()
    noun_aliases=()
}

_opsctl_show_escalation()
{
    last_command="opsctl_show_escalation"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--installation=")
    two_word_flags+=("--installation")
    two_word_flags+=("-i")
    flags+=("--installations-branch=")
    two_word_flags+=("--installations-branch")
    two_word_flags+=("-b")
    flags+=("--repository=")
    two_word_flags+=("--repository")
    two_word_flags+=("-r")
    flags+=("--no-cache")
    flags+=("--sso")

    must_have_one_flag=()
    must_have_one_flag+=("--installation=")
    must_have_one_flag+=("-i")
    must_have_one_noun=()
    noun_aliases=()
}

_opsctl_show_installation()
{
    last_command="opsctl_show_installation"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--installation=")
    two_word_flags+=("--installation")
    two_word_flags+=("-i")
    flags+=("--installations-branch=")
    two_word_flags+=("--installations-branch")
    two_word_flags+=("-b")
    flags+=("--repository=")
    two_word_flags+=("--repository")
    two_word_flags+=("-r")
    flags+=("--no-cache")
    flags+=("--sso")

    must_have_one_flag=()
    must_have_one_flag+=("--installation=")
    must_have_one_flag+=("-i")
    must_have_one_noun=()
    noun_aliases=()
}

_opsctl_show_secret()
{
    last_command="opsctl_show_secret"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--in=")
    two_word_flags+=("--in")
    two_word_flags+=("-i")
    flags+=("--key=")
    two_word_flags+=("--key")
    two_word_flags+=("-k")
    flags+=("--no-cache")
    flags+=("--sso")

    must_have_one_flag=()
    must_have_one_flag+=("--in=")
    must_have_one_flag+=("-i")
    must_have_one_flag+=("--key=")
    must_have_one_flag+=("-k")
    must_have_one_noun=()
    noun_aliases=()
}

_opsctl_show()
{
    last_command="opsctl_show"

    command_aliases=()

    commands=()
    commands+=("escalation")
    commands+=("installation")
    commands+=("secret")

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--no-cache")
    flags+=("--sso")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_opsctl_ssh()
{
    last_command="opsctl_ssh"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--cert-based")
    flags+=("--cluster=")
    two_word_flags+=("--cluster")
    two_word_flags+=("-c")
    flags+=("--cmd=")
    two_word_flags+=("--cmd")
    flags+=("--installations-branch=")
    two_word_flags+=("--installations-branch")
    two_word_flags+=("-b")
    flags+=("--jumphost-only")
    flags+=("--jumphost-user=")
    two_word_flags+=("--jumphost-user")
    flags+=("--level=")
    two_word_flags+=("--level")
    two_word_flags+=("-l")
    flags+=("--machine-user=")
    two_word_flags+=("--machine-user")
    flags+=("--vault=")
    two_word_flags+=("--vault")
    flags+=("--verbose")
    flags+=("-v")
    flags+=("--no-cache")
    flags+=("--sso")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_opsctl_undeploy()
{
    last_command="opsctl_undeploy"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--installation=")
    two_word_flags+=("--installation")
    two_word_flags+=("-i")
    flags+=("--jumphost-user=")
    two_word_flags+=("--jumphost-user")
    flags+=("--konfigure-binary=")
    two_word_flags+=("--konfigure-binary")
    flags+=("--level=")
    two_word_flags+=("--level")
    two_word_flags+=("-l")
    flags+=("--machine-user=")
    two_word_flags+=("--machine-user")
    flags+=("--use-kubeconfig")
    flags+=("--no-cache")
    flags+=("--sso")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_opsctl_update_api()
{
    last_command="opsctl_update_api"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--api-version=")
    two_word_flags+=("--api-version")
    flags+=("--installation=")
    two_word_flags+=("--installation")
    two_word_flags+=("-i")
    flags+=("--installations-branch=")
    two_word_flags+=("--installations-branch")
    two_word_flags+=("-b")
    flags+=("--jumphost-user=")
    two_word_flags+=("--jumphost-user")
    flags+=("--level=")
    two_word_flags+=("--level")
    two_word_flags+=("-l")
    flags+=("--machine-user=")
    two_word_flags+=("--machine-user")
    flags+=("--repository=")
    two_word_flags+=("--repository")
    two_word_flags+=("-r")
    flags+=("--no-cache")
    flags+=("--sso")

    must_have_one_flag=()
    must_have_one_flag+=("--installation=")
    must_have_one_flag+=("-i")
    must_have_one_noun=()
    noun_aliases=()
}

_opsctl_update_draughtsman()
{
    last_command="opsctl_update_draughtsman"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--all")
    flags+=("-a")
    flags+=("--installation=")
    two_word_flags+=("--installation")
    two_word_flags+=("-i")
    flags+=("--installations-branch=")
    two_word_flags+=("--installations-branch")
    two_word_flags+=("-b")
    flags+=("--level=")
    two_word_flags+=("--level")
    two_word_flags+=("-l")
    flags+=("--releases-branch=")
    two_word_flags+=("--releases-branch")
    two_word_flags+=("-e")
    flags+=("--repository=")
    two_word_flags+=("--repository")
    two_word_flags+=("-r")
    flags+=("--user=")
    two_word_flags+=("--user")
    flags+=("--wait")
    flags+=("-w")
    flags+=("--no-cache")
    flags+=("--sso")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_opsctl_update_installation()
{
    last_command="opsctl_update_installation"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--installation=")
    two_word_flags+=("--installation")
    two_word_flags+=("-i")
    flags+=("--installations-branch=")
    two_word_flags+=("--installations-branch")
    two_word_flags+=("-b")
    flags+=("--installations-repository=")
    two_word_flags+=("--installations-repository")
    two_word_flags+=("-r")
    flags+=("--release-version=")
    two_word_flags+=("--release-version")
    flags+=("--scope=")
    two_word_flags+=("--scope")
    two_word_flags+=("-s")
    flags+=("--no-cache")
    flags+=("--sso")

    must_have_one_flag=()
    must_have_one_flag+=("--installation=")
    must_have_one_flag+=("-i")
    must_have_one_noun=()
    noun_aliases=()
}

_opsctl_update_mayu()
{
    last_command="opsctl_update_mayu"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--dry-run")
    flags+=("--hive-branch=")
    two_word_flags+=("--hive-branch")
    two_word_flags+=("-b")
    flags+=("--hive-repository=")
    two_word_flags+=("--hive-repository")
    two_word_flags+=("-r")
    flags+=("--installation=")
    two_word_flags+=("--installation")
    two_word_flags+=("-i")
    flags+=("--installation-branch=")
    two_word_flags+=("--installation-branch")
    flags+=("--installation-repository=")
    two_word_flags+=("--installation-repository")
    flags+=("--jumphost-user=")
    two_word_flags+=("--jumphost-user")
    flags+=("--machine-user=")
    two_word_flags+=("--machine-user")
    flags+=("--vpn")
    flags+=("--vpn-config-file=")
    two_word_flags+=("--vpn-config-file")
    flags+=("--vpn-verbose")
    flags+=("--no-cache")
    flags+=("--sso")

    must_have_one_flag=()
    must_have_one_flag+=("--installation=")
    must_have_one_flag+=("-i")
    must_have_one_noun=()
    noun_aliases=()
}

_opsctl_update_secret()
{
    last_command="opsctl_update_secret"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--file=")
    two_word_flags+=("--file")
    two_word_flags+=("-f")
    flags+=("--in=")
    two_word_flags+=("--in")
    two_word_flags+=("-i")
    flags+=("--key=")
    two_word_flags+=("--key")
    two_word_flags+=("-k")
    flags+=("--no-cache")
    flags+=("--sso")

    must_have_one_flag=()
    must_have_one_flag+=("--in=")
    must_have_one_flag+=("-i")
    must_have_one_flag+=("--key=")
    must_have_one_flag+=("-k")
    must_have_one_noun=()
    noun_aliases=()
}

_opsctl_update_status()
{
    last_command="opsctl_update_status"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--installation=")
    two_word_flags+=("--installation")
    two_word_flags+=("-i")
    flags+=("--installations-branch=")
    two_word_flags+=("--installations-branch")
    two_word_flags+=("-b")
    flags+=("--level=")
    two_word_flags+=("--level")
    two_word_flags+=("-l")
    flags+=("--no-ssh-tunnel")
    flags+=("--path=")
    two_word_flags+=("--path")
    two_word_flags+=("-p")
    flags+=("--user=")
    two_word_flags+=("--user")
    flags+=("--no-cache")
    flags+=("--sso")

    must_have_one_flag=()
    must_have_one_flag+=("--installation=")
    must_have_one_flag+=("-i")
    must_have_one_flag+=("--path=")
    must_have_one_flag+=("-p")
    must_have_one_noun=()
    noun_aliases=()
}

_opsctl_update_vault()
{
    last_command="opsctl_update_vault"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--dry-run")
    flags+=("--hive-branch=")
    two_word_flags+=("--hive-branch")
    two_word_flags+=("-b")
    flags+=("--installation=")
    two_word_flags+=("--installation")
    two_word_flags+=("-i")
    flags+=("--installations-branch=")
    two_word_flags+=("--installations-branch")
    flags+=("--installations-repository=")
    two_word_flags+=("--installations-repository")
    flags+=("--jumphost-user=")
    two_word_flags+=("--jumphost-user")
    flags+=("--machine-user=")
    two_word_flags+=("--machine-user")
    flags+=("--repository=")
    two_word_flags+=("--repository")
    two_word_flags+=("-r")
    flags+=("--vpn")
    flags+=("--vpn-config-file=")
    two_word_flags+=("--vpn-config-file")
    flags+=("--vpn-verbose")
    flags+=("--no-cache")
    flags+=("--sso")

    must_have_one_flag=()
    must_have_one_flag+=("--installation=")
    must_have_one_flag+=("-i")
    must_have_one_noun=()
    noun_aliases=()
}

_opsctl_update()
{
    last_command="opsctl_update"

    command_aliases=()

    commands=()
    commands+=("api")
    commands+=("draughtsman")
    commands+=("installation")
    if [[ -z "${BASH_VERSION:-}" || "${BASH_VERSINFO[0]:-}" -gt 3 ]]; then
        command_aliases+=("cluster")
        aliashash["cluster"]="installation"
    fi
    commands+=("mayu")
    commands+=("secret")
    commands+=("status")
    commands+=("vault")

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--no-cache")
    flags+=("--sso")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_opsctl_validate_clusterconfig()
{
    last_command="opsctl_validate_clusterconfig"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--installation=")
    two_word_flags+=("--installation")
    two_word_flags+=("-i")
    flags+=("--installations-branch=")
    two_word_flags+=("--installations-branch")
    two_word_flags+=("-b")
    flags+=("--no-cache")
    flags+=("--sso")

    must_have_one_flag=()
    must_have_one_flag+=("--installation=")
    must_have_one_flag+=("-i")
    must_have_one_noun=()
    noun_aliases=()
}

_opsctl_validate_tunnels()
{
    last_command="opsctl_validate_tunnels"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--all")
    flags+=("-a")
    flags+=("--installations-branch=")
    two_word_flags+=("--installations-branch")
    two_word_flags+=("-b")
    flags+=("--level=")
    two_word_flags+=("--level")
    two_word_flags+=("-l")
    flags+=("--user=")
    two_word_flags+=("--user")
    flags+=("--no-cache")
    flags+=("--sso")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_opsctl_validate()
{
    last_command="opsctl_validate"

    command_aliases=()

    commands=()
    commands+=("clusterconfig")
    commands+=("tunnels")

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--no-cache")
    flags+=("--sso")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_opsctl_vault_run()
{
    last_command="opsctl_vault_run"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--installation=")
    two_word_flags+=("--installation")
    two_word_flags+=("-i")
    flags+=("--installations-branch=")
    two_word_flags+=("--installations-branch")
    two_word_flags+=("-b")
    flags+=("--level=")
    two_word_flags+=("--level")
    flags+=("--namespace=")
    two_word_flags+=("--namespace")
    two_word_flags+=("-n")
    flags+=("--pod=")
    two_word_flags+=("--pod")
    two_word_flags+=("-p")
    flags+=("--no-cache")
    flags+=("--sso")

    must_have_one_flag=()
    must_have_one_flag+=("--installation=")
    must_have_one_flag+=("-i")
    must_have_one_noun=()
    noun_aliases=()
}

_opsctl_vault()
{
    last_command="opsctl_vault"

    command_aliases=()

    commands=()
    commands+=("run")

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--no-cache")
    flags+=("--sso")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_opsctl_version_check()
{
    last_command="opsctl_version_check"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--level=")
    two_word_flags+=("--level")
    two_word_flags+=("-l")
    flags+=("--no-cache")
    flags+=("--sso")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_opsctl_version_update()
{
    last_command="opsctl_version_update"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--level=")
    two_word_flags+=("--level")
    two_word_flags+=("-l")
    flags+=("--no-cache")
    flags+=("--sso")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_opsctl_version()
{
    last_command="opsctl_version"

    command_aliases=()

    commands=()
    commands+=("check")
    commands+=("update")

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--no-cache")
    flags+=("--sso")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_opsctl_vpn_close()
{
    last_command="opsctl_vpn_close"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--level=")
    two_word_flags+=("--level")
    two_word_flags+=("-l")
    flags+=("--vpn-config-file=")
    two_word_flags+=("--vpn-config-file")
    flags+=("--vpn-verbose")
    flags+=("--no-cache")
    flags+=("--sso")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_opsctl_vpn_open()
{
    last_command="opsctl_vpn_open"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--level=")
    two_word_flags+=("--level")
    two_word_flags+=("-l")
    flags+=("--vpn-config-file=")
    two_word_flags+=("--vpn-config-file")
    flags+=("--vpn-verbose")
    flags+=("--no-cache")
    flags+=("--sso")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_opsctl_vpn()
{
    last_command="opsctl_vpn"

    command_aliases=()

    commands=()
    commands+=("close")
    commands+=("open")

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--no-cache")
    flags+=("--sso")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_opsctl_wtf()
{
    last_command="opsctl_wtf"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--cluster=")
    two_word_flags+=("--cluster")
    two_word_flags+=("-c")
    local_nonpersistent_flags+=("--cluster")
    local_nonpersistent_flags+=("--cluster=")
    local_nonpersistent_flags+=("-c")
    flags+=("--full-audit")
    local_nonpersistent_flags+=("--full-audit")
    flags+=("--installation=")
    two_word_flags+=("--installation")
    two_word_flags+=("-i")
    local_nonpersistent_flags+=("--installation")
    local_nonpersistent_flags+=("--installation=")
    local_nonpersistent_flags+=("-i")
    flags+=("--no-cache")
    flags+=("--sso")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_opsctl_root_command()
{
    last_command="opsctl"

    command_aliases=()

    commands=()
    commands+=("completion")
    commands+=("create")
    commands+=("debug")
    commands+=("decrypt")
    commands+=("delete")
    commands+=("deploy")
    commands+=("diff")
    commands+=("drain")
    commands+=("encrypt")
    commands+=("ensure")
    commands+=("get")
    commands+=("gsctl")
    commands+=("help")
    commands+=("history")
    if [[ -z "${BASH_VERSION:-}" || "${BASH_VERSINFO[0]:-}" -gt 3 ]]; then
        command_aliases+=("opslog")
        aliashash["opslog"]="history"
    fi
    commands+=("kgs")
    commands+=("kubectl")
    commands+=("list")
    commands+=("login")
    commands+=("notify")
    commands+=("open")
    commands+=("ping")
    commands+=("reconcile")
    commands+=("reinstall")
    commands+=("release")
    commands+=("scp")
    commands+=("secret")
    commands+=("show")
    commands+=("ssh")
    commands+=("undeploy")
    commands+=("update")
    commands+=("validate")
    commands+=("vault")
    commands+=("version")
    commands+=("vpn")
    commands+=("wtf")

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--no-cache")
    flags+=("--sso")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

__start_opsctl()
{
    local cur prev words cword split
    declare -A flaghash 2>/dev/null || :
    declare -A aliashash 2>/dev/null || :
    if declare -F _init_completion >/dev/null 2>&1; then
        _init_completion -s || return
    else
        __opsctl_init_completion -n "=" || return
    fi

    local c=0
    local flag_parsing_disabled=
    local flags=()
    local two_word_flags=()
    local local_nonpersistent_flags=()
    local flags_with_completion=()
    local flags_completion=()
    local commands=("opsctl")
    local command_aliases=()
    local must_have_one_flag=()
    local must_have_one_noun=()
    local has_completion_function=""
    local last_command=""
    local nouns=()
    local noun_aliases=()

    __opsctl_handle_word
}

if [ "$(type -t compopt)" = "builtin" ]; then
    complete -o default -F __start_opsctl opsctl
    complete -o default -F __start_opsctl ops
else
    complete -o default -o nospace -F __start_opsctl opsctl
    complete -o default -o nospace -F __start_opsctl ops
fi

# ex: ts=4 sw=4 et filetype=sh
