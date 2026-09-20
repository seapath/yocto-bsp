#!/usr/bin/env bash
#
# Copyright (C) 2026 Savoir-faire Linux, Inc.
# SPDX-License-Identifier: Apache-2.0
#
# Generate a throwaway PKI used to sign SWUpdate packages with CMS.
#
# The PKI is a three-level hierarchy:
#
#   root CA  ->  intermediate CA  ->  signing certificate (EKU=codeSigning)
#
# The signing certificate is used to sign the sw-description of an update
# package, the intermediate certificate is appended to the CMS structure so the
# target can build the chain, and the root (and intermediate) certificates are
# baked into the device trust store as trust anchors.
#
# This key material is meant for tests and CI only. Production signing keys are
# managed outside of this project.
#
# Copyright header is required by the project; see ../README.adoc.

set -euo pipefail

NAME="SEAPATH SWUpdate"
OUTPUT=""
BITS="4096"
ROOT_DAYS="7300"
INTERMEDIATE_DAYS="3650"
SIGNER_DAYS="825"

print_usage() {
    cat 1>&2 <<EOF
Generate a throwaway PKI for SWUpdate CMS signing.

This script produces the following artifacts in <output-dir>:

  * ca/root-ca.crt            Root CA certificate (trust anchor)
  * ca/root-ca.key            Root CA private key
  * ca/intermediate-ca.crt    Intermediate CA certificate (trust anchor)
  * ca/intermediate-ca.key    Intermediate CA private key
  * signer.crt                Signing certificate (EKU=codeSigning)
  * signer.key                Unencrypted signing private key

Both ca/*.crt certificates are assembled by the swupdate-trust recipe into
/etc/swupdate/ca-chain.pem. signer.crt and signer.key are passed to the
SWU recipes through SWUPDATE_CMS_CERT and SWUPDATE_CMS_KEY.

${0##*/} [OPTIONS]

Options:
    (-o|--output)             <path>     Output directory (required)
    (-n|--name)               <name>     Certificate Common Name prefix
    (-b|--bits)               <bits>     RSA key size in bits (default: ${BITS})
    (--root-days)             <days>     Root CA validity (default: ${ROOT_DAYS})
    (--intermediate-days)     <days>     Intermediate CA validity (default: ${INTERMEDIATE_DAYS})
    (--signer-days)           <days>     Signing certificate validity (default: ${SIGNER_DAYS})
    (-h|--help)                          Display this help message

The output directory is created if it does not exist and must not already
contain key material, to avoid destroying an existing key pair.

EOF
    exit "${1:-1}"
}

die() {
    echo "!!! Fatal: $*" 1>&2
    exit 1
}

log() {
    echo "==> $*"
}

# Run an OpenSSL command, keeping its output for diagnostics on failure.
run_openssl() {
    if ! "$@" >>"${WORKDIR}/openssl.log" 2>&1; then
        cat "${WORKDIR}/openssl.log" 1>&2
        die "OpenSSL command failed: $*"
    fi
}

verify_dependencies() {
    command -v openssl &>/dev/null || die "Missing command: openssl"

    # -addext and extendedKeyUsage=codeSigning require a recent OpenSSL.
    openssl version | grep -qE "OpenSSL (1\.1\.1|3\.)" ||
        die "OpenSSL 1.1.1 or newer is required"
}

parse_options() {
    if ! ARGS=$(getopt -o "o:n:b:h" \
        -l "output:,name:,bits:,root-days:,intermediate-days:,signer-days:,help" \
        -- "$@"); then
        print_usage
    fi

    eval set -- "${ARGS}"

    while true; do
        case "${1}" in
            -o|--output)
                OUTPUT="${2}"
                shift 2
                ;;
            -n|--name)
                NAME="${2}"
                shift 2
                ;;
            -b|--bits)
                BITS="${2}"
                shift 2
                ;;
            --root-days)
                ROOT_DAYS="${2}"
                shift 2
                ;;
            --intermediate-days)
                INTERMEDIATE_DAYS="${2}"
                shift 2
                ;;
            --signer-days)
                SIGNER_DAYS="${2}"
                shift 2
                ;;
            -h|--help)
                print_usage 0
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

generate_root_ca() {
    log "Generating root CA"
    run_openssl openssl req -x509 -newkey "rsa:${BITS}" -nodes -sha256 \
        -keyout "${OUTPUT}/ca/root-ca.key" \
        -out "${OUTPUT}/ca/root-ca.crt" \
        -days "${ROOT_DAYS}" \
        -subj "/CN=${NAME} Root CA/" \
        -addext "basicConstraints=critical,CA:TRUE" \
        -addext "keyUsage=critical,keyCertSign,cRLSign" \
        -addext "subjectKeyIdentifier=hash"
}

generate_intermediate_ca() {
    log "Generating intermediate CA"
    run_openssl openssl req -new -newkey "rsa:${BITS}" -nodes -sha256 \
        -keyout "${OUTPUT}/ca/intermediate-ca.key" \
        -out "${OUTPUT}/ca/intermediate-ca.csr" \
        -subj "/CN=${NAME} Intermediate CA/"

    cat > "${WORKDIR}/intermediate.ext" <<EOF
[v3_intermediate_ca]
basicConstraints = critical,CA:TRUE,pathlen:0
keyUsage = critical,keyCertSign,cRLSign
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer
EOF

    run_openssl openssl x509 -req \
        -in "${OUTPUT}/ca/intermediate-ca.csr" \
        -CA "${OUTPUT}/ca/root-ca.crt" \
        -CAkey "${OUTPUT}/ca/root-ca.key" \
        -CAcreateserial \
        -days "${INTERMEDIATE_DAYS}" \
        -sha256 \
        -extfile "${WORKDIR}/intermediate.ext" \
        -extensions v3_intermediate_ca \
        -out "${OUTPUT}/ca/intermediate-ca.crt"
}

generate_signer() {
    log "Generating signing certificate"
    run_openssl openssl req -new -newkey "rsa:${BITS}" -nodes -sha256 \
        -keyout "${OUTPUT}/signer.key" \
        -out "${WORKDIR}/signer.csr" \
        -subj "/CN=${NAME} Signing/"

    cat > "${WORKDIR}/signer.ext" <<EOF
[v3_signer]
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer
EOF

    run_openssl openssl x509 -req \
        -in "${WORKDIR}/signer.csr" \
        -CA "${OUTPUT}/ca/intermediate-ca.crt" \
        -CAkey "${OUTPUT}/ca/intermediate-ca.key" \
        -CAcreateserial \
        -days "${SIGNER_DAYS}" \
        -sha256 \
        -extfile "${WORKDIR}/signer.ext" \
        -extensions v3_signer \
        -out "${OUTPUT}/signer.crt"
}

verify_pki() {
    log "Verifying the signing chain"
    openssl verify -CAfile "${OUTPUT}/ca/root-ca.crt" \
        -untrusted "${OUTPUT}/ca/intermediate-ca.crt" \
        "${OUTPUT}/signer.crt" >/dev/null 2>&1 ||
        die "The generated signing chain does not verify"

    openssl x509 -in "${OUTPUT}/signer.crt" -noout -text |
        grep -q "Code Signing" ||
        die "The signing certificate does not carry EKU=codeSigning"

    # A round-trip CMS signature proves the key material is usable end to end.
    echo "swupdate signing key material" > "${WORKDIR}/probe.txt"
    openssl cms -sign -binary -in "${WORKDIR}/probe.txt" \
        -signer "${OUTPUT}/signer.crt" \
        -inkey "${OUTPUT}/signer.key" \
        -certfile "${OUTPUT}/ca/intermediate-ca.crt" \
        -outform DER -nosmimecap \
        -out "${WORKDIR}/probe.sig" >/dev/null 2>&1 ||
        die "Unable to produce a CMS signature with the generated key material"

    openssl cms -verify -binary -inform DER \
        -in "${WORKDIR}/probe.sig" \
        -content "${WORKDIR}/probe.txt" \
        -CAfile "${OUTPUT}/ca/root-ca.crt" \
        -purpose any \
        -out /dev/null >/dev/null 2>&1 ||
        die "Unable to verify a CMS signature with the generated trust anchor"
}

main() {
    parse_options "$@"

    [ -n "${OUTPUT}" ] || print_usage

    for value in "${BITS}" "${ROOT_DAYS}" "${INTERMEDIATE_DAYS}" "${SIGNER_DAYS}"; do
        [[ "${value}" =~ ^[0-9]+$ ]] ||
            die "Invalid numeric option value: '${value}'"
    done

    verify_dependencies

    OUTPUT="$(realpath -m "${OUTPUT}")"

    if [ -e "${OUTPUT}/signer.key" ] || [ -e "${OUTPUT}/ca/root-ca.key" ]; then
        die "Output directory already contains key material: ${OUTPUT}"
    fi

    mkdir -p "${OUTPUT}/ca" || die "Cannot create ${OUTPUT}/ca"

    WORKDIR="$(mktemp -d)"
    trap 'rm -rf "${WORKDIR}"' EXIT

    generate_root_ca
    generate_intermediate_ca
    generate_signer

    rm -f \
        "${OUTPUT}/ca/intermediate-ca.csr" \
        "${OUTPUT}/ca/root-ca.srl" \
        "${OUTPUT}/ca/intermediate-ca.srl"
    chmod 0600 "${OUTPUT}/ca/root-ca.key" \
        "${OUTPUT}/ca/intermediate-ca.key" "${OUTPUT}/signer.key"

    verify_pki

    log "The generated keys are stored in ${OUTPUT}"
    log "Trust anchors : ${OUTPUT}/ca/*.crt"
    log "Signing pair  : ${OUTPUT}/signer.crt + ${OUTPUT}/signer.key"
}

main "$@"
