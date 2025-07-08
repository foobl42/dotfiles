#!/bin/bash

# NOTE: This script extracts the recipient key from an age encryption key
# (identity) file, if the key file exists and known-good checksum matches. The
# key file should be unencrypted/plain text. The extracted recipient key will be
# sent to STDOUT.

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

PATH="$HOME/.local/bin"
PATH="$PATH:/opt/homebrew/bin:/home/linuxbrew/.linuxbrew/bin"
PATH="$PATH:/usr/local/bin:/usr/bin:/bin"

XDG_CONFIG_HOME="$HOME/.config"
CONFIG_DIR="$XDG_CONFIG_HOME/chezmoi"
KEY_FILE="$CONFIG_DIR/chezmoi.key"
KEY_CHECKSUM="$CONFIG_DIR/$(basename "$KEY_FILE").sha256"

# Error if key file and checksum do not match
if [[ -r "$KEY_FILE" && -r "$KEY_CHECKSUM" ]]; then
    if [[ "$(compute_checksum "$KEY_FILE")" != \
          "$(cat "$KEY_CHECKSUM")" ]]; then
        die "Key file checksum does not match."
    fi
fi

[[ -r "$KEY_FILE" ]] \
    || die "Key file (\"$(basename $KEY_FILE)\") not found."

for cmd in awk; do
    command -v "$cmd" >/dev/null 2>&1 || die "Command \"$cmd\" not found."
done

awk "/public key/ {printf \$4}" $KEY_FILE \
    || die "Failed to extract recipient key from encryption key file."
