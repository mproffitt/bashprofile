##
# Process Manager script
#
# @Author: Martin Proffitt <mproffitt@choclab.net>
# @Website: www.choclab.net
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
export THREAD_SLEEP=0.05
export QUEUE=()
export PROCESSES=()
export STATUSES=()
export ORIGINAL=()
export RETURN_CODES=()
export RUNNING=()
export ACTIVE=0
export MANAGER_RUNNING=1
export EXPORTED_QUEUE=''
export USE_FIFO=true

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
    unset QUEUE
    unset PROCESSES
    unset STATUSES
    unset RETURN_CODES
    unset ORIGINAL
    unset RUNNING
    unset EXPORTED_QUEUE

    export QUEUE=()
    export PROCESSES=()
    export STATUSES=()
    export RETURN_CODES=()
    export ORIGINAL=()
    export RUNNING=()
    export ACTIVE=0
    export EXPORTED_QUEUE=''
}

function restart_queue()
{
    local args=''
    if ! $USE_FIFO; then
        args='-fg'
    fi
    unset PROCESSES
    export PROCESSES=()
    STATUSES=("${ORIGINAL[@]}")
    export STATUSES
    for (( i=0; i < ${#STATUSES[@]}; i++ )); do
        RETURN_CODES[$i]=-1
    done
    export RETURN_CODES
    print_queue
    process $args
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
        echo "$i - ${STATUSES[$i]}: $(sed 's/\(.*\)~~~.*/\1/' <<<${QUEUE[$i]})"
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
    local command=''
    local logfile=''
    local block=false
    local waitfor=-1
    local wait=false
    local push=false

    while [ ${#@} -gt 0 ]; do
        argument=$1
        case $argument in
            '-LF')
                logfile=$2
                shift
                ;;
            *)
                case "$(cut -d\= -f1 <<<$argument)" in
                    'block')
                        [ "$(cut -d\= -f2 <<<$argument | tr [:upper:] [:lower:])" = 'true' ] && block=true
                        ;;
                    'waitfor')
                        waitfor=$(cut -d\= -f2 <<<$argument | tr [:upper:] [:lower:])
                        wait=true
                        ;;
                    'push')
                        [ "$(cut -d\= -f2 <<<$argument | tr [:upper:] [:lower:])" = 'true' ] && push=true
                        ;;
                    *)
                        command="$command $argument"
                        ;;
                esac
        esac
        shift
    done

    local status='Ready'
    if $block && $wait; then
        status="Waiting=$waitfor|Block"
    elif $block; then
        status='Block'
    elif $wait; then
        status="Waiting=$waitfor"
    fi

    if $push; then
        _reindex_existing_waits
        QUEUE=("$command~~~$logfile" "${QUEUE[@]}")
        STATUSES=("$status" "${STATUSES[@]}")
        if [ ${#ORIGINAL[@]} -ne 0 ] ; then
            ORIGINAL=("$status" "${ORIGINAL[@]}")
        fi
    else
        QUEUE+=("$command~~~$logfile")
        STATUSES+=("$status")
        if [ ${#ORIGINAL[@]} -ne 0 ] ; then
            ORIGINAL+=("$status")
        fi
    fi

    export QUEUE
    export STATUSES
    export ORIGINAL
    export ACTIVE
    return $(expr ${#QUEUE[@]} - 1)
}

##
# Push an item onto the top of the queue instead of appending it to the bottom
#
# @see `process_manager::queue`
function queue_push()
{
    export STATUSES
    queue "$@" "push=true"
    return $?
}

##
# Triggers the process manager
#
function process()
{
    export USE_FIFO=true
    local foreground=false
    for arg; do
        case "$arg" in
            '-fg')
                foreground=true
        esac
    done
    for (( i=0; i < ${#STATUSES[@]}; i++ )); do
        RETURN_CODES[$i]=-1
        EXPORTED_QUEUE="$EXPORTED_QUEUE%%%${QUEUE[$i]}"
    done
    export RETURN_CODES
    export EXPORTED_QUEUE

    if $foreground; then
        export USE_FIFO=false
        _process_queue
        return $?
    fi
    _process_queue &>/dev/null &
    ${HOME}/.bashprofile/bin/processview.py
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
# Kill the entire Queue
#
function kill_all()
{
    inform "Shutting down..."
    for (( i=0; i < ${#STATUSES[@]}; i++ )); do
        if [ "${STATUSES[$i]}" = 'Running' ] ; then
            _kill_tree ${PROCESSES[$i]}
        elif [ "${STATUSES[$i]}" != 'Complete' ]; then
            STATUSES[$i]='Complete'
        fi
    done
    inform "Done"
}

##
# Start the queue and execute any commands contained within it
#
# Queue status can be tested against the MANAGER_RUNNING environment variable
#
function _process_queue()
{
    ORIGINAL=(${STATUSES[@]})
    export ORIGINAL
    sleep 2
    if $USE_FIFO; then
        exec 3<>/dev/tcp/127.0.0.1/8888
    fi
    while true ; do
        export MANAGER_RUNNING=0
        for (( i=0; i < ${#QUEUE[@]}; i++ )); do
            if [ "${STATUSES[$i]}" = 'Complete' ]; then
                continue
            fi

            if [ $ACTIVE -lt ${PROCESSORS} ] ; then
                case "$(cut -d= -f1 <<<${STATUSES[$i]})" in
                    'Ready')
                        _exec $i
                        ;;
                    'Block')
                        _exec $i
                        _block $i
                        ;;
                    'Waiting')
                        local pids=($(cut -d= -f2 <<<"${STATUSES[$i]}" | cut -d\| -f1 | tr ',' ' '))
                        local ready=true
                        for ((j=0; j < ${#pids[@]}; j++)); do
                            local index=${pids[$j]}
                            case "${pids[$j]}" in
                                'first')
                                    index=0
                                    ;;
                                'last')
                                    index=$(expr ${#STATUSES[@]} - 1)
                                    ;;
                                'prev')
                                    index=$(expr $i - 1)
                                    ;;
                                'middle')
                                    index=$(expr ${#STATUSES[@]} / 2)
                                    ;;
                                'next')
                                    index=$(expr $i + 1)
                                    ;;
                            esac
                            if [ "${STATUSES[$index]}" != 'Complete' ]; then
                                # Don't wait for ourself
                                if [ $index -eq $i ]; then
                                    continue
                                fi
                                ready=false
                            fi
                        done
                        if $ready; then
                            _exec $i
                            if grep -q '.*|Block$' <<<${STATUSES[$i]}; then
                                _block $i
                            fi
                        fi
                        ;;
                esac
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
# Iterate over all statuses when pushing elements on top of the queue and update the indexes
#
function _reindex_existing_waits()
{
    # Update location of all waiting statuses to point at new IDs
    for ((i=0; i < ${#STATUSES[@]}; i++)); do
        if [ "$(cut -d= -f1 <<<${STATUSES[$i]})" = 'Waiting' ]; then
            pids=($(cut -d= -f2 <<<"${STATUSES[$i]}" | cut -d\| -f1 | tr ',' ' '))
            new_pids='Waiting='
            for pid in ${pids[@]}; do
                if [[ $pid =~ [0-9]+ ]]; then
                    new_pids="$new_pids,$(expr $pid + 1)"
                else
                    new_pids="$new_pids,$pid"
                fi
            done
            if [ "$(cut -d\| -f2 <<<${STATUSES[$i]})" = 'Block' ]; then
                new_pids="$new_pids|Block"
            fi
            new_pids=$(sed 's/=,/=/' <<<$new_pids)
            warn "Changing ${STATUSES[$i]} to ${new_pids}"
            STATUSES[$i]=$new_pids
        fi
    done
}

##
# Monitor the queue and mark any completed processes
#
# @private
#
function _monitor()
{
    local EXPORTED_STATUSES=''
    local EXPORTED_RETURN_CODES=''
    for (( i=0; i < ${#STATUSES[@]}; i++ )); do
        if [ ! -z ${PROCESSES[$i]} ] && ! kill -0 ${PROCESSES[$i]} &>/dev/null; then
            STATUSES[$i]='Complete'
            RUNNING=($(
                for ((j=0; j < ${#RUNNING[@]}; j++)); do
                    if [ ! -z ${RUNNING[$j]} ] && [ $i -ne ${RUNNING[$j]} ]; then
                        echo ${RUNNING[$j]}
                    fi
                done
            ))
            export ACTIVE=${#RUNNING[@]}
        fi
        EXPORTED_STATUSES="${EXPORTED_STATUSES};${STATUSES[$i]}"
        EXPORTED_RETURN_CODES="${EXPORTED_RETURN_CODES};${RETURN_CODES[$i]}"
    done
    export STATUSES
    if $USE_FIFO; then
        echo "$EXPORTED_STATUSES|||$EXPORTED_RETURN_CODES" >&3
    fi
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
            debug "Waiting for $i to complete (status = ${STATUSES[$i]})"
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
    local command=$(sed 's/\(.*\)~~~.*/\1/' <<<${QUEUE[$queue_id]})
    local logfile=$(sed 's/.*~~~\(.*\)/\1/' <<<${QUEUE[$queue_id]})

    if [ ! -z $logfile ]; then
        logfile="${queue_id}_${logfile}"
        if [ ! -z $LOGDIR ]; then
            [ ! -d $LOGDIR ] && mkdir -p $LOGDIR
            logfile="$LOGDIR/$logfile"
        fi

        if [ ! -f $logfile ] ; then
            touch $logfile
        fi
        inform "Triggering process ${queue_id} '${command}'" | tee -a $logfile
        eval "((${command}) 2>&1 | tee -a ${logfile}) &"
        RETURN_CODES[$queue_id]=$?
    else
        inform "Triggering process ${queue_id} '${command}'"
        eval "(${command}) &"
        RETURN_CODES[$queue_id]=$?
    fi
    local pid=$!
    PROCESSES[$queue_id]=$pid
    STATUSES[$queue_id]='Running'
    ACTIVE=$(expr $ACTIVE + 1)
    RUNNING[$ACTIVE]=$queue_id

    export PROCESSES
    export STATUSES
    export ACTIVE
    export RUNNING
    export RETURN_CODES
    return $pid
}

##
# Block until the process at queue_id is complete
#
# @param queue_id int
#
# Blocks the entire queue until a given ID has finished its execution
#
function _block()
{
    local queue_id=$1
    wait_for $queue_id 'process'
    STATUSES[$queue_id]='Complete'
    export ACTIVE=$(expr $ACTIVE - 1)
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

##
# Simple test for the queue mechanism
function test_queue()
{
    inform "Populating QUEUE"
    for ((i=0; i < 100; i++)); do
        command="echo 'hello world $i' && sleep 0.5";
        if [ $i -eq 18 ]; then
            queue $command waitfor=16
        elif [ $i -eq 5 ]; then
            queue $command waitfor=10,middle,last push=true
        elif [ $i -eq 38 ] ; then
            queue $command waitfor=1,5,27
        elif [ $i -eq 74 ]; then
            queue $command waitfor=12,37,44 block=true
        elif [ $i -eq 10 ] || [ $i -eq 95 ]; then
            queue "echo 'hello world $i' && sleep 10" block=true
        elif [ $i -eq 50 ]; then
            queue $command push=true
        else
            queue $command
        fi
    done
    inform "Done populating"
    process $@
}
