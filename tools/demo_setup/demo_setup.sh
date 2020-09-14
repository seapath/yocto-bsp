#!/bin/bash
set -e

source_dir=$(dirname "$0")

usage()
{
    echo 'usage: demo_setup.sh [-h] [--config config_file]'
    echo
    echo 'optional arguments:'
    echo '  -h, --help                show this help message and exit'
    echo '  -c, --config config_file  config file to use (default config.ini)'
    echo
    echo 'demo_setup requiere a config file.'
    echo 'See HOWTO.pdf for explainations and the examples directory to find examples.'
}

config_file="$(pwd)/config.ini"

options=$(getopt -o hc: --long help,config: -- "$@")
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
    -c|--config)
        shift
        config_file="$1"
        if [ ! -f "${config_file}" ] ; then
            echo "error could not found ${config_file}"
            echo
            usage
            exit 1
        fi
        config_file=$(readlink -f "${config_file}")
        ;;
    --)
        shift
        break
        ;;
    esac
    shift
done

cd "${source_dir}"
source src/utils.sh
MACHINES="votp1 votp2 observer"

VARIABLES="GENERAL_USE_DPDK \
    VOTP1_INITIAL_IP \
    VOTP2_INITIAL_IP \
    OBSERVER_INITIAL_IP \
    VOTP1_NETWORK_INTERFACE \
    VOTP2_NETWORK_INTERFACE \
    OBSERVER_NETWORK_INTERFACE \
"
BRIDGE_VARIABLES="VOTP1_BRIDGE_INTERFACE VOTP2_BRIDGE_INTERFACE"
OVS_VARIABLES="VOTP1_NIC VOTP2_NIC"

# Params machine, parameter none, parameter
check_no_null_parameter()
{
    machine="$1"
    parameter_name="$2"
    parameter="$3"
    if [ -z "${parameter}" ] ;then
        echo "Invalid parameter ${parameter_name} for ${machine}"
        exit 1
    fi
}

# Params: section variable
get_ini_variable()
{
    section="$1"
    variable="$2"
    awk -F'=' -v section="[${section}]" -v k="${variable}"  '
    $0==section{ flag=1; next }  # check if we are in the right section
    /\[/{ flag=0; next }         # if we are not unset the flash
    flag && $1==k{ print $2 }    # If flag is set and variable print the value
    ' "${config_file}"
}

# Check we get all parameters
check_parameters()
{
    local parameters
    if [ "${GENERAL_USE_DPDK}" = "yes" ] ; then
        parameters="${VARIABLES} ${OVS_VARIABLES}"
    else
        parameters="${VARIABLES} ${BRIDGE_VARIABLES}"
    fi
    local error
    for parameter in ${parameters} ; do
        local variable
        variable="$(eval echo \${${parameter}})"
        if [ -z "${variable}" ] ; then
            error=1
            section=$(echo "${parameter}" | cut -d '_' -f 1)
            config=$(echo "${parameter}" | cut -d '_' -f 2-)
            echo "Missing configuration ${config} in section ${section,,}"
        fi
    done
    if [ -n "${error}" ] ; then
        exit 1
    fi
}

# Print configuration
print_preliminary_message()
{
    echo "VOTP1_INITIAL_IP=${VOTP1_INITIAL_IP}"
    echo "VOTP2_INITIAL_IP=${VOTP2_INITIAL_IP}"
    echo "OBSERVER_INITIAL_IP=${OBSERVER_INITIAL_IP}"
    echo "GENERAL_USE_DPDK=${GENERAL_USE_DPDK}"
    echo "VOTP1_NETWORK_INTERFACE=${VOTP1_NETWORK_INTERFACE}"
    echo "VOTP2_NETWORK_INTERFACE=${VOTP2_NETWORK_INTERFACE}"
    echo "OBSERVER_NETWORK_INTERFACE=${OBSERVER_NETWORK_INTERFACE}"
    if [ "${GENERAL_USE_DPDK}" != "yes" ] ; then
        echo "VOTP1_BRIDGE_INTERFACE=${VOTP1_BRIDGE_INTERFACE}"
        echo "VOTP2_BRIDGE_INTERFACE=${VOTP2_BRIDGE_INTERFACE}"
    else
        echo "VOTP1_NIC=${VOTP1_NIC}"
        echo "VOTP2_NIC=${VOTP2_NIC}"
    fi
    echo -n "Please check settings from above and all machines are up before"
    echo " continuing"
    read -s -p "Press enter when you are ready"
    echo
}

# Ping all the machine
check_machine_availability()
{
    for machine in ${MACHINES} ; do
        initial_ip="$(eval echo \${${machine^^}_INITIAL_IP})"
        if ! ping -c 1 -W 1  "${initial_ip}" 2>&1 1>/dev/null ; then
            echo "$machine doesn't respond to ping"
            exit 1
        fi
    done
    if ! ping -c 1 -W 1  "${NTP_ADDR}" 2>&1 1>/dev/null ; then
        echo "NTP doesn't respond to ping"
        exit 1
    fi
}
# Create a tarball with the content of root directory
create_tar()
{
    tar -C root -cf /tmp/setup.tar .
}

# For the given machine, copy and uncompress setup.tar and call
# /opt/setup/setup.sh script
setup_marchine()
{
    machine="$1"
    echo "Setup $machine"
    initial_ip="$(eval echo \${${machine^^}_INITIAL_IP})"
    network_interface="$(eval echo \${${machine^^}_NETWORK_INTERFACE})"
    check_no_null_parameter ${machine} initial_ip ${initial_ip}
    check_no_null_parameter ${machine} network_interface ${network_interface}
    # Check the machine have been reflash
    if ! ssh ${SSH_OPTIONS} root@${initial_ip} -- hostname |grep -Eq '^votp$'
    then
        echo "Error the machine has not been reinitialized"
        exit 1
    fi
    if [ "${machine}" = "observer" ] ; then
        setup_options="--host ${machine} \
                       --network-interface ${network_interface}"
    else
        use_dpdk="${GENERAL_USE_DPDK}"
        if [ "${use_dpdk}" = "yes" ] ; then
            nic="$(eval echo \${${machine^^}_NIC})"
            check_no_null_parameter ${machine} nic ${nic}
            setup_options="--host ${machine} \
                           --network-interface ${network_interface} \
                           --ovs \
                           --nic ${nic}"
        elif [ "${use_dpdk}" = "no" ] ; then
            bridge_interface="$(eval echo \${${machine^^}_BRIDGE_INTERFACE})"
            check_no_null_parameter ${machine} bridge_interface \
                ${bridge_interface}
            setup_options="--host ${machine} \
                           --network-interface ${network_interface} \
                           --bridge-interface ${bridge_interface}"
        else
            echo "Invalid parameter use_dpdk for ${machine}"
            exit 1
        fi
    fi
    scp ${SSH_OPTIONS} /tmp/setup.tar root@${initial_ip}:/setup.tar
    ssh ${SSH_OPTIONS} root@${initial_ip} -- tar -C / -xf /setup.tar
    ssh ${SSH_OPTIONS} root@${initial_ip} -- /opt/setup/setup.sh \
        ${setup_options}
    # The reboot command through ssh can return an error because the reboot
    # operation close the ssh connexion
    set +e
    ssh ${SSH_OPTIONS} root@${initial_ip} -- reboot 2>/dev/null
    set -e
}


if [ ! -f "${config_file}" ] ; then
    echo "Error could not find config file: ${config_file}"
    exit 1
fi
for variable in ${VARIABLES} ${BRIDGE_VARIABLES} ${OVS_VARIABLES} ; do
    ini_section=$(echo $variable | cut -d '_' -f 1)
    ini_variable=$(echo $variable | cut -d '_' -f 2-)
    eval "${variable}=$(get_ini_variable ${ini_section,,} ${ini_variable})"
done


check_parameters
print_preliminary_message
check_machine_availability
create_tar
for machine in ${MACHINES} ; do
    setup_marchine ${machine}
done
# Wait reboot
__RUNNING_FROM_SCRIPT__=1 ./src/setup_2nd_step.sh
