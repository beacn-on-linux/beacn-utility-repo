#!/bin/bash
set -e

USER="beacn-on-linux"
REPOSITORY="beacn-utility-repo"

FLATPAK_REF="https://${USER}.github.io/${REPOSITORY}/flatpak/beacn-utility.flatpakref"

echo "Installing Beacn Utility via Flatpak"
flatpak install ${FLATPAK_REF} < /dev/tty

echo "Installation Complete"