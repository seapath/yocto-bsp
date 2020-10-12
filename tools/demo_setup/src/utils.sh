# Copyright (C) 2020, RTE (http://www.rte-france.com)
# This program is distributed under the Apache 2 license.

MACHINES="votp1 votp2 observer"
SSH_OPTIONS='-q -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'

VOTP1_ADDR=192.168.217.131
VOTP2_ADDR=192.168.217.132
OBSERVER_ADDR=192.168.217.133
NTP_ADDR=192.168.217.134

# params: host command command_arg
run_ssh_command()
{
    host="$1"
    command="$2"
    args="$3"
    ip_addr="$(eval echo \${${host^^}_ADDR})"
    #echo "ssh $host $command $args"
    ssh ${SSH_OPTIONS} root@"$ip_addr" -- "$command" $args
}

# param 1 iteration number before failed
# param 2 seconds to wait between iteration
# param 3 command to run
wait_until()
{
    i="$1"
    wait="$2"
    shift
    shift
    command="$@"
    while ! eval $command && [ $i -gt 0 ] ; do
        sleep $wait
    let i--
    done
}
