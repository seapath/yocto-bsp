#!/bin/bash
# Copyright (C) 2020, RTE (http://www.rte-france.com)
# This program is distributed under the Apache 2 license.

# Name:       print_usage
# Brief:      Print script usage
print_usage()
{
    echo "This script tag and provide git log of a Yocto project

./$(basename ${0}) [OPTIONS]

Options:
        (--customer)    <customer>
        (--dir)         <existing directory to use>
        (--project)     <project name>
        (-h|--help)     Display this help message
        "
}

# Name:       parse_options
# Brief:      Parse options from command line
# Param[in]:  Command line parameters
parse_options()
{
    ARGS=$(getopt -o "h" -l "customer:,dir:,project:" -n "$0" -- "$@")

    #Bad arguments
    if [ $? -ne 0 ]; then
        exit 1
    fi

    eval set -- "${ARGS}"

    while true; do
        case "$1" in
            --customer)
                export CUSTOMER=$2
                shift 2
                ;;

            --dir)
                export working_dir=$2
                no_clone=1
                shift 2
                ;;

            --project)
                export PROJECT=$2
                shift 2
                ;;

            -h|--help)
                print_usage
                exit 1
                shift
                break
                ;;

            -|--)
                shift
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

parse_options "${@}"

if [ -z "$CUSTOMER" ] || [ -z "$PROJECT" ]; then
    print_usage
    exit 1
fi

[ -z "$working_dir" ] && working_dir=$(mktemp -d)
[ -d "$working_dir" ] || exit 1

yocto_git_repos="meta-$CUSTOMER repo-manifest yocto-bsp"
echo $yocto_git_repos
gerrit_sfl="ssh://g1.sfl.team"

function go_to_working_dir() {
    echo "entering $working_dir"
    cd $working_dir && return 0 || return 1
}

function enter_project() {
    local project_dir=$1
    cd $project_dir && return 0 || return 1
}

function clone_project() {
    local url=$1
    git clone $url &> /dev/null && return 0 || return 1
}

function check_copyright() {
    local dir=$1
    echo "# checking copyright on $yocto_project"
    file_extension=".*\.\(adoc\|bb\|bbappend\|inc\|c\|cpp\|md\|py\|sh\|toml\|xml\)"
    search_name="copyright"
    find $dir -type f -regex "$file_extension" \
        -exec grep --color=auto -iHnL "$search_name" {} \;;
    echo "############################"
}

function check_license() {
    local dir=$1
    echo "# checking licence on $yocto_project"
    file_extension=".*\.\(bb\|inc\|c\|cpp\|py\|sh\|toml\|xml\)"
    search_name="LICENSE"
    find $dir -type f -regex "$file_extension" \
        -exec grep --color=auto -iHnL "$search_name" {} \;;
    echo "############################"
}

current_pwd=$(pwd)
go_to_working_dir || exit 1
for yocto_project in $yocto_git_repos; do
    if [ -z "$no_clone" ]; then
        clone_project "$gerrit_sfl/$CUSTOMER/$PROJECT/$yocto_project" || exit 1
    fi
    enter_project $yocto_project && check_copyright . && check_license .
    go_to_working_dir || exit 1
done
cd $current_pwd
