#!/bin/bash
set -e

USER="beacn-on-linux"
REPOSITORY="beacn-utility-repo"

GPG_KEY_URL="https://${USER}.github.io/${REPOSITORY}/public.gpg"
APT_REPO_LIST_URL="https://${USER}.github.io/${REPOSITORY}/deb/beacn-on-linux.list"

echo "Installing the Beacn on Linux DEB repository..."
echo "Your password may be requested to install the security key and configure the repository."
echo ""

# Import GPG key for verification
echo "Installing security key"
curl -fsSL "$GPG_KEY_URL" | gpg --dearmor | sudo tee /usr/share/keyrings/beacn-on-linux.gpg >/dev/null

# Install DEB repo file
echo "Configuring repository"
sudo curl -fsSL "$APT_REPO_LIST_URL" -o /etc/apt/sources.list.d/beacn-on-linux.list
sudo apt-get update

echo "Installing Beacn Utility"
sudo apt-get install -y beacn-utility

echo "Installation Complete"