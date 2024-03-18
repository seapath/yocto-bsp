#!/bin/bash
# Copyright (C) 2020, RTE (http://www.rte-france.com)
# SPDX-License-Identifier: Apache-2.0

set -e

source_dir=$(dirname "$0")
cd "${source_dir}"

usage()
{
    echo 'usage: add_vm.sh [-h] [--disk disk] --id id --interface interface'
    echo
    echo 'mandatory arguments:'
    echo '  --interface {ovs,kernelbr0,kernelbr1}  network interface to use'
    echo '  --id        id                         VM uniq id (number 0-99)'
    echo
    echo 'optional arguments:'
    echo '  -h, --help                             show this help message and exit'
    echo '  -d, --disk disk                        disk to use (default disk)'
}


id=
interface=
disk="disk"

options=$(getopt -o hd: --long disk:,id:,interface:,help -- "$@")
[ $? -eq 0 ] || {
    echo "Incorrect options provided"
    exit 1
}

eval set -- "$options"
while true; do
    case "$1" in
    -h|--help)
        usage
        exit 0
        ;;
    -d|--disk)
        shift
        disk="$1"
        ;;
    --id)
        shift
        id="$1"
        ;;
    --interface)
        shift
        interface="$1"
        ;;
    --)
        shift
        break
        ;;
    esac
    shift
done

if [ -z "${interface}" ] ; then
    echo "Error missing argument interface"
    usage
    exit 1
fi

if [ "${interface}" != "kernelbr0" ] && \
   [ "${interface}" != "kernelbr1" ] && \
   [ "${interface}" != "ovs" ] ; then
    echo "Invalid argument interface"
    usage
    exit 1
fi

if [ -z "${id}" ] ; then
    echo "Error missing argument id"
    usage
    exit 1
fi

if ! echo "${id}" | grep -qE '^[0-9]+$' ; then
    echo "Invalid argument id"
    usage
    exit 1
fi

source ./src/utils.sh

run_ssh_command seapath1 /opt/setup/addvm.sh "--id ${id} --interface ${interface} \
    -d \"${disk}\""
run_ssh_command seapath2 /opt/setup/addvm.sh "--id ${id} --interface ${interface} \
    -d \"${disk}\""
run_ssh_command seapath1 crm "config primitive guest${id} \
   ocf:heartbeat:VirtualDomain \
   params config=/etc/pacemaker/guest${id}.xml \
   hypervisor=\"qemu:///system\" \
   migration_transport=\"ssh\" meta allow-migrate=\"true\" \
   op start timeout=\"120s\" \
   op stop timeout=\"120s\" \
   op monitor timeout=\"30\" interval=\"10\" depth=\"0\"" 2>/dev/null
if ! run_ssh_command seapath2 crm "resource status" | \
    grep -E -q "guest${id}.*ocf::heartbeat:VirtualDomain" ; then
    echo "Error the VM was not installed correctly"
    exit 1
fi
