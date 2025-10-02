#!/bin/bash
set -e

USER="beacn-on-linux"
REPOSITORY="beacn-utility-repo"

# Detect OSTree immutable system
if [ -f /run/ostree-booted ]; then
    echo "Immutable OSTree-based system detected. Use the Flatpak version:"
    echo "  https://${USER}.github.io/${REPOSITORY}/scripts/install-flatpak.sh"
    exit 1
fi

GPG_KEY_URL="https://${USER}.github.io/${REPOSITORY}/public.gpg"
RPM_REPO_URL="https://${USER}.github.io/${REPOSITORY}/rpm/beacn-on-linux.repo"

echo "Installing the Beacn on Linux RPM repository..."
echo "Your password may be requested to install the security key and configure the repository."
echo ""

# Import GPG key for verification
echo "Installing security key"
TMP_KEY="$(mktemp)"
curl -fsSL "${GPG_KEY_URL}" -o "${TMP_KEY}"
sudo rpm --import "$TMP_KEY"

# Install RPM repo file
echo "Configuring repository"
sudo curl -fsSL "$RPM_REPO_URL" -o /etc/yum.repos.d/beacn-on-linux.repo

echo "Installing Beacn Utility"
sudo dnf -y install beacn-utility || sudo yum -y install beacn-utility

echo "Installation Complete"
