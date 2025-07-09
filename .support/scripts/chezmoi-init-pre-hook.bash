#!/bin/bash

# NOTE: The purpose of this script is to run as a "pre init hook" for chezmoi.
# This script will run prior to every call to "chezmoi init". This script allows
# more than one command to be ran in this context.

# NOTE: Hooks in chezmoi are ran every time. Even when in dry-run mode.

set -eufo pipefail

source_dir="$HOME/.local/share/chezmoi"
support_scripts_dir="$source_dir/.support/scripts"

$support_scripts_dir/restore-age-identity-file.bash
