#!/bin/zsh

# Creates the long-lived, zero-fee signing identity used by the local
# Reimagine release build and GitHub Actions. The certificate is self-signed:
# it keeps macOS TCC identity stable, but it is not an Apple Developer ID and
# cannot be notarized by Apple.

set -euo pipefail

identity_name="${OPEN_ISLAND_RELEASE_SIGNING_IDENTITY:-Open Island Reimagine Stable}"
keychain="${OPEN_ISLAND_RELEASE_SIGNING_KEYCHAIN:-$HOME/Library/Keychains/login.keychain-db}"
export_path=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --export-p12)
            [[ $# -ge 2 ]] || { echo "--export-p12 requires a path" >&2; exit 2; }
            export_path="$2"
            shift 2
            ;;
        *)
            echo "Unknown argument: $1" >&2
            exit 2
            ;;
    esac
done

if security find-identity -p codesigning -v "$keychain" 2>/dev/null | grep -Fq "\"$identity_name\""; then
    if [[ -n "$export_path" ]]; then
        echo "Identity already exists; refusing to export unrelated keychain identities." >&2
        echo "Use the original protected P12 backup for CI recovery." >&2
        exit 1
    fi
    echo "Code signing identity already exists: $identity_name"
    exit 0
fi

command -v openssl >/dev/null 2>&1 || { echo "openssl is required" >&2; exit 1; }

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
key_pem="$tmp_dir/key.pem"
cert_pem="$tmp_dir/cert.pem"
cert_p12="$tmp_dir/cert.p12"
p12_password="${OPEN_ISLAND_RELEASE_P12_PASSWORD:-$(openssl rand -hex 24)}"

if [[ -n "$export_path" && -z "${OPEN_ISLAND_RELEASE_P12_PASSWORD:-}" ]]; then
    echo "OPEN_ISLAND_RELEASE_P12_PASSWORD is required with --export-p12." >&2
    exit 1
fi

openssl req -x509 -newkey rsa:3072 \
    -keyout "$key_pem" \
    -out "$cert_pem" \
    -days 3650 \
    -nodes \
    -subj "/CN=$identity_name/O=OpenIsland Reimagine" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=critical,codeSigning" \
    2>/dev/null

openssl pkcs12 -export -legacy \
    -out "$cert_p12" \
    -inkey "$key_pem" \
    -in "$cert_pem" \
    -name "$identity_name" \
    -password "pass:$p12_password" \
    2>/dev/null

security import "$cert_p12" \
    -k "$keychain" \
    -P "$p12_password" \
    -T /usr/bin/codesign \
    >/dev/null
if [[ -n "$export_path" ]]; then
    [[ ! -e "$export_path" ]] || { echo "Refusing to overwrite $export_path" >&2; exit 1; }
    umask 077
    cp "$cert_p12" "$export_path"
fi

security find-certificate -c "$identity_name" -a -Z "$keychain" >/dev/null
echo "Stable release signing identity is ready: $identity_name"
