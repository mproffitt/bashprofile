##
# Process Manager script
#
# @Author: Martin Proffitt <mproffitt@jitsc.co.uk>
# @Website: www.jitsc.co.uk
# @license: GNU GPL v3 or later
#
# The purpose of this script is to provide multi-processing capabilities to
# BASH shell scripts which require, or can make use of "fan in / fan out"
# capabilities.
#
# Originally written to support the Bioinformatics ChIPSeq pipeline,
# [https://github.com/mproffitt/BioWorkflow](mproffitt/BioWorkflow), this script provides
# 3 modes of process management.
#
#   1. Full flow.    - simply add commands to the queue and wait for them to complete
#   2. Partial flow. - Commands can be set to 'wait' for a previous command to complete
#   3. Full block.   - Commands can block the whole queue until they have completed.
#
export PROCESSORS=$(grep -c processor /proc/cpuinfo)
export THREAD_SLEEP=1
export QUEUE=()
export PROCESSES=()
export STATUSES=()
export ACTIVE=0
export MANAGER_RUNNING=1

##
# Reset the queue back to a clean state.
#
# If the queue is currently running, this script will delay until
# all previous threads have completed
#
function reset_queue()
{
    [ -z ${MANAGER_RUNNING} ] && export MANAGER_RUNNING=0
    if [ $MANAGER_RUNNING -eq 0 ]; then
        until _queue_complete -eq 0; do
            _monitor
            sleep $THREAD_SLEEP
        done
    fi

    export QUEUE=()
    export PROCESSES=()
    export STATUSES=()
    export ACTIVE=0
}

##
# Print the contents of the queue
#
# Iterates over the queue and prints the status of the queue item
# followed by the command:
#
function print_queue()
{
    for (( i=0; i < ${#QUEUE[@]}; i++ )); do
        echo "${STATUSES[$i]}: $(cut -d^ -f1 <(echo ${QUEUE[$i]}))"
    done
}

##
# Add an item to the queue
#
# @param command       string
# @param logfile       string [optional]
# @param block|waitfor bool|int|last [optional]
#
# @return int Queue location ID
#
# Only one of <block|waitfor> may be provided.
#
#   block    May only be true or false. Will block the entire queue once started
#   waitfor  May be an integer identifying an existing queue item. Specifying 'last'
#            will use the queue id of the last command appended to the queue.
#
function queue()
{
    if [ ${#@} -eq 0 ] ; then
        inform "Usage: queue '<command>' [<logfile>] [[block|waitfor]=[true|false]]";
        inform 'commands must be quoted whilst logfile and blocking is optional.'
        inform 'call `process_queue` to execute.'
        return 1
    fi

    local command=''
    local logfile=''
    local block=''
    local push=false

    while [ ${#@} -ge 1 ]; do
        argument=$1
        shift
        flagtype=$(cut -d\= -f1 <(echo $argument))
        if [ "${flagtype}" = 'block' ] || [ "$flagtype" = 'waitfor' ] ; then
            block=$argument
        elif [ "${flagtype}" = 'push' ] && [ "$(sed 's/.*=//;' <(echo $argument))" = 'true' ]; then
            push=true
        elif which $(awk '{print $1}' <(echo $argument)) &>/dev/null ; then
            command="$argument"
        elif typeset -f $(awk '{print $1}' <(echo $argument)) &>/dev/null; then
            command="$argument"
        else
            logfile="$argument"
        fi
    done

    if $push; then
        QUEUE=("$command^$logfile" "${QUEUE[@]}")
    else
        QUEUE+=("$command^$logfile")
    fi

    status='Ready'
    if [ ! -z "$block" ] ; then
        if [ "$(cut -d\= -f1 <(echo $block))" = 'block' ] && [ "$(sed 's/.*=//;' <(echo $block))" = 'true' ]; then
            status='Block'
        elif [ "$(cut -d\= -f1 <(echo $block))" = 'waitfor' ]; then
            pid=$(sed 's/.*=//' <(echo $block))
            [ "$pid" = 'last' ] && pid=$(expr ${#STATUSES[@]} - 1)
            status="Waiting for ${pid}"
        fi
    fi

    if $push; then
        STATUSES=("$status" "${STATUSES[@]}")
    else
        STATUSES+=("$status")
    fi

    export QUEUE
    export STATUSES
    export ACTIVE
    return $(expr ${#QUEUE[@]} - 1)
}

##
# Push an item onto the top of the queue instead of appending it to the bottom
#
# @see `process_manager::queue`
function queue_push()
{
    queue "$@" "push=true"
    return $?
}

##
# Start the queue and execute any commands contained within it
#
# Queue status can be tested against the MANAGER_RUNNING environment variable
#
function process_queue()
{
    while true ; do
        export MANAGER_RUNNING=0
        for (( i=0; i < ${#QUEUE[@]}; i++ )); do
            if [ "${STATUSES[$i]}" = 'Complete' ]; then
                continue
            fi

            if [ $ACTIVE -lt ${PROCESSORS} ] ; then
                if [ "${STATUSES[$i]}" = 'Block' ] ; then
                    _exec $i
                    block $i
                elif [[ "${STATUSES[$i]}" =~ Waiting.* ]]; then
                    local index=$(awk '{print $NF}' <(echo ${STATUSES[$i]}))
                    if [ "${STATUSES[$index]}" = 'Complete' ] && ! kill -0 ${PROCESSES[$index]} &>/dev/null; then
                        _exec $i
                    fi
                elif [ "${STATUSES[$i]}" = 'Ready' ]; then
                    _exec $i
                fi
            fi
        done
        _monitor
        if _queue_complete; then
            break
        fi
        sleep $THREAD_SLEEP
    done
    export MANAGER_RUNNING=1
}

##
# Wait for a given process to complete
#
# @param pid     int | 'last'
# @param pidtype string ['queue' | 'process'] Which pool to check for $pid
#
# Hold the current pool until the process is completed
function wait_for()
{
    local pid=$1
    local pidtype=$2
    if [ -z $pidtype ] || [ "$pidtype" = 'queue' ] ; then
        [ "$pid" = 'last' ] && pid=$(expr ${#STATUSES[@]} - 1)
        until [ "${STATUSES[$pid]}" = 'Complete' ] ; do
            sleep $THREAD_SLEEP
        done
    elif [ "$pidtype" = 'process' ] ; then
        [ "${pid}" = 'last' ] && pid=$(_find_last_triggered_process) || pid=${PROCESSES[$pid]}
        until ! kill -0 $pid &>/dev/null ; do
            sleep $THREAD_SLEEP
        done
    fi
}

##
# Block until the process at queue_id is complete
#
# @param queue_id int
#
# Blocks the entire queue until a given ID has finished its execution
#
function block()
{
    queue_id=$1
    wait_for $queue_id 'process'
    STATUSES[$queue_id]='Complete'
    export ACTIVE=$(expr $ACTIVE - 1)
}

##
# Kill the entire Queue
#
function kill_all()
{
    echo "Shutting down..."
    for (( i=0; i < ${#STATUSES[@]}; i++ )); do
        if [ "${STATUSES[$i]}" = 'Running' ] ; then
            _kill_tree ${PROCESSES[$i]}
        elif [ "${STATUSES[$i]}" != 'Complete' ]; then
            STATUSES[$i]='Complete'
        fi
    done
    [ -f /tmp/procpid ] && rm /tmp/procpid
    echo "Done"
}

##
# Private methods
# ===============
#

##
# Monitor the queue and mark any completed processes
#
# @private
#
function _monitor()
{
    for (( i=0; i < ${#STATUSES[@]}; i++ )); do
        if [ ! -z ${PROCESSES[$i]} ] && ! kill -0 ${PROCESSES[$i]} &>/dev/null; then
            STATUSES[$i]='Complete'
            export ACTIVE=$(expr $ACTIVE - 1)
        fi
    done
    export STATUSES
}

##
# Verify that the queue is complete
#
# @private
#
function _queue_complete()
{
    for (( i=0; i < ${#STATUSES[@]}; i++)); do
        if [ "${STATUSES[$i]}" != 'Complete' ] ; then
            return 1
        fi
    done
    return 0
}

##
# Execute a command on the queue
#
# @param queue_id int
#
# @return pid
function _exec()
{
    local queue_id=$1
    local command=$(cut -d^ -f1 <(echo ${QUEUE[$queue_id]}))
    local logfile=$(cut -d^ -f2 <(echo ${QUEUE[$queue_id]}))

    if [ ! -z $logfile ]; then
        logfile="${queue_id}_${logfile}"
        if [ ! -z $LOGDIR ]; then
            [ ! -d $LOGDIR ] && mkdir -p $LOGDIR
            logfile="$LOGDIR/$logfile"
        fi

        if [ ! -f $logfile ] ; then
            touch $logfile
        fi
        echo "Triggering process ${queue_id} '${command}'" | tee -a $logfile
        eval "((${command}) 2>&1 | tee -a ${logfile}) &"
        RETURN_CODES[$queue_id]=$?
    else
        echo "Triggering process ${queue_id} '${command}'"
        eval "(${command}) &"
        RETURN_CODES[$queue_id]=$?
    fi
    local pid=$!
    PROCESSES[$queue_id]=$pid
    STATUSES[$queue_id]='Running'
    ACTIVE=$(expr $ACTIVE + 1)

    export PROCESSES
    export STATUSES
    export ACTIVE
    export RETURN_CODES
    return $pid
}

##
# Get the PID of the last triggered process
#
function _find_last_triggered_process()
{
    local running=0
    for ((i=0; i < ${#STATUSES[@]}; i++)); do
        if [ "${STATUSES[$i]}" = 'Running' ]; then
            running=${PROCESSES[$i]}
        fi
    done
    echo $running
}

##
# Get the internal process id for a given PID
#
function _find_by_pid()
{
    for ((i=0; i < ${#STATUSES[@]}; i++)); do
        if [ "${PROCESSES[$i]}" = "$pid" ]; then
            return $i
        fi
    done
}

##
# Kill the process tree for a given pid
#
# @param pid int
#
function _kill_tree()
{
    local pid=$1
    kill -stop ${pid}
    for child in $(ps -o pid --no-headers --ppid ${pid}); do
        _kill_tree $child
    done
    kill -SIGKILL ${pid}
}

trap "kill_all" EXIT
reset_queue
