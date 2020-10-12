#!/bin/bash
# Copyright (C) 2020, RTE (http://www.rte-france.com)
# This program is distributed under the Apache 2 license.

set -e

if [ -z "$__RUNNING_FROM_SCRIPT__" ] ; then
    echo "Error this script must not be run manualy" 1>&2
    exit 1
fi
source ./src/utils.sh

setup_pacemaker()
{
    echo "Configure pacemacker"
    # Check corosync/pacemacker are up and the cluster is ready
    wait_until 10 3 "run_ssh_command votp1 crm status | grep -q 'Online: \[ votp1 votp2 \]'"
    run_ssh_command votp1 /opt/setup/setup_pacemaker.sh
    pacemaker_config=$(run_ssh_command votp2 crm "configure show")
    echo "${pacemaker_config}" |grep -q "stonith-enabled=false"
    echo "${pacemaker_config}" |grep -q "no-quorum-policy=ignore"
}

setup_ceph_monitors()
{
    echo "Setup Ceph monitors"
    run_ssh_command votp1 /opt/setup/setup_mon_votp1.sh
    run_ssh_command votp2 /opt/setup/setup_mon_votp2.sh
    run_ssh_command observer /opt/setup/setup_mon_observer.sh

    # Check the 3 mon are up
    wait_until 10 1 'run_ssh_command observer ceph status | grep -q "mon: 3 daemons, quorum"'

    run_ssh_command votp1 systemctl 'restart ceph-mon@votp1'
    run_ssh_command votp2 systemctl 'restart ceph-mon@votp2'
    run_ssh_command observer systemctl 'restart ceph-mon@observer'

    # Check the 3 mon are up
    wait_until 10 1 'run_ssh_command votp2 ceph status | grep -q "mon: 3 daemons, quorum"'
}

setup_ceph_osds()
{
    echo "Setup Ceph OSDs"
    run_ssh_command votp1 /opt/setup/setup_osd.sh
    run_ssh_command votp2 /opt/setup/setup_osd.sh
    run_ssh_command votp2 mount |grep -q '/dev/sda3 on /var/lib/ceph/osd/ceph-1'
    run_ssh_command votp1 mount |grep -q '/dev/sda3 on /var/lib/ceph/osd/ceph-0'
    run_ssh_command votp2 ceph "osd stat" | grep -q "2 osds"
}

setup_rbd_pool()
{
    echo "setup rbd pool"
    run_ssh_command votp1 /opt/setup/setup_rbd.sh
    run_ssh_command votp1 /opt/setup/setup_libvirt.sh
    run_ssh_command votp2 /opt/setup/setup_libvirt.sh
}

# Wait for machine
wait_machines_up()
{
    echo "Waits until all machines are rebooted"
    flag=0
    while [ "$flag" -ne 1 ] ; do
        flag=1
        for machine in ${MACHINES} ; do
            ip="$(eval echo \${${machine^^}_ADDR})"
            if ! ping -c1 "${ip}" -W 1 1>/dev/null 2>&1 ; then
                echo "Waiting for $machine"
                flag=0
            fi
        done
    done
}

wait_machines_up
setup_pacemaker
setup_ceph_monitors
setup_ceph_osds
setup_rbd_pool
echo "Your cluster is now ready to host VMs"
#echo "You can monitor the distributed storaged at http://192.168.217.133:8080"
#echo "login admin ; password admin"
