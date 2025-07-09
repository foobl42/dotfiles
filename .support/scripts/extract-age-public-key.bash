#!/bin/bash

# NOTE: This script extracts the age public key from an age identity file, if
# the identity file exists and its known-good checksum matches. The identity
# file should be unencrypted/plain text. The extracted public key will be sent
# to STDOUT.

set -eufo pipefail

PATH="$HOME/.local/bin"
PATH="$PATH:/opt/homebrew/bin:/home/linuxbrew/.linuxbrew/bin"
PATH="$PATH:/usr/local/bin:/usr/bin:/bin"

conf_dir="$HOME/.config/chezmoi"

ident_file="$conf_dir/chezmoi.key"
ident_file_sum="$conf_dir/$(basename "$ident_file").sha256"

abort() {
    echo "Error: $1" >&2
    exit 1
}

checksum() {
    local file="$1"
    case "$(uname -s)" in
        Darwin)
            command -v shasum >/dev/null 2>&1 \
                || abort "The \"shasum\" command was not found."
            shasum -a 256 "$file" | cut -d' ' -f1 \
                || abort "Failed to checksum \"$(basename $file)\"."
            ;;
        Linux)
            command -v sha256sum >/dev/null 2>&1 \
                || abort "The \"sha256sum\" command was not found."
            sha256sum "$file" | cut -d' ' -f1 \
                || abort "Failed to checksum \"$(basename $file)\"."
            ;;
        *)
            abort "Unexpected OS (\"$(uname -s)\") was detected."
            ;;
    esac
}

# Error if the checksum for the identity file does not match
if [[ -r "$ident_file" && -r "$ident_file_sum" ]]; then
    if [[ "$(checksum "$ident_file")" != "$(cat "$ident_file_sum")" ]]; then
        abort "The identity file checksum does not match."
    fi
fi

[[ -r "$ident_file" ]] || abort "The identity file was not found."

command -v awk >/dev/null 2>&1 || abort "The \"awk\" command was not found."

awk "/public key/ {printf \$4}" $ident_file \
    || abort "Failed to extract the public key."
