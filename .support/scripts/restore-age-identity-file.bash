#!/bin/bash

# NOTE: This script restores an age identity file from a passphrase-encrypted
# file. If the restored identity file exists and known-good checksums match,
# then this process is skipped. This script will accept the passphrase via
# STDIN, via the environment variable AGE_PASSPHRASE, or will prompt for it.
# Upon successful restoration of the identity file, this script will create new
# checksum files for both the passphrase-encrypted file and the restored
# identity file.

# NOTE: This script uses age built-in to chezmoi, and does not have a dependency
# on age itself.

set -eufo pipefail

PATH="$HOME/.local/bin"
PATH="$PATH:/opt/homebrew/bin:/home/linuxbrew/.linuxbrew/bin"
PATH="$PATH:/usr/local/bin:/usr/bin:/bin"

conf_dir="$HOME/.config/chezmoi"
src_dir="$HOME/.local/share/chezmoi"

encr_file="$src_dir/.support/encrypted/chezmoi.key.age"
encr_file_sum="$conf_dir/$(basename "$encr_file").sha256"

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

# Exit if the checksums for the encryption and identity files match
if [[ -r "$ident_file" && -r "$ident_file_sum" && \
      -r "$encr_file" && -r "$encr_file_sum" ]]; then
    if [[ "$(checksum "$encr_file")" == "$(cat "$encr_file_sum")" && \
          "$(checksum "$ident_file")" == "$(cat "$ident_file_sum")" ]]; then
        exit 0
    fi
    rm -f "$ident_file" "$encr_file_sum" "$ident_file_sum" \
        || abort "Failed to remove the outdated identity file or checksums."
fi

[[ -r "$encr_file" ]] || abort "The encrypted file was not found."

for cmd in chezmoi mktemp; do
    command -v "$cmd" >/dev/null 2>&1 \
        || abort "The \"$cmd\" command was not found."
done

temp_config_file=$(mktemp) || abort "Failed to create the temp config file."
trap 'rm -f "$temp_config_file"' EXIT INT TERM HUP

{
    printf 'useBuiltinAge: true\n'
    printf 'warnings:\n'
    printf '  configFileTemplateHasChanged: false\n'
} > "$temp_config_file" || abort "Failed to write to the temp config file."

mkdir -p "$conf_dir" || abort "Failed to create the directory \"$conf_dir\"."
chmod 700 "$conf_dir" || abort "Failed to set the permissions on \"$conf_dir\"."

# Handle passphrase: stdin, AGE_PASSPHRASE, or custom prompt
passphrase=""
if [[ ! -t 0 ]]; then
    read -r passphrase < /dev/stdin || true
else
    read -r -t 1 passphrase < /dev/stdin || true
fi

decrypt_with_passphrase() {
    local passphrase="$1"
    echo "$passphrase" | chezmoi age decrypt --config "$temp_config_file" \
        --config-format yaml --no-tty --passphrase --output "$ident_file" \
        "$encr_file" >/dev/null 2>&1 \
            || abort "Failed to restore the identity file."
}

if [[ -n "$passphrase" ]]; then
    decrypt_with_passphrase "$passphrase"
elif [[ -n "${AGE_PASSPHRASE:-}" ]]; then
    decrypt_with_passphrase "$AGE_PASSPHRASE"
elif [[ -t 0 ]]; then
    echo -n "Enter the encryption passphrase: " >&2
    read -r -s passphrase
    echo >&2
    [[ -n "$passphrase" ]] || abort "No encryption passphrase was provided."
    decrypt_with_passphrase "$passphrase"
else
    abort "No encryption passphrase was provided."
fi

chmod 600 "$ident_file" \
    || abort "Failed to set the permissions on \"$(basename $ident_file)\"."

 # Save checksums
checksum "$encr_file" > "$encr_file_sum" \
    || abort "Failed to save the encrypted file checksum."
checksum "$ident_file" > "$ident_file_sum" \
    || abort "Failed to save the identity file checksum."
chmod 600 "$encr_file_sum" "$ident_file_sum" \
    || abort "Failed to set permissions on the checksums."

echo "The identity file was restored successfully."
