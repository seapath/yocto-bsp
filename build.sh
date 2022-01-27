#!/bin/bash
#
# Yocto build system initiator.
#
# Copyright (C) 2019-2020 Savoir-faire Linux, Inc.
# This program is distributed under the Apache 2 license.

# Name:       print_usage
# Brief:      Print script usage

# Set image to build, default to core-image-minimal
print_usage()
{
    echo "This script builds a yocto distribution

./$(basename ${0}) [OPTIONS]

Options:
        (-d|--dl-dir)           <path>                  Yocto downloads cache directory
        (-i|--image)            <image>                 Yocto target image
        (--distro)              <distro>                Yocto target distribution
        (-m|--machine)          <machine>               Yocto target machine
        (-s|--sstate-dir)       <path>                  Yocto build cache directory
        (-k|--sdk)                                      Compile the SDK
        (-r|--remove-build-dir)                         Remove Yocto build directory
        (-v|--verbose)                                  Verbose mode
        (--debug)                                       Print all commands
        (--no-layers-update)                            Don't auto update bblayers.conf
        (-h|--help)                                     Display this help message
        (--)                    <command>               Command to launch
        "
}

# Name:       apply_patch
# Brief:      Test and apply a patch file if needed
# Param[in]:  Patch file
apply_patch()
{
  if patch --dry-run --silent -F 0 --strip=1 --force --input ${1} >/dev/null
  then
    patch --strip=1 -F 0 --force --input ${1}
  fi
}

# Name:       parse_options
# Brief:      Parse options from command line
# Param[in]:  Command line parameters
parse_options()
{
    ARGS=$(getopt -o "d:i:khm:rs:v" -l "distro:,dl-dir:,help,image:,machine:,no-layers-update,debug,remove-build-dir,sdk,sstate-dir:,verbose" -n "build.sh" -- "$@")

    #Bad arguments
    if [ $? -ne 0 ]; then
        exit 1
    fi

    eval set -- "${ARGS}"

    while true; do
        case "$1" in
            --distro)
                export DISTRO=$2
                shift 2
                ;;

            -d|--dl-dir)
                if [ ! -d "$2" ]; then
                    echo "Fatal: specified dl-dir does not exist"
                    exit 1
                fi
                export DL_DIR=$(readlink -f $2)
                shift 2
                ;;

            --debug)
                set -x
                shift
                ;;

            -i|--image)
                export IMAGE=$2
                shift 2
                ;;
            --no-layers-update)
                NO_LAYERS_UPDATE=yes
                shift
                ;;
            -m|--machine)
                export MACHINE=$2
                shift 2
                ;;

            -r|--remove-build-dir)
                REMOVE_BUILDDIR=1
                shift
                ;;

            -k|--sdk)
                COMPILE_SDK=1
                shift
                ;;

            -s|--sstate-dir)
                if [ ! -d "$2" ]; then
                    echo "Fatal: specified state-dir does not exist"
                    exit 1
                fi
                export SSTATE_DIR=$(readlink -f $2)
                shift 2
                ;;

            --meta-list-file)
                export META_LIST_FILE=$(readlink -f $2)
                shift 2
                ;;

            -v|--verbose)
                VERBOSE=1
                shift
                ;;

            -h|--help)
                print_usage
                exit 1
                shift
                break
                ;;

            -|--)
                shift
                CMD=$@
                break
                ;;

            *)
                print_usage
                exit 1
                shift
                break
                ;;
        esac
    done
}

# Name:       run_cmd
# Brief:      Run given command with enhanced display and return code checked
# Param[in]:  Command description to print
# Param[in]:  The command itself
run_cmd()
{
  # Description to display
  description=$1
  print_noln "$description"

  # Remove description from parameters
  shift
  # Launch command
  eval $@

  # Check command result, exit on error
  check_result $?

  # Print ok otherwise
  print_ok
}

# Name        Update layers
# Brief       Add layers in bblayers.conf using bitbake-layers add-layer
update_layers()
{
    if [ -n "${NO_LAYERS_UPDATE}" ] ; then
        return 0
    fi

    local layers_filter_pattern
    if [ -s "${TOPDIR}/layers.blacklist" ] ; then
        while read layer
        do
            layers_filter_pattern="$layers_filter_pattern${sep}${SOURCESDIR}/${layer}"
            local sep="|"
        done < ${TOPDIR}/layers.blacklist
        layers_filter_pattern="($layers_filter_pattern)"
    else
        layers_filter_pattern="!()"
    fi

    local layers_to_add=$(find "${SOURCESDIR}"/meta-* \
        "${SOURCESDIR}"/poky/meta-* \
        -type f \
        -path '*/conf/layer.conf' | \
        xargs -n1 dirname | \
        xargs -n1 dirname | egrep -v "^${layers_filter_pattern}$")

    if [ -n "${layers_to_add}" ] ; then
        run_cmd "update layers" "bitbake-layers add-layer ${layers_to_add}"
    fi
}

##########################
########## MAIN ##########
##########################

# Include scripting tools
. scripts/bash_scripting_tools/functions.sh

#### Local vars ####
# Not verbose by default
export VERBOSE=0
# Keep directory to retrieve tools
TOPDIR=$(dirname $(readlink -f ${0}))
BUILDDIR=${TOPDIR}/build
SOURCESDIR=${TOPDIR}/sources
POKYDIR=$(dirname $(find "${SOURCESDIR}" -name "oe-init-build-env" -print -quit))

# Change to top directory
cd "${TOPDIR}"

# Check for Poky directory
if [ -z "${POKYDIR}" ]; then
  print_ko_ "poky directory cannot be found"
  exit 1
fi

# Parse options
parse_options "${@}"

# Display VARIABLES
echo "CMD = '$CMD'"
echo "DL_DIR = '$DL_DIR'"
echo "SSTATE_DIR = '$SSTATE_DIR'"

# Init display
init_output $VERBOSE build

# Apply patches
for patch in patches/*
do
  apply_patch ${patch}
done

# Set image to build, default to core-image-minimal
export IMAGE=${IMAGE:-"seapath-host-efi-image"}
export MACHINE=${MACHINE:-"votp-host"}
export DISTRO=${DISTRO:-"seapath-host"}
export ACCEPT_FSL_EULA="1"
export LSB_WARN='0'
if [ -f seapath.conf ] ; then
    for seapath_env in $(bash -c \
        '( source seapath.conf ; set -o posix ; set \
            | grep -e "^SEAPATH" )') ; do
        seapath_env_key=$(echo ${seapath_env} | cut -d '=' -f 1)
        seapath_env_value=$(echo ${seapath_env} | cut -d '=' -f 2-)
        if [ -z $(printenv "${seapath_env_key}") ] ; then
            export "${seapath_env_key}"="${seapath_env_value}"
        fi
        BB_ENV_EXTRAWHITE="$BB_ENV_EXTRAWHITE ${seapath_env_key}"
    done
fi

for seapath_env in $(printenv | grep -e "^SEAPATH") ; do
    echo -n "$(echo $seapath_env | cut -d '=' -f 1) = "
    echo $seapath_env | cut -d '=' -f 2-
done

# Set variable readable from command line
export BB_ENV_EXTRAWHITE="$BB_ENV_EXTRAWHITE \
  DISTRO \
  DL_DIR \
  MACHINE \
  SSTATE_DIR \
  ACCEPT_FSL_EULA \
  LSB_WARN \
"
if [ ! -z "$REMOVE_BUILDDIR" ]; then
  # Clean directory
  run_cmd "Remove build directory" rm -Rf "${BUILDDIR}"
fi

# Clean layers
if [ -z "${NO_LAYERS_UPDATE}" ] ; then
    rm -f ${BUILDDIR}/conf/bblayers.conf
fi

# Init poky build
set "${BUILDDIR}"
. "${POKYDIR}"/oe-init-build-env

# Add layers
update_layers

# Build Yocto
if [ ! -z "$CMD" ]; then
  run_cmd "Launch custom command (should take a while)..." "$CMD"
elif [ -z "$COMPILE_SDK" ]; then
  run_cmd "Build image (should take a while)..." bitbake "$IMAGE"
else
  run_cmd "Build sdk (should take a while)..." bitbake "$IMAGE" -c populate_sdk
fi

# Generate the documentation
if [ "$(type -p asciidoctor-pdf)" ]; then
  asciidoctor-pdf -o tmp/deploy/images/README.pdf ../README.adoc
fi
