#!/bin/sh

# Script to synchronize system state
# with configuration files for nixos system
# and home-manager

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# Fix root-owned sqlite errors
sudo chown -R 1000:users ~/.cache/nix;

# Install and build home-manager configuration
home-manager switch --impure --flake $SCRIPT_DIR;

$SCRIPT_DIR/sync-posthook.sh
