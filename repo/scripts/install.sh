#!/usr/bin/env bash

# If we don't have a TTY, dump and rerun this script with /dev/tty as stdin.
if [ "${_PIPED_REEXEC:-}" != "1" ] && [ ! -t 0 ]; then
    if [ -t 1 ] && [ -r /dev/tty ] && [ -w /dev/tty ]; then
        TEMP_FILE="$(mktemp)" || { echo "Failed to create temp file"; exit 1; }
        cat >"$TEMP_FILE" || { echo "Failed to save piped script"; exit 1; }
        chmod +x "$TEMP_FILE"

        export _PIPED_REEXEC=1

        # Use the same bash executable if available, otherwise use 'bash' from PATH.
        if [ -n "${BASH:-}" ]; then
            exec "$BASH" "$TEMP_FILE" "$@" < /dev/tty
        else
            exec bash "$TEMP_FILE" "$@" < /dev/tty
        fi

        # If exec fails for some reason, clean up and exit.
        rm -f "$TEMP_FILE"
        echo "Failed to re-exec installer." >&2
        exit 1
    else
        echo "Error: no usable TTY for interaction. Re-run the script in a terminal." >&2
        exit 1
    fi
fi

set -euo pipefail

# These are just helpers, so that forks can easily change settings
USER="beacn-on-linux"
REPOSITORY="beacn-utility-repo"

# Individual scripts are stored here:
DEB_URL="https://${USER}.github.io/${REPOSITORY}/scripts/install-deb.sh"
RPM_URL="https://${USER}.github.io/${REPOSITORY}/scripts/install-rpm.sh"
FLATPAK_URL="https://${USER}.github.io/${REPOSITORY}/scripts/install-flatpak.sh"
AUR_PACKAGE="beacn-utility"

# We need to check which package managers are available, but first we need to confirm whether this is an
# immutable system, where RPM-based installs won't work.
is_immutable=false
if [ -f /run/ostree-booted ]; then
    is_immutable=true
fi

available=()

# Check for APT
if command -v apt >/dev/null 2>&1; then
    available+=("deb")
fi

# Check for RPM managers
if command -v dnf >/dev/null 2>&1 || command -v yum >/dev/null 2>&1 || command -v zypper >/dev/null 2>&1; then
    available+=("rpm")
fi

# Check for any AUR helpers
aur_helper=""
if command -v yay >/dev/null 2>&1; then
    available+=("aur")
    aur_helper="yay"
elif command -v paru >/dev/null 2>&1; then
    available+=("aur")
    aur_helper="paru"
elif command -v pamac >/dev/null 2>&1 && grep -q '^\s*EnableAUR' /etc/pamac.conf 2>/dev/null; then
    available+=("aur")
    aur_helper="pamac"
fi

# Check for Flatpak support
if command -v flatpak >/dev/null 2>&1; then
    available+=("flatpak")
fi

# If we're immutable, RPM isn't valid, remove it from the list
if $is_immutable; then
    filtered=()
    for opt in "${available[@]}"; do
        if [ "$opt" != "rpm" ]; then
            filtered+=("$opt")
        fi
    done
    available=("${filtered[@]}")
fi

if [ ${#available[@]} -eq 0 ]; then
    echo "No supported package managers found (apt, dnf/yum/zypper, flatpak, AUR)."
    exit 1
fi

# Friendly names for user prompt
friendly_name() {
    case "$1" in
        deb) echo "Debian/Ubuntu (.deb via apt)" ;;
        rpm) echo "Fedora/RHEL/openSUSE (.rpm via dnf/yum/zypper)" ;;
        aur) echo "Arch Linux / AUR helper ($aur_helper)" ;;
        flatpak) echo "Flatpak (distro-agnostic sandboxed install)" ;;
        *) echo "$1" ;;
    esac
}

# Function to download and run installer
run_installer() {
    url="$1"
    name="$2"

    echo "Downloading installer for $name..."
    if ! curl -fsSL -o "$TEMP_FILE" "$url"; then
        echo "Failed to download installer script."
        exit 1
    fi

    echo ""
    echo "Installer script for $name downloaded to: $TEMP_FILE"
    echo "URL: $url"
    echo ""
    read -rp "Press Enter to continue (or any other key to cancel)..."

    if [[ -z "$REPLY" ]]; then
        bash "$TEMP_FILE"
    else
        echo "Installation cancelled by user."
        exit 0
    fi
}

# Select install method
chosen=""
if [ ${#available[@]} -eq 1 ]; then
    chosen="${available[0]}"
else
    echo "Multiple installation methods available:"
    i=1
    for opt in "${available[@]}"; do
        echo "  $i) $(friendly_name "$opt")"
        i=$((i+1))
    done
    echo "  $i) Exit"
    read -rp "Select installation method [1-$i]: " choice

    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt $i ]; then
        echo "Invalid choice."
        exit 1
    fi

    if [ "$choice" -eq $i ]; then
        echo "Installation cancelled by user."
        exit 0
    fi

    chosen="${available[$((choice-1))]}"
fi

# Run the chosen installer
case "$chosen" in
    deb)
        run_installer "$DEB_URL" "deb"
        ;;
    rpm)
        run_installer "$RPM_URL" "rpm"
        ;;
    flatpak)
        run_installer "$FLATPAK_URL" "flatpak"
        ;;
    aur)
        echo "Installing $AUR_PACKAGE via $aur_helper..."
        case "$aur_helper" in
            yay|paru)
                $aur_helper -S "$AUR_PACKAGE"
                ;;
            pamac)
                pamac install "$AUR_PACKAGE"
                ;;
        esac
        ;;
    *)
        echo "Unknown install type: $chosen"
        exit 1
        ;;
esac