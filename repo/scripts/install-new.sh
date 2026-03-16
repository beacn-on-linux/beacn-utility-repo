#!/usr/bin/env bash

# =============================================================================
# Stage 1 — Boostrapping
#
# So before we do anything, see if we have any gui tools (zenity / kdialog), and if
# we do use them directly rather than having a terminal.
# =============================================================================

_has_display() {
    [ -n "${DISPLAY:-}" ] || [ -n "${WAYLAND_DISPLAY:-}" ]
}

_has_gui_tools() {
    _has_display || return 1
    command -v zenity &>/dev/null || command -v kdialog &>/dev/null
}

# Conditions in which we may need to spawn a terminal:
# 1: We've not already re-execed (avoid infinite loop)
# 2: We have a display (So we can launch the terminal app)
# 3: We don't have GUI dialog tools
# 4: Stdin is not a TTY (we're not already inside a terminal)
if [ "${_TERMINAL_REEXEC:-}" != "1" ] && _has_display && ! _has_gui_tools && [ ! -t 0 ]; then
    # This is simply a list of possible terminals we could try and spawn to run the installer in.
    terminal_candidates=(
        "gnome-terminal:--"
        "konsole:-e"
        "xfce4-terminal:-x"
        "mate-terminal:-x"
        "tilix:-e"
        "lxterminal:-e"
        "xterm:-e"
        "kitty:"
        "alacritty:-e"
        "foot:-e"
        "urxvt:-e"
        "rxvt:-e"
    )

    TERMINAL_BIN=""
    TERMINAL_FLAG=""
    for entry in "${terminal_candidates[@]}"; do
        bin="${entry%%:*}"
        flag="${entry##*:}"
        if command -v "$bin" &>/dev/null; then
            TERMINAL_BIN="$bin"
            TERMINAL_FLAG="$flag"
            break
        fi
    done

    if [ -n "$TERMINAL_BIN" ]; then
        export _TERMINAL_REEXEC=1
        SELF="$(realpath "$0")"

        # Wrap in a shell so the window pauses on failure rather than
        # closing before the user can read any error output.
        if [ -n "$TERMINAL_FLAG" ]; then
            exec "$TERMINAL_BIN" "$TERMINAL_FLAG" bash -c \
                "bash '$SELF'; code=\$?; [ \$code -ne 0 ] && { echo; read -rp 'Press Enter to close...'; }; exit \$code"
        else
            exec "$TERMINAL_BIN" bash -c \
                "bash '$SELF'; code=\$?; [ \$code -ne 0 ] && { echo; read -rp 'Press Enter to close...'; }; exit \$code"
        fi
        echo "Failed to launch terminal emulator." >&2
        exit 1
    else
        # I'm honestly not sure what we can do here, we're not in an active terminal, we can't spawn a terminal, and
        # we don't have GUI tools to show a message box. Best effort is to hope that xmessage is available to display
        # *SOMETHING*,
        msg="Unable to launch the install script. Please contact us on Discord for support."
        if command -v xmessage &>/dev/null; then
            xmessage "$msg"
        else
            echo -e "$msg" >&2
        fi
        exit 1
    fi
fi

# If stdin is not a TTY (piped: curl ... | bash), re-exec with /dev/tty.
if [ "${_PIPED_REEXEC:-}" != "1" ] && [ "${_DESKTOP_LAUNCH:-}" != "1" ] && [ ! -t 0 ]; then
    if [ -t 1 ] && [ -r /dev/tty ] && [ -w /dev/tty ]; then
        TEMP_FILE="$(mktemp)" || { echo "Failed to create temp file"; exit 1; }
        cat >"$TEMP_FILE" || { echo "Failed to save piped script"; exit 1; }
        chmod +x "$TEMP_FILE"
        export _PIPED_REEXEC=1
        if [ -n "${BASH:-}" ]; then
            exec "$BASH" "$TEMP_FILE" "$@" < /dev/tty
        else
            exec bash "$TEMP_FILE" "$@" < /dev/tty
        fi
        rm -f "$TEMP_FILE"
        echo "Failed to re-exec installer." >&2
        exit 1
    else
        echo "Error: no usable TTY for interaction. Re-run the script in a terminal." >&2
        exit 1
    fi
fi

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

GH_USER="beacn-on-linux"
REPOSITORY="beacn-utility-repo"
BASE_URL="https://${GH_USER}.github.io/${REPOSITORY}"

GPG_KEY_URL="${BASE_URL}/public.gpg"
APT_REPO_LIST_URL="${BASE_URL}/deb/beacn-on-linux.list"
RPM_REPO_URL="${BASE_URL}/rpm/beacn-on-linux.repo"
FLATPAK_REF="${BASE_URL}/flatpak/beacn-utility.flatpakref"
AUR_PACKAGE="beacn-utility"

# ---------------------------------------------------------------------------
# UI helpers
#
# Each function tries, in order:
#   1. zenity       — GTK GUI dialog (X11/Wayland, GNOME et al.)
#   2. kdialog      — KDE GUI dialog (X11/Wayland, KDE Plasma)
#   3. whiptail     — ncurses TUI
#   4. dialog       — ncurses TUI
#   5. plain read   — bare terminal fallback, always available
# ---------------------------------------------------------------------------

# ui_select TITLE PROMPT option1 option2 ...
# Sets REPLY to the chosen option string, or exits if cancelled.
ui_select() {
    local title="$1" prompt="$2"; shift 2
    local options=("$@")
    local i choice

    local -a menu_args=()
    for i in "${!options[@]}"; do
        menu_args+=("$((i+1))" "${options[$i]}")
    done

    if _has_display && command -v zenity &>/dev/null; then
        REPLY=$(zenity --list \
            --title="$title" \
            --text="$prompt" \
            --column="Option" \
            "${options[@]}" 2>/dev/null) || { echo "Installation cancelled."; exit 0; }

    elif _has_display && command -v kdialog &>/dev/null; then
        local -a kd_args=()
        for i in "${!options[@]}"; do
            kd_args+=("${options[$i]}" "${options[$i]}")
        done
        REPLY=$(kdialog --menu "$prompt" "${kd_args[@]}" 2>/dev/null) \
            || { echo "Installation cancelled."; exit 0; }

    elif command -v whiptail &>/dev/null || command -v dialog &>/dev/null; then
        local cmd; command -v whiptail &>/dev/null && cmd=whiptail || cmd=dialog
        choice=$("$cmd" --title "$title" \
            --menu "$prompt" 20 60 "${#options[@]}" \
            "${menu_args[@]}" \
            3>&1 1>&2 2>&3) || { echo "Installation cancelled."; exit 0; }
        REPLY="${options[$((choice-1))]}"

    else
        echo "$prompt"
        for i in "${!options[@]}"; do
            printf "  %d) %s\n" "$((i+1))" "${options[$i]}"
        done
        printf "  %d) Exit\n" "$(( ${#options[@]} + 1 ))"
        read -rp "Select [1-$(( ${#options[@]} + 1 ))]: " choice
        [[ "$choice" =~ ^[0-9]+$ ]] || { echo "Invalid choice."; exit 1; }
        (( choice == ${#options[@]} + 1 )) && { echo "Installation cancelled."; exit 0; }
        (( choice < 1 || choice > ${#options[@]} )) && { echo "Invalid choice."; exit 1; }
        REPLY="${options[$((choice-1))]}"
    fi
}

# ui_confirm TITLE MESSAGE
# Returns 0 (yes) or 1 (no/cancel).
ui_confirm() {
    local title="$1" msg="$2"

    if _has_display && command -v zenity &>/dev/null; then
        zenity --question --title="$title" --text="$msg" 2>/dev/null

    elif _has_display && command -v kdialog &>/dev/null; then
        kdialog --yesno "$msg" 2>/dev/null

    elif command -v whiptail &>/dev/null || command -v dialog &>/dev/null; then
        local cmd; command -v whiptail &>/dev/null && cmd=whiptail || cmd=dialog
        "$cmd" --title "$title" --yesno "$msg" 10 60 3>&1 1>&2 2>&3

    else
        read -rp "$msg [y/N] " ans
        [[ "${ans,,}" == y* ]]
    fi
}

# ui_info TITLE MESSAGE
# Shows a non-interactive notice (OK only).
ui_info() {
    local title="$1" msg="$2"

    if _has_display && command -v zenity &>/dev/null; then
        zenity --info --title="$title" --text="$msg" 2>/dev/null

    elif _has_display && command -v kdialog &>/dev/null; then
        kdialog --msgbox "$msg" 2>/dev/null

    elif command -v whiptail &>/dev/null || command -v dialog &>/dev/null; then
        local cmd; command -v whiptail &>/dev/null && cmd=whiptail || cmd=dialog
        "$cmd" --title "$title" --msgbox "$msg" 10 60 3>&1 1>&2 2>&3

    else
        echo ""
        echo "=== $title ==="
        echo "$msg"
        echo ""
    fi
}

# ---------------------------------------------------------------------------
# Progress bar
#
# Usage:
#   progress_start TITLE TOTAL_STEPS
#   progress_step  "Step label"
#   progress_finish                    (also called automatically on EXIT)
# ---------------------------------------------------------------------------

_PROGRESS_PIPE=""
_PROGRESS_PID=""
_PROGRESS_STEP=0
_PROGRESS_TOTAL=0
_PROGRESS_MODE=""
_KDIALOG_DBUS=""

progress_start() {
    local title="$1"
    _PROGRESS_TOTAL="$2"
    _PROGRESS_STEP=0

    trap progress_finish EXIT

    if _has_display && command -v zenity &>/dev/null; then
        _PROGRESS_MODE="zenity"
        _PROGRESS_PIPE="$(mktemp -u /tmp/beacn-progress-XXXXXX)"
        mkfifo "$_PROGRESS_PIPE"
        zenity --progress \
            --title="$title" \
            --text="Starting..." \
            --percentage=0 \
            --auto-close \
            --no-cancel \
            < "$_PROGRESS_PIPE" &
        _PROGRESS_PID=$!
        exec 3>"$_PROGRESS_PIPE"

    elif _has_display && command -v kdialog &>/dev/null; then
        _PROGRESS_MODE="kdialog"
        _KDIALOG_DBUS=$(kdialog --progressbar "$title" "$_PROGRESS_TOTAL" 2>/dev/null)

    elif command -v whiptail &>/dev/null || command -v dialog &>/dev/null; then
        _PROGRESS_MODE="whiptail"
        _PROGRESS_PIPE="$(mktemp -u /tmp/beacn-progress-XXXXXX)"
        mkfifo "$_PROGRESS_PIPE"
        local cmd; command -v whiptail &>/dev/null && cmd=whiptail || cmd=dialog
        "$cmd" --title "$title" --gauge "Starting..." 8 60 0 < "$_PROGRESS_PIPE" &
        _PROGRESS_PID=$!
        exec 3>"$_PROGRESS_PIPE"

    else
        _PROGRESS_MODE="plain"
    fi
}

progress_step() {
    local label="${1:-}"
    _PROGRESS_STEP=$(( _PROGRESS_STEP + 1 ))
    local pct=$(( _PROGRESS_STEP * 100 / _PROGRESS_TOTAL ))

    case "$_PROGRESS_MODE" in
        zenity)
            printf '# %s\n%d\n' "$label" "$pct" >&3
            ;;
        kdialog)
            qdbus $_KDIALOG_DBUS Set "" "value" "$_PROGRESS_STEP" &>/dev/null || true
            qdbus $_KDIALOG_DBUS setLabelText "$label" &>/dev/null || true
            ;;
        whiptail)
            printf '%d\nXXX\n%s\nXXX\n' "$pct" "$label" >&3
            ;;
        plain)
            printf '[%d/%d] %s\n' "$_PROGRESS_STEP" "$_PROGRESS_TOTAL" "$label"
            ;;
    esac
}

progress_finish() {
    trap - EXIT

    case "$_PROGRESS_MODE" in
        zenity|whiptail)
            { printf '100\n' >&3; } 2>/dev/null || true
            exec 3>&- 2>/dev/null || true
            [ -n "$_PROGRESS_PIPE" ] && rm -f "$_PROGRESS_PIPE"
            [ -n "$_PROGRESS_PID" ] && wait "$_PROGRESS_PID" 2>/dev/null || true
            ;;
        kdialog)
            qdbus $_KDIALOG_DBUS close &>/dev/null || true
            ;;
        plain)
            :
            ;;
    esac

    _PROGRESS_PIPE=""
    _PROGRESS_PID=""
    _PROGRESS_MODE=""
    _KDIALOG_DBUS=""
}

# ---------------------------------------------------------------------------
# Privilege escalation — GUI-friendly, terminal fallback
# ---------------------------------------------------------------------------

ESCALATE=""
_detect_escalate() {
    if command -v pkexec &>/dev/null; then
        if dbus-send --system --print-reply \
               --dest=org.freedesktop.PolicyKit1 \
               /org/freedesktop/PolicyKit1/Authority \
               org.freedesktop.DBus.Peer.Ping &>/dev/null 2>&1; then
            ESCALATE="pkexec"
            # Warm up a polkit session by running a no-op so subsequent
            # calls reuse the same authentication within the session window.
            pkexec true 2>/dev/null || true
            return
        fi
    fi

    if [ -t 0 ]; then
        if command -v sudo &>/dev/null; then
            ESCALATE="sudo"
            # Cache credentials upfront so subsequent calls don't re-prompt.
            sudo -v
            return
        fi
        if command -v su &>/dev/null; then
            ESCALATE="su_c"
            return
        fi
    fi

    local msg
    msg="Administrator privileges are required, but no supported "
    msg+="escalation method was found.\n\n"
    msg+="Please install polkit (pkexec), or run this script from a terminal."
    ui_info "Cannot escalate privileges" "$msg"
    exit 1
}

run_privileged() {
    if [ -z "$ESCALATE" ]; then
        _detect_escalate
    fi

    case "$ESCALATE" in
        pkexec) pkexec "$@" ;;
        sudo)   sudo "$@" ;;
        su_c)   su -c "$(printf '%q ' "$@")" root ;;
    esac
}

# ---------------------------------------------------------------------------
# Version helpers
# ---------------------------------------------------------------------------

version_gte() {
    [ "$(printf '%s\n%s' "$2" "$1" | sort -V | tail -n1)" = "$1" ]
}

# ---------------------------------------------------------------------------
# Detect available install methods
# ---------------------------------------------------------------------------

is_immutable=false
[ -f /run/ostree-booted ] && is_immutable=true

available=()

command -v apt &>/dev/null && available+=("deb")

if ! $is_immutable; then
    if command -v dnf &>/dev/null || command -v yum &>/dev/null || command -v zypper &>/dev/null; then
        available+=("rpm")
    fi
fi

aur_helper=""
if command -v yay &>/dev/null; then
    available+=("aur"); aur_helper="yay"
elif command -v paru &>/dev/null; then
    available+=("aur"); aur_helper="paru"
elif command -v pamac &>/dev/null && grep -q '^\s*EnableAUR' /etc/pamac.conf 2>/dev/null; then
    available+=("aur"); aur_helper="pamac"
fi

if command -v flatpak &>/dev/null; then
    flatpak_version="$(flatpak --version | awk '{print $2}')"
    if version_gte "$flatpak_version" "1.15.11"; then
        available+=("flatpak")
    fi
fi

if [ ${#available[@]} -eq 0 ]; then
    ui_info "No supported package manager" \
        "No supported package managers were found.\n\nSupported: apt, dnf/yum/zypper, flatpak, AUR helpers (yay/paru/pamac)."
    exit 1
fi

# ---------------------------------------------------------------------------
# Friendly names
# ---------------------------------------------------------------------------

friendly_name() {
    case "$1" in
        deb)     echo "Debian / Ubuntu  (.deb via apt)" ;;
        rpm)     echo "Fedora / RHEL / openSUSE  (.rpm via dnf/yum/zypper)" ;;
        aur)     echo "Arch Linux  (AUR via $aur_helper)" ;;
        flatpak) echo "Flatpak  (distro-agnostic sandboxed install)" ;;
        *)       echo "$1" ;;
    esac
}

# ---------------------------------------------------------------------------
# Install methods
# ---------------------------------------------------------------------------

install_deb() {
    ui_confirm "Install via APT" \
        "This will:\n  • Import the BEACN GPG signing key\n  • Add the BEACN apt repository\n  • Install beacn-utility\n\nYou will be prompted for your password.\n\nProceed?" \
        || { echo "Installation cancelled."; exit 0; }

    _detect_escalate

    progress_start "Installing BEACN Utility" 4

    progress_step "Downloading and importing signing key..."
    curl -fsSL "$GPG_KEY_URL" \
        | gpg --dearmor \
        | run_privileged tee /usr/share/keyrings/beacn-on-linux.gpg >/dev/null

    progress_step "Configuring apt repository..."
    run_privileged curl -fsSL "$APT_REPO_LIST_URL" \
        -o /etc/apt/sources.list.d/beacn-on-linux.list

    progress_step "Updating package lists..."
    run_privileged apt-get update -q

    progress_step "Installing beacn-utility..."
    run_privileged apt-get install -y beacn-utility

    progress_finish
    ui_info "Installation complete" "BEACN Utility has been installed successfully."
}

install_rpm() {
    ui_confirm "Install via DNF/YUM" \
        "This will:\n  • Import the BEACN GPG signing key\n  • Add the BEACN RPM repository\n  • Install beacn-utility\n\nYou will be prompted for your password.\n\nProceed?" \
        || { echo "Installation cancelled."; exit 0; }

    _detect_escalate

    progress_start "Installing BEACN Utility" 4

    progress_step "Downloading signing key..."
    TMP_KEY="$(mktemp)"
    curl -fsSL "$GPG_KEY_URL" -o "$TMP_KEY"

    progress_step "Importing signing key..."
    run_privileged rpm --import "$TMP_KEY"
    rm -f "$TMP_KEY"

    progress_step "Configuring RPM repository..."
    run_privileged curl -fsSL "$RPM_REPO_URL" \
        -o /etc/yum.repos.d/beacn-on-linux.repo

    progress_step "Installing beacn-utility..."
    run_privileged dnf -y install beacn-utility 2>/dev/null \
        || run_privileged yum -y install beacn-utility

    progress_finish
    ui_info "Installation complete" "BEACN Utility has been installed successfully."
}

install_flatpak() {
    ui_confirm "Install via Flatpak" \
        "This will install BEACN Utility as a Flatpak from:\n${FLATPAK_REF}\n\nProceed?" \
        || { echo "Installation cancelled."; exit 0; }

    # flatpak handles its own progress output and privilege escalation
    # internally, and needs a real TTY for its interactive prompts.
    echo "Installing BEACN Utility (Flatpak)..."
    flatpak install "$FLATPAK_REF" < /dev/tty

    ui_info "Installation complete" "BEACN Utility has been installed successfully."
}

install_aur() {
    ui_confirm "Install via AUR ($aur_helper)" \
        "This will install ${AUR_PACKAGE} using ${aur_helper}.\n\nProceed?" \
        || { echo "Installation cancelled."; exit 0; }

    # AUR helpers manage their own escalation and progress output.
    echo "Installing BEACN Utility (AUR)..."
    case "$aur_helper" in
        yay|paru) $aur_helper -S "$AUR_PACKAGE" ;;
        pamac)    pamac install "$AUR_PACKAGE" ;;
    esac

    ui_info "Installation complete" "BEACN Utility has been installed successfully."
}

# ---------------------------------------------------------------------------
# Select install method
# ---------------------------------------------------------------------------

chosen=""

if [ ${#available[@]} -eq 1 ]; then
    chosen="${available[0]}"
else
    friendly_opts=()
    for opt in "${available[@]}"; do
        friendly_opts+=("$(friendly_name "$opt")")
    done

    ui_select "BEACN Utility Installer" \
        "Multiple installation methods are available.\nChoose the one that matches your system:" \
        "${friendly_opts[@]}"

    for i in "${!friendly_opts[@]}"; do
        [[ "${friendly_opts[$i]}" == "$REPLY" ]] && chosen="${available[$i]}" && break
    done
fi

# ---------------------------------------------------------------------------
# Run chosen installer
# ---------------------------------------------------------------------------

case "$chosen" in
    deb)     install_deb ;;
    rpm)     install_rpm ;;
    flatpak) install_flatpak ;;
    aur)     install_aur ;;
    *)       echo "Unknown install type: $chosen"; exit 1 ;;
esac