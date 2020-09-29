#!/bin/bash
# Copyright (C) 2020, RTE (http://www.rte-france.com)

set -e

if ip addr | grep -q " kernelbr1:" ; then
    available_interface="kernelbr1"
    usage_interface="kernelbr1}"
else
    available_interface="ovs"
    usage_interface="ovs}      "
fi

usage()
{
    echo 'usage: add_vm.sh [-h] [--disk disk] --id id --interface interface'
    echo
    echo 'mandatory arguments:'
    echo "  --interface {kernelbr0,${usage_interface}  network interface to use"
    echo '  --id        id                             VM uniq id (number 0-99)'
    echo
    echo 'optional arguments:'
    echo '  -h, --help                                 show this help message and exit'
    echo '  -d, --disk disk                            disk to use (default disk)'
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
   [ "${interface}" != "${available_interface}" ] ; then
    if [ "${interface}" != "kernelbr1" ] && [ "${interface}" != "ovs" ] ; then
        echo "Invalid argument interface"
        usage
        exit 1
    else
        echo "Unavailable interface"
        usage
        exit 1
    fi
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

if [ -f /etc/pacemaker/guest"${id}".xml ] ; then
    echo "id already used"
    exit 1
fi

if ! rbd list | grep -q -E "^${disk}\$" ; then
    echo "Error could not found $disk in rbd pool"
fi

echo "Add VM guest$id with interface $interface using disk $disk on $(hostname)"

if [ "${interface}" = ovs ] ; then
    vm_config=/opt/setup/guest_ovs.xml
    if [ -f /etc/available_dpdk_socket ] ; then
        socketid="$(( $(cat /etc/available_dpdk_socket) +1 ))"
    else
        socketid=0
    fi
else
    vm_config=/opt/setup/guest_bridge.xml
fi
if ! rbd list | grep -q -E "^disk${id}\$" ; then
    # Avoid create the disk twice
    echo "Create disk"
    rbd copy "${disk}" disk"${id}"
fi
cp  ${vm_config} /tmp/guest"${id}".xml
sed "s/@VM_ID@/${id}/g" -i /tmp/guest"${id}".xml
sed "s/@UUID@/$(uuidgen)/g"  -i /tmp/guest"${id}".xml
sed "s/@INTERFACE@/${interface}/g"  -i /tmp/guest"${id}".xml
sed "s/@DPDK_SOCKET@/${socketid}/g"  -i /tmp/guest"${id}".xml

# Update OVS available socket
echo socketid >/etc/available_dpdk_socket

echo "Create VM guest$id"
virsh define /tmp/guest"${id}".xml >/dev/null
rm -f /tmp/guest"${id}".xml
virsh autostart --disable guest"${id}" >/dev/null
virsh dumpxml guest"${id}" >/etc/pacemaker/guest"${id}".xml
