#!/bin/bash

# NOTE: This script restores an age encryption key (identity) from an encrypted
# file. If the restored key file exists and known-good checksums match, then
# this process is skipped. The encrypted file is age encrypted with a
# passphrase. This script will accept the passphrase via STDIN, via the
# environment variable AGE_PASSPHRASE, or will prompt for it. Upon successful
# restoration of the key file, this script will create new checksum files for
# both the encrypted file and the restored key file.

set -eufo pipefail

die() {
    echo "Error: $1" >&2
    exit 1
}

compute_checksum() {
    local file="$1"
    case "$(uname -s)" in
        Darwin)
            command -v shasum >/dev/null 2>&1 \
                || die "Command \"shasum\" not found."
            shasum -a 256 "$file" | cut -d' ' -f1 \
                || die "Failed to compute checksum for \"$(basename $file)\"."
            ;;
        Linux)
            command -v sha256sum >/dev/null 2>&1 \
                || die "Command \"sha256sum\" not found."
            sha256sum "$file" | cut -d' ' -f1 \
                || die "Failed to compute checksum for \"$(basename $file)\"."
            ;;
        *)
            die "Unexpected OS while computing checksum (\"$(uname -s)\")."
            ;;
    esac
}

decrypt_with_passphrase() {
    local passphrase="$1"
    echo "$passphrase" | chezmoi age decrypt --config "$temp_config_file" \
        --config-format yaml --no-tty --passphrase --output "$KEY_FILE" \
        "$ENCRYPTED_KEY_FILE" >/dev/null 2>&1 \
        || die "Decryption failed (invalid passphrase or corrupted file)."
}

PATH="$HOME/.local/bin"
PATH="$PATH:/opt/homebrew/bin:/home/linuxbrew/.linuxbrew/bin"
PATH="$PATH:/usr/local/bin:/usr/bin:/bin"

XDG_CONFIG_HOME="$HOME/.config"
XDG_DATA_HOME="$HOME/.local/share"
CONFIG_DIR="$XDG_CONFIG_HOME/chezmoi"
SOURCE_DIR="$XDG_DATA_HOME/chezmoi"
ENCRYPTED_KEY_FILE="$SOURCE_DIR/.support/encrypted/chezmoi.key.age"
KEY_FILE="$CONFIG_DIR/chezmoi.key"
ENCRYPTED_KEY_CHECKSUM="$CONFIG_DIR/$(basename "$ENCRYPTED_KEY_FILE").sha256"
KEY_CHECKSUM="$CONFIG_DIR/$(basename "$KEY_FILE").sha256"

# Exit if key file and checksums match
if [[ -r "$KEY_FILE" && -r "$KEY_CHECKSUM" && \
      -r "$ENCRYPTED_KEY_FILE" && -r "$ENCRYPTED_KEY_CHECKSUM" ]]; then
    if [[ "$(compute_checksum "$ENCRYPTED_KEY_FILE")" == \
          "$(cat "$ENCRYPTED_KEY_CHECKSUM")" && \
          "$(compute_checksum "$KEY_FILE")" == \
          "$(cat "$KEY_CHECKSUM")" ]]; then
        exit 0
    fi
    rm -f "$KEY_FILE" "$ENCRYPTED_KEY_CHECKSUM" "$KEY_CHECKSUM" \
        || die "Failed to remove outdated key or checksums files."
fi

[[ -r "$ENCRYPTED_KEY_FILE" ]] \
    || die "Encrypted key file (\"$(basename $ENCRYPTED_KEY_FILE)\") not found."

for cmd in chezmoi mktemp; do
    command -v "$cmd" >/dev/null 2>&1 || die "Command \"$cmd\" not found."
done

temp_config_file=$(mktemp) || die "Failed to create temporary config file."
trap 'rm -f "$temp_config_file"' EXIT INT TERM HUP

{
    printf 'useBuiltinAge: true\n'
    printf 'warnings:\n'
    printf '  configFileTemplateHasChanged: false\n'
} > "$temp_config_file" || die "Failed to write to temporary config file."

mkdir -p "$CONFIG_DIR" || die "Failed to create directory \"$CONFIG_DIR\"."
chmod 700 "$CONFIG_DIR" || die "Failed to set permissions on \"$CONFIG_DIR\"."

# Handle passphrase: stdin, AGE_PASSPHRASE, or custom prompt
passphrase=""
if [[ ! -t 0 ]]; then
    read -r passphrase < /dev/stdin || true
else
    read -r -t 1 passphrase < /dev/stdin || true
fi

if [[ -n "$passphrase" ]]; then
    decrypt_with_passphrase "$passphrase"
elif [[ -n "${AGE_PASSPHRASE:-}" ]]; then
    decrypt_with_passphrase "$AGE_PASSPHRASE"
elif [[ -t 0 ]]; then
    echo -n "Enter passphrase: " >&2
    read -r -s passphrase
    echo >&2
    [[ -n "$passphrase" ]] || die "No passphrase provided."
    decrypt_with_passphrase "$passphrase"
else
    die "No passphrase provided."
fi

chmod 600 "$KEY_FILE" \
    || die "Failed to set permissions on \"$(basename $KEY_FILE)\"."

 # Save checksums
compute_checksum "$ENCRYPTED_KEY_FILE" > "$ENCRYPTED_KEY_CHECKSUM" \
    || die "Failed to save encrypted file checksum."
compute_checksum "$KEY_FILE" > "$KEY_CHECKSUM" \
    || die "Failed to save key file checksum."
chmod 600 "$ENCRYPTED_KEY_CHECKSUM" "$KEY_CHECKSUM" \
    || die "Failed to set permissions on checksum files."

printf "Encryption key restored to %s.\n" "$KEY_FILE"
