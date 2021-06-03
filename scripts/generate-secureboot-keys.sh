#!/usr/bin/env bash
#
# Copyright (C) 2021, RTE (http://www.rte-france.com)
# SPDX-License-Identifier: Apache-2.0
#
# Generate keys and signed EFI Signature list of PK, KEK, DB and DBX
# so they can be used to setup UEFI SecureBoot on a compatible
# system.
#
# Microsoft keys are included by default in DB and KEK to ensure
# that 3rd party firmwares (known as "UEFI option ROM") can also
# be loaded. This generally includes NICs, GPUs, ECs, BMCs, RAID
# controllers, etc...
# If the manufacturer is in complete control over the selected
# x86 platform and firmware, Microsoft keys can be completely
# opted-out.
#
# DB/DBX can be enriched by providing a path to certs and hashes
# to be included in either of those databases.
#
# Keys will be generated either in the script's folder or the
# one provided in command line

set -o pipefail

NAME="SEAPATH UEFI Secureboot"
WORKDIR="$(dirname "$(realpath "${0}")")"
OUTPUT="${WORKDIR}"
GUID="$(uuidgen)"

MS_UEFI_CA_CERT_LINK="https://go.microsoft.com/fwlink/p/?linkid=321194"
MS_KEK_CERT_LINK="https://go.microsoft.com/fwlink/?LinkId=321185"

print_usage() {
    cat 1>&2 << EOF
Build UEFI Secure Boot keys and authenticated variables.

This script will produce the following artifacts :

  * PK.crt / PK.key (Platform Key keypair)
  * KEK.crt / KEK.key (Key Encryption Key keypair)
  * PK.esl / KEK.esl / DB.esl (EFI Signature List variables for PK / KEK and DB)
  * *auth (EFI Variable Authentication headers)

Optional:
  * DBX.esl (EFI Signature List variable for DBX)

DB will contain the DB key and Microsoft UEFI Secureboot certs that are required
to load 3rd party firmwares.

Keys and ESL files will be created in script's directory or in the path provided
with "--output|-o" option.

${0##*./} [OPTIONS]

Options:
    (-n|--name)       <name>             Name of the key set
    (-o|--output)     <path>             Output directory
    (-g|--guid)       <uuid>             GUID used to identify the owner of the key set
    (--populate-db)   <path>             Add certificates (DER/PEM) and hashes from <path> in DB
    (--populate-dbx)  <path>             Generate a DBX, based on certificates (DER/PEM) and hashes stored in <path>
    (--no-ms)                            Disable the integration of Microsoft public keys

For "--populate-db" and "--populate-dbx", the tool is accepting :
    * PEM or DER certificates with ".crt" extension
    * Files containing sha256 hash stored in binary (32 bytes) with ".hash" extension

EOF
    exit 1
}

die() {
    echo "!!! Fatal: $*"
    exit 1
}

log() {
    echo "==> $*"
}

warn() {
    echo "<!> $*"
}

# Verify that every required tool is available for usage
verify_dependencies() {
    required_commands=(openssl curl cert-to-efi-sig-list sign-efi-sig-list sbsiglist)
    for cmd in "${required_commands[@]}"; do
        if ! command -v "${cmd}" &>/dev/null; then
            die "Missing command: ${cmd}"
        fi
    done
}

# Transform a DER encoded certificate into a PEM certificate and print
# the resulting file on stdout.
der2pem() {
    local der_cert pem_cert
    der_cert="${1}"

    [ -f "${der_cert}" ] || die "DER Certificate not found"

    if grep -q "\-----BEGIN CERTIFICATE-----" "${der_cert}"; then
        echo "${der_cert}"
        return
    fi

    pem_cert="$(basename "${der_cert}" | cut -d. -f1).pem"

    if ! openssl x509 -in "${der_cert}" -inform der -outform pem -out "${pem_cert}" &>/dev/null; then
        return 1
    fi

    echo "${pem_cert}"
}

# Parse options from command line
parse_options() {
    if ! ARGS=$(getopt -o "n:o:g:" -l "help,name:,output:,guid:,populate-dbx:,populate-db:,no-ms" -- "$@"); then
        print_usage
    fi

    eval set -- "${ARGS}"

    while true; do
        case "${1}" in
        -n|--name)
            NAME="${2}"
            echo -e "* Certificates 'Common Name' : ${NAME}"
            shift 2
            ;;
        -o|--output)
            OUTPUT="$(realpath "${2}")"
            echo -e "* Output directory : ${OUTPUT}"
            if [ -d "${OUTPUT}" ]; then
                die "Output directory already exists, please remove it"
            else
                mkdir -p "${OUTPUT}" || die "Can not create ${OUTPUT}"
            fi
            shift 2
            ;;
        -g|--guid)
            GUID="${2}"
            if ! uuid -d "${GUID}" &>/dev/null; then
                die "Invalid GUID"
            fi
            shift 2
            ;;
        --no-ms)
            NO_MS="1"
            shift
            ;;
        --populate-db)
            if ! DB_ENTRIES_PATH="$(readlink -e "${2}")"; then
                die "DB folder '${2}' not found"
            fi
            echo -e "* DB entries path : ${DB_ENTRIES_PATH}"
            shift 2
            ;;
        --populate-dbx)
            if ! DBX_ENTRIES_PATH="$(readlink -e "${2}")"; then
                die "DBX folder '${2}' not found"
            fi
            echo -e "* DBX entries path : ${DBX_ENTRIES_PATH}"
            POPULATE_DBX="1"
            shift 2
            ;;
        --help)
            print_usage
            ;;
        --)
            shift
            break
            ;;
        *)
            print_usage
            ;;
        esac
    done
}

# Generate RSA key pairs with the name specified in the command line
# options (the platform key PK, the Key Exchange Key KEK and the
# Signature database DB).
generate_key_pairs() {
    local reqcmd="openssl req -new -x509 -newkey rsa:2048 -days 7300 -nodes -sha256"

    if ! ${reqcmd} -subj "/CN=$NAME PK/" -keyout PK.key -out PK.crt &>/dev/null; then
        die "Error while generating PK"
    fi

    if ! ${reqcmd} -subj "/CN=$NAME KEK/" -keyout KEK.key -out KEK.crt &>/dev/null; then
        die "Error while generating KEK"
    fi

    if ! ${reqcmd} -subj "/CN=$NAME DB/" -keyout DB.key -out DB.crt &>/dev/null; then
        die "Error while generating DB Signing key"
    fi

    log "PK, KEK and DB key pair generated..."
}

# Create EFI Signature list from a X509 certificate (in PEM format).
create_efi_signature_lists() {
    cert-to-efi-sig-list -g "${GUID}" PK.crt PK.esl
    cert-to-efi-sig-list -g "${GUID}" KEK.crt KEK.esl
    cert-to-efi-sig-list -g "${GUID}" DB.crt DB.esl
    log "EFI Signature lists created..."
}

# Produce an *.auth file with an authenticated header for direct update
# to a secure variable.
sign_efi_signature_lists() {
    sign-efi-sig-list -k PK.key -c PK.crt PK PK.esl PK.auth >/dev/null
    sign-efi-sig-list -k PK.key -c PK.crt KEK KEK.esl KEK.auth >/dev/null
    sign-efi-sig-list -k KEK.key -c KEK.crt db DB.esl DB.auth >/dev/null
    if [ "${POPULATE_DBX}" = "1" ]; then
        sign-efi-sig-list -k KEK.key -c KEK.crt db DBX.esl DBX.auth >/dev/null
    fi
    log "EFI Signature lists signed..."
}

# Add Microsoft Certificates to the EFI signature lists.
add_ms_certs() {
    if [ "${NO_MS}" ]; then
        warn "Microsoft UEFI Certificates will not be added to the EFI Signature lists"
        return
    fi

    if ! curl -s -L "${MS_UEFI_CA_CERT_LINK}" -o MicCorUEFCA.crt; then
        die "Unable to download Microsoft UEFI CA Cert from link : ${MS_UEFI_CA_CERT_LINK}"
    fi

    if [ ! -s MicCorUEFCA.crt ] || ! ms_ca="$(der2pem MicCorUEFCA.crt)"; then
        die "MS UEFI CA Certificate is invalid"
    fi

    if ! curl -s -L "${MS_KEK_CERT_LINK}" -o MicCorKEK.crt; then
        die "Unable to download Microsoft UEFI KEK Cert from link : ${MS_KEK_CERT_LINK}"
    fi

    if [ ! -s MicCorKEK.crt ] || ! ms_kek="$(der2pem MicCorKEK.crt)"; then
        die "MS KEK Certificate is invalid"
    fi

    cert-to-efi-sig-list -g "${GUID}" "${ms_kek}" MS_KEK.esl
    cert-to-efi-sig-list -g "${GUID}" "${ms_ca}" MS_DB.esl

    mv -f DB.esl DB.orig.esl
    mv -f KEK.esl KEK.orig.esl
    cat KEK.orig.esl MS_KEK.esl > KEK.esl
    cat DB.orig.esl MS_DB.esl > DB.esl
    rm -f -- *.orig.esl
    rm -f MS_*.esl
    rm -f MicCor*.*

    log "MS certificates added to EFI Signature lists..."
}

# Convert a certificate or hash to EFI Signature List and
# append it to the database provided in parameter.
convert_to_esl_and_append() {
    local type="${1}"
    local filename="${2}"
    local database="${3}"

    case ${type} in
        cert)
            if ! pemname="$(der2pem "${filename}")"; then
                warn "Error while converting $(basename "${filename}") to PEM. Skipped"
                return
            fi
            if ! cert-to-efi-sig-list -g "${GUID}" "${pemname}" "${filename}.esl"; then
                warn "Error while converting $(basename "${filename}") to EFI Signature list. Skipped"
                return
            fi
            ;;
        hash)
            if ! sbsiglist --owner "${GUID}" --type sha256 --output "${filename}.esl" "${filename}"; then
                warn "Error while converting $(basename "${filename}") hash to EFI Signature list. Skipped"
                return
            fi
            ;;
        *)
            warn "Unknown type : ${type}. Skipped"
            return
            ;;
    esac
    mv -f "${database}" "${database}.orig"
    cat "${database}.orig" "${filename}.esl" > "${database}"
    echo "* Added ${type} to ${database}: $(basename "${filename}")"
    rm -f "${filename}.esl"
    rm -f "${database}.orig"
}

# Add certificates and hashes available in the specified path
# into a ESL database (either DB or DBX).
add_entries_to_efi_database() {
    local database="${1}"
    local path_to_entries="${2}"
    local db_file="${database}.esl"

    if ! grep -qE "^DBX?$" <<< "${database}"; then
        warn "Can only update either DB or DBX. Skipped"
        return
    fi

    touch "${db_file}"

    certs_to_add="$(find "${path_to_entries}" -type f -iname "*.crt" -print0 | xargs -0)"
    hashes_to_add="$(find "${path_to_entries}" -type f -iname "*.hash" -print0 | xargs -0)"

    for file in ${hashes_to_add}; do
        convert_to_esl_and_append "hash" "${file}" "${db_file}"
    done

    for file in ${certs_to_add}; do
        convert_to_esl_and_append "cert" "${file}" "${db_file}"
    done
}

# Add any additional entry to DB
add_supplemental_db_entries() {
    if [ -z "${DB_ENTRIES_PATH}" ]; then
        warn "No additional DB entries to add."
        return
    fi

    add_entries_to_efi_database DB "${DB_ENTRIES_PATH}"

    log "Additional entries added to DB"
}

# Add any additional entry to DBX
generate_dbx() {
    if [ "${POPULATE_DBX}" != "1" ]; then
        log "No DBX to populate."
        return
    fi

    add_entries_to_efi_database DBX "${DBX_ENTRIES_PATH}"

    log "DBX populated"
}


verify_dependencies

parse_options "${@}"

cd "${OUTPUT}" || die "Can not cd to ${OUTPUT}"

OUTPUT="$(pwd)"

generate_key_pairs

create_efi_signature_lists

add_ms_certs

add_supplemental_db_entries

generate_dbx

sign_efi_signature_lists

log "The generated keys are stored in the ${OUTPUT} directory"
log "GUID used : ${GUID} -- Keep it to ease identification of future updates of DB/DBX"
