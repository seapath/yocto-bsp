#!/bin/bash
# Copyright (C) 2020, RTE (http://www.rte-france.com)

set -e

usage()
{
    echo
    echo 'usage: setup.sh [-h] [--ovs] [--nic nic] [--bridge-interface interface] --host host --network-interface interface'
    echo
    echo 'mandatory arguments:'
    echo '  --host {votp1,votp2,observer}  host to setup'
    echo '  --network-interface interface  network interface to use'
    echo
    echo 'optional arguments:'
    echo '  -h, --help                     show this help message and exit'
    echo '  --nic nic                      PCI address of the network interface to use with OVS (require if --ovs)'
    echo '  --bridge-interface             network to use with network bridge (require if not observer and no --ovs was given)'
}

host=
eth=
eth2=
ovs=no
nic=

options=$(getopt -o h --long host:,ovs,network-interface:,nic:,bridge-interface:,help -- "$@")
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
    --ovs)
        ovs=yes
        ;;
    --network-interface)
        shift
        eth="$1"
        ;;
    --bridge-interface)
        shift
        eth2="$1"
        ;;
    --host)
        shift
        host="$1"
        ;;
    --nic)
        shift
        nic="$1"
        ;;
    --)
        shift
        break
        ;;
    esac
    shift
done

source /opt/setup/setup_config.sh
source /opt/setup/setup_utils.sh

generate_local_mac_address()
{
    printf 'ea:9e:cf:%02x:%02x:%02x\n' \
        $[RANDOM%256] $[RANDOM%256] $[RANDOM%256]
}

create_logs_directories()
{
    echo "Create logs directories"
    mkdir -p /var/log.tmp/
    cp -a /var/log/* /var/log.tmp/
    mv /var/log.tmp /var/log
    mkdir -p /var/log/corosync
    rm -f /var/tmp /var/log
    ln -sf /tmp /var/tmp
    mkdir -p /var/log/qemu /var/log/corosync /var/log/cluster
    chmod 777 /var/log/qemu /var/log/corosync /var/log/cluster
}

setup_hostname()
{
    echo "Set hostname"
    echo "$host" >/etc/hostname
}

setup_ntp()
{
    echo "Configure NTP address"
    replace ntp_addr "${NTP_ADDR}" /etc/systemd/timesyncd.conf
}

setup_hosts()
{
    echo "Update /etc/hosts"
    {
        echo "${VOTP1_ADDR} votp1"
        echo "${VOTP2_ADDR} votp2"
        echo "${OBSERVER_ADDR} observer"
    } >>/etc/hosts
    sed "s/$host/$host rbd/" -i /etc/hosts
}

setup_observer_network()
{
    echo "Setup network"
    rm -f /etc/systemd/network/00*
    cp /opt/setup/observer/00-en.network /etc/systemd/network/
    replace interface "${eth}" /etc/systemd/network/00-en.network
    replace observer_addr "${OBSERVER_ADDR}" /etc/systemd/network/00-en.network
    replace gateway_addr "${GATEWAY_ADDR}" /etc/systemd/network/00-en.network
}

setup_observer_systemd()
{
    echo "Disable unwanted services in observer"
    systemctl disable ovs-vswitchd.service >/dev/null 2>/dev/null
    systemctl disable ovsdb-server.service >/dev/null 2>/dev/null
    systemctl disable openvswitch.service >/dev/null 2>/dev/null
    systemctl disable libvirtd.service >/dev/null 2>/dev/null
    systemctl disable docker.service >/dev/null 2>/dev/null
    systemctl disable votp-config_ovs.service >/dev/null 2>/dev/null
}

setup_observer()
{
    setup_observer_network
    setup_observer_systemd
}

setup_hypervisor_network()
{
    echo "Configure Network"
    replace enbridge0 "${eth}" /etc/systemd/network/00-enkernelbr0.network
    replace mac "$(generate_local_mac_address)" \
        /etc/systemd/network/00-kernelbr0.netdev
    if [ "$host" = "votp1" ]
    then
        ip_addr="${VOTP1_ADDR}"
    else
        ip_addr="${VOTP2_ADDR}"
    fi
    replace ip_addr "${ip_addr}" /etc/systemd/network/00-kernelbr0.network
    replace gateway_addr "${GATEWAY_ADDR}" \
        /etc/systemd/network/00-kernelbr0.network
    if [ "${ovs}" = "no" ]
    then
        cp /opt/setup/no_ovs/* /etc/systemd/network/
        replace enbridge1 "${eth2}" \
            /etc/systemd/network/00-enkernelbr1.network
        replace mac "$(generate_local_mac_address)" \
            /etc/systemd/network/00-kernelbr1.netdev
    else
        replace dpdk_nic "${nic}" /opt/setup/setup_ovs.sh
    fi
}

setup_hypervisor_systemd()
{
    echo "Configure systemd"
    if [ "${ovs}" = "yes" ]
    then
        cp /lib/systemd/system/pacemaker.service \
            /etc/systemd/system/pacemaker.service
        sed '/^Requires=corosync.service/a After=setup_ovs.service' -i \
            /etc/systemd/system/pacemaker.service
        systemctl daemon-reload
        systemctl enable setup_ovs.service >/dev/null 2>/dev/null
    fi
    systemctl enable corosync pacemaker >/dev/null 2>/dev/null
}

setup_hypervison_ceph_osd_partition()
{
    echo "Create Ceph OSD partition"
    parted -s /dev/sda mkpart primary xfs 10G 100% >/dev/null
    partprobe /dev/sda >/dev/null

    echo "Format ceph OSD partition"
    mkfs.xfs -f  /dev/sda3 >/dev/null

    echo "Update fstab"
    if [ "$host" = "votp1" ] ; then
        ceph_osd_number=0
    else
        ceph_osd_number=1
    fi
    echo "/dev/sda3  /var/lib/ceph/osd/ceph-${ceph_osd_number} xfs \
        rw,noatime,inode64,logbufs=8,logbsize=256k 0 0" >> /etc/fstab
}

setup_hypservisor()
{
    setup_hypervisor_network
    setup_hypervisor_systemd
    setup_hypervison_ceph_osd_partition
}

setup_ceph_conf()
{
    echo "Update ceph configuration"
    replace votp1_addr "${VOTP1_ADDR}" /etc/ceph/ceph.conf
    replace votp2_addr "${VOTP2_ADDR}" /etc/ceph/ceph.conf
    replace observer_addr "${OBSERVER_ADDR}" /etc/ceph/ceph.conf
    replace public_network "${PUBLIC_NETWORK}" /etc/ceph/ceph.conf
}

# Check parameters
check_arguments()
{
    if [ -z "$host" ] ; then
        echo "Error: host parameter not set"
        usage
        exit 1
    fi
    if [[ "$host" != "votp1" && "$host" != "votp2" && "$host" != "observer" ]]
    then
        echo "Error: bad parameter host: $host"
        usage
        exit 1
    fi
    if [ -z "$eth" ] ; then
        echo "Error: network-interface not set"
        usage
        exit 1
    fi
    if ! ip addr | grep -q " ${eth}:" || [ -z "$eth" ]
    then
        echo "Error: Interface $eth was not found in $host"
        exit 1
    fi

    if [ "$host" != "observer" ] ; then
        if [ "${ovs}" = "yes" ]
        then
            if [ -z "$nic" ] ; then
                echo "Error: nic parameter not set"
                usage
                exit 1
            fi
            if ! echo "$nic" | grep -q -E '^[0-9]+:[0-9]+:[0-9]+\.[0-9]+$' ; then
                echo "Error: $nic is not a nic"
                echo "nic must be a PCI address like 0000:02:00.0"
                usage
                exit 1
            fi
            if ! dpdk-devbind --status-dev net |grep -q "$nic"
            then
                echo "Error: nic $nic was not found in $host"
                exit 1
            fi
            if dpdk-devbind --status-dev net |grep "$nic" |grep -q "$eth"
            then
                echo "Error: nic interface must be different of network-interface"
                exit 1
            fi
        else
            if [ -z "$eth2" ] ; then
                echo "Error: bridge-interface parameter not set"
                usage
                exit 1
            fi
            if [ "$eth" = "$eth2" ] ; then
                echo "Error: bridge-interface must be different of network-interface"
                usage
                exit 1
            fi
            if ! ip addr | grep -q "${eth2}:"
            then
                echo "Error: Interface $eth2 was not found in $host"
                exit 1
            fi
        fi
    fi
}

check_arguments
setup_hostname
setup_hosts
setup_ntp
if [ "$host" != "observer" ] ; then
    setup_hypservisor
else
    setup_observer
fi
setup_ceph_conf
create_logs_directories
