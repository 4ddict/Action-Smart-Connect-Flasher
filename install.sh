#!/usr/bin/env bash
set -Eeuo pipefail

# LSC 3215672.2 Decloud Wizard
# Beginner-friendly Linux installer for the Action LSC Smart Connect 3215672.2
# This project does NOT redistribute vendor firmware. It builds a custom APP
# image from the user's own camera dump.

VERSION="0.2.0"
WORK_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/lsc-3215672-decloud-wizard"
SRC_DIR="$WORK_DIR/sources"
BACKUP_DIR="$WORK_DIR/backups"
BUILD_DIR="$WORK_DIR/build"
MOUNT_DIR="$WORK_DIR/sd"
STATE_FILE="$WORK_DIR/state.env"
RUNTIME_DIR="$WORK_DIR/runtime"
GITHUB_REPO="${LSC_WIZARD_REPO:-4ddict/LSC-3215672-Decloud-Wizard}"
GITHUB_BRANCH="${LSC_WIZARD_BRANCH:-main}"
RAW_BASE="https://raw.githubusercontent.com/${GITHUB_REPO}/${GITHUB_BRANCH}"
TOOLKIT_REPO="https://github.com/tasarren/lsc-tuya-toolkit.git"
FIRMWARE_REPO="https://github.com/FluxAlchemist/LSC_AK3918AV130_cam_custom_firmware.git"
SMOLRTSP_REPO="https://github.com/OpenIPC/smolrtsp.git"
SD_LABEL="LSC_DECLOUD"
EXPECTED_APP_SIZE=5242880
CAMERA_NAME=""
CAMERA_HOSTNAME=""
CAMERA_BACKUP_DIR=""
CAMERA_BUILD_DIR=""
LATEST_BACKUP_FILE=""

# When run from a cloned/downloaded repository, use the local helper scripts.
# When launched with the one-line curl command, fetch those tiny helpers into
# the cache directory so the user still only has to run one command.
SCRIPT_SOURCE="${BASH_SOURCE[0]:-}"
if [[ -n "$SCRIPT_SOURCE" && -f "$SCRIPT_SOURCE" && -d "$(cd "$(dirname "$SCRIPT_SOURCE")" 2>/dev/null && pwd)/camera" ]]; then
    SELF_DIR="$(cd "$(dirname "$SCRIPT_SOURCE")" && pwd)"
else
    SELF_DIR="$RUNTIME_DIR"
fi

# ── Appearance ───────────────────────────────────────────────────────────────
if command -v tput >/dev/null 2>&1 && [[ -t 1 ]]; then
    BOLD="$(tput bold)"; DIM="$(tput dim)"; RESET="$(tput sgr0)"
    GREEN="$(tput setaf 2)"; YELLOW="$(tput setaf 3)"; RED="$(tput setaf 1)"
    CYAN="$(tput setaf 6)"; BLUE="$(tput setaf 4)"
else
    BOLD=""; DIM=""; RESET=""; GREEN=""; YELLOW=""; RED=""; CYAN=""; BLUE=""
fi

CHECK="${GREEN}✔${RESET}"
CROSS="${RED}✖${RESET}"
ARROW="${CYAN}➜${RESET}"
WARNICON="${YELLOW}⚠${RESET}"
INFOICON="${BLUE}●${RESET}"
QUESTION="${CYAN}?${RESET}"

say() { printf '%b\n' "$*"; }
info() { say "${INFOICON} $*"; }
ok() { say "${CHECK} $*"; }
warn() { say "${WARNICON} ${YELLOW}$*${RESET}"; }
die() { say "${CROSS} ${RED}$*${RESET}" >&2; exit 1; }
step() { say "${ARROW} ${BOLD}$*${RESET}"; }
pause() { printf '\n%b Press Enter to continue... ' "${ARROW}"; read -r _; }

hr() {
    say "${DIM}────────────────────────────────────────────────────────────${RESET}"
}

section() {
    local num="$1" total="$2" title="$3"
    say ""
    hr
    say "${CYAN}${BOLD}[${num}/${total}] ${title}${RESET}"
    hr
}

ask_menu() {
    # Usage: ask_menu "Prompt" min max
    local prompt="$1" min="$2" max="$3" value
    while true; do
        printf "%b %s" "$QUESTION" "$prompt"
        read -r value
        if [[ "$value" =~ ^[0-9]+$ ]] && (( value >= min && value <= max )); then
            REPLY="$value"
            return 0
        fi
        warn "Please enter a number from $min to $max."
    done
}

ask_yes_no() {
    # Returns 0 for yes and 1 for no. Invalid input is simply asked again.
    local prompt="$1" default="${2:-yes}" answer
    while true; do
        if [[ "$default" == "yes" ]]; then
            printf "%b %s [Y/n]: " "$QUESTION" "$prompt"
        else
            printf "%b %s [y/N]: " "$QUESTION" "$prompt"
        fi
        read -r answer
        answer="${answer,,}"
        if [[ -z "$answer" ]]; then
            [[ "$default" == "yes" ]] && return 0 || return 1
        fi
        case "$answer" in
            y|yes) return 0 ;;
            n|no) return 1 ;;
            *) warn "Please answer yes or no." ;;
        esac
    done
}

quit_cleanly() {
    say ""
    info "Nothing else was changed. You can run the wizard again whenever you are ready."
    exit 0
}

cleanup_mount() {
    if mountpoint -q "$MOUNT_DIR" 2>/dev/null; then
        sudo umount "$MOUNT_DIR" >/dev/null 2>&1 || true
    fi
}
trap cleanup_mount EXIT

mkdir -p "$WORK_DIR" "$SRC_DIR" "$BACKUP_DIR" "$BUILD_DIR" "$MOUNT_DIR" "$RUNTIME_DIR"

banner() {
    clear 2>/dev/null || true
    cat <<'BANNER'
╔══════════════════════════════════════════════════════════════╗
║              LSC 3215672.2 DECLOUD WIZARD                  ║
║              Tuya cloud  ➜  Local RTSP                     ║
╚══════════════════════════════════════════════════════════════╝
BANNER
    say "${DIM}Beginner-friendly installer for the Action LSC Smart Connect camera${RESET}"
    say "${DIM}Anyka AK3918AV130 • ak_rtsp • Linux${RESET}"
    say ""
    say "Version ${BOLD}${VERSION}${RESET}"
    say ""
    say "This wizard will guide you through every physical step."
    say "No Telnet commands, cross-compiling knowledge, or MTD knowledge is required."
    say ""
    warn "Supported model ONLY: 3215672.2 / SI B26101"
}

ensure_wizard_assets() {
    local missing=0 f
    mkdir -p "$SELF_DIR/camera"
    for f in decloud_stage1.sh decloud_flash.sh; do
        [[ -s "$SELF_DIR/camera/$f" ]] || missing=1
    done
    (( missing == 0 )) && return 0

    info "Downloading the wizard helper files..."
    command -v curl >/dev/null 2>&1 || die "curl is required for the one-line installer."
    for f in decloud_stage1.sh decloud_flash.sh; do
        curl -fsSL --retry 3 "$RAW_BASE/camera/$f" -o "$SELF_DIR/camera/$f" \
            || die "Could not download $f from $GITHUB_REPO."
        chmod +x "$SELF_DIR/camera/$f"
    done
    ok "Wizard helper files downloaded."
}

confirm_model() {
    say ""
    say "Look at the sticker on the camera box or camera."
    say "The article number must read exactly: ${BOLD}3215672.2${RESET}"
    say ""
    while true; do
        printf "Type the article number (or Q to quit): "
        read -r model
        if [[ "${model^^}" == "Q" ]]; then
            quit_cleanly
        elif [[ "$model" == "3215672.2" ]]; then
            ok "Correct camera model confirmed."
            return
        else
            warn "That is not 3215672.2. Please check the sticker and try again."
            say "This wizard must not be used on 3215672, 3215672.1 or another model."
        fi
    done
}

ask_camera_name() {
    say ""
    say "${BOLD}Give this camera a name${RESET}"
    say "This is useful if you install several cameras."
    say "The name is used for backup folders and as the camera's DHCP hostname."
    say "Example: ${BOLD}Front Door${RESET} becomes ${BOLD}front-door${RESET}."
    say ""

    local raw normalized
    while true; do
        printf "Camera name: "
        read -r raw
        [[ -n "${raw//[[:space:]]/}" ]] || { warn "The camera name cannot be empty."; continue; }

        normalized="$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//; s/-+/-/g' | cut -c1-63)"
        [[ -n "$normalized" ]] || { warn "Please use at least one letter or number in the camera name."; continue; }

        say "I will use: ${BOLD}$normalized${RESET}"
        if [[ -d "$BACKUP_DIR/$normalized" ]] && find "$BACKUP_DIR/$normalized" -mindepth 1 -maxdepth 1 -type d -print -quit 2>/dev/null | grep -q .; then
            warn "Backups already exist for a camera named '$normalized'."
            say "If this is a different camera, using a unique name will make the backups easier to identify."
            if ! ask_yes_no "Use '$normalized' anyway?" no; then
                continue
            fi
        fi
        if ask_yes_no "Is this name okay?" yes; then
            CAMERA_NAME="$normalized"
            CAMERA_HOSTNAME="$normalized"
            CAMERA_BACKUP_DIR="$BACKUP_DIR/$CAMERA_NAME"
            CAMERA_BUILD_DIR="$BUILD_DIR/$CAMERA_NAME"
            LATEST_BACKUP_FILE="$WORK_DIR/cameras/$CAMERA_NAME/latest_backup_path"
            mkdir -p "$CAMERA_BACKUP_DIR" "$CAMERA_BUILD_DIR" "$(dirname "$LATEST_BACKUP_FILE")"
            ok "Camera name saved as '$CAMERA_NAME'."
            return
        fi
    done
}
have() { command -v "$1" >/dev/null 2>&1; }

install_dependencies() {
    local missing=()
    local cmds=(curl git cmake make zig unsquashfs mksquashfs mkfs.vfat sfdisk lsblk findmnt expect telnet file)
    for c in "${cmds[@]}"; do have "$c" || missing+=("$c"); done
    if ((${#missing[@]} == 0)); then
        ok "All required tools are installed."
        return
    fi

    warn "Missing tools: ${missing[*]}"
    say "The wizard can try to install the required packages."
    if ! ask_yes_no "Install dependencies now?" yes; then
        say "The wizard cannot continue without these tools."
        quit_cleanly
    fi

    if have pacman; then
        sudo pacman -S --needed --noconfirm curl git cmake make zig squashfs-tools dosfstools util-linux expect inetutils file
    elif have apt-get; then
        sudo apt-get update
        # Package naming differs slightly between Debian/Ubuntu releases.
        sudo apt-get install -y curl git cmake make squashfs-tools dosfstools util-linux expect telnet file || \
        sudo apt-get install -y curl git cmake make squashfs-tools dosfstools util-linux expect inetutils-telnet file
        if ! have zig; then
            die "Zig is not available from your configured APT repositories. Install Zig, then run this wizard again."
        fi
    elif have dnf; then
        sudo dnf install -y curl git cmake make zig squashfs-tools dosfstools util-linux expect telnet file
    else
        die "Unsupported package manager. Install the missing tools manually: ${missing[*]}"
    fi

    for c in "${cmds[@]}"; do have "$c" || die "Required command '$c' is still missing."
    done
    ok "Dependencies installed."
}

update_sources() {
    info "Downloading/updating the two upstream projects..."
    if [[ -d "$SRC_DIR/toolkit/.git" ]]; then
        git -C "$SRC_DIR/toolkit" fetch --quiet origin
        git -C "$SRC_DIR/toolkit" reset --hard origin/main --quiet
    else
        rm -rf "$SRC_DIR/toolkit"
        git clone --depth 1 "$TOOLKIT_REPO" "$SRC_DIR/toolkit"
    fi

    if [[ -d "$SRC_DIR/firmware/.git" ]]; then
        git -C "$SRC_DIR/firmware" fetch --quiet origin
        git -C "$SRC_DIR/firmware" reset --hard origin/main --quiet
    else
        rm -rf "$SRC_DIR/firmware"
        git clone --depth 1 "$FIRMWARE_REPO" "$SRC_DIR/firmware"
    fi

    local required=(
        "$SRC_DIR/toolkit/sd_card/hack.sh"
        "$SRC_DIR/toolkit/sd_card/custom/scripts/entrypoint.sh"
        "$SRC_DIR/toolkit/sd_card/custom/configs/wifi.conf"
        "$SRC_DIR/firmware/src/ak_rtsp/Makefile"
        "$SRC_DIR/firmware/src/ak_rtsp/build_firmware.sh"
        "$SRC_DIR/firmware/src/ak_rtsp/arm_atomics.S"
        "$SRC_DIR/firmware/tools/firmware_patch_templates/ak_rtsp_wrapper.sh"
    )
    for f in "${required[@]}"; do [[ -f "$f" ]] || die "Upstream layout changed; missing: $f"; done
    ok "Upstream sources ready."
}

show_disks() {
    say ""
    say "Storage devices currently visible to Linux:"
    lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL,MOUNTPOINTS,MODEL | sed 's/^/  /'
    say ""
}

root_disk() {
    local rootsrc pk
    rootsrc="$(findmnt -no SOURCE / 2>/dev/null || true)"
    [[ -n "$rootsrc" ]] || return 0
    pk="$(lsblk -no PKNAME "$rootsrc" 2>/dev/null | head -n1 || true)"
    if [[ -n "$pk" ]]; then echo "/dev/$pk"; else echo "$rootsrc"; fi
}

collect_sd_candidates() {
    SD_CANDIDATES=()
    local rd d type bytes rm tran mounts
    rd="$(root_disk)"

    while read -r d type; do
        [[ "$type" == "disk" ]] || continue
        [[ "$d" != "$rd" ]] || continue
        bytes="$(lsblk -bdnro SIZE "$d" 2>/dev/null | head -n1 || echo 0)"
        [[ "${bytes:-0}" =~ ^[0-9]+$ ]] || bytes=0
        (( bytes >= 33554432 )) || continue

        rm="$(lsblk -dnro RM "$d" 2>/dev/null | head -n1 || echo 0)"
        tran="$(lsblk -dnro TRAN "$d" 2>/dev/null | head -n1 || true)"
        mounts="$(lsblk -nrpo MOUNTPOINTS "$d" 2>/dev/null | tr '\n' ' ')"

        if [[ "$rm" == "1" || "$tran" == "usb" || "$tran" == "mmc" || "$mounts" == *"/run/media/"* || "$mounts" == *"/media/"* ]]; then
            SD_CANDIDATES+=("$d")
        fi
    done < <(lsblk -dpno NAME,TYPE)
}

describe_disk() {
    local d="$1" size model mounts
    size="$(lsblk -dnro SIZE "$d" | xargs)"
    model="$(lsblk -dnro MODEL "$d" | xargs || true)"
    mounts="$(lsblk -nrpo MOUNTPOINTS "$d" 2>/dev/null | awk 'NF' | paste -sd ', ' -)"
    printf '%s — %s' "$size" "${model:-removable storage}"
    [[ -n "$mounts" ]] && printf ' — mounted at %s' "$mounts"
}

choose_sd_device() {
    say ""
    say "${BOLD}Insert the microSD card now${RESET}"
    say ""
    say "1. Put the microSD card in your computer or card reader."
    say "2. Wait a few seconds for Linux to detect it."
    say "3. If it appears in your file manager, open it once so it is mounted."
    say "   If it is blank or cannot be opened, that is okay; the wizard will format it."
    say "4. Come back to this terminal."
    say ""
    say "You will choose the card from a simple numbered list. You do NOT need to"
    say "understand Linux device names such as /dev/sdc or partitions such as /dev/sdc1."
    pause

    local i choice selected confirm
    while true; do
        collect_sd_candidates
        say ""
        say "${BOLD}Removable storage found:${RESET}"
        if ((${#SD_CANDIDATES[@]} == 0)); then
            warn "No removable SD card was detected."
            say "Make sure the card is inserted, then choose Rescan."
        else
            for i in "${!SD_CANDIDATES[@]}"; do
                printf "  %d) " "$((i+1))"
                describe_disk "${SD_CANDIDATES[$i]}"
                printf '\n'
            done
        fi
        say "  0) Rescan after inserting/remounting the SD card"
        say ""
        printf "Choose the microSD card by number: "
        read -r choice

        if [[ "$choice" == "0" ]]; then
            continue
        fi
        if ! [[ "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > ${#SD_CANDIDATES[@]} )); then
            warn "That is not one of the available options. Please choose a number from the list."
            continue
        fi

        selected="${SD_CANDIDATES[$((choice-1))]}"
        say ""
        say "Selected: ${BOLD}$(describe_disk "$selected")${RESET}"
        warn "The wizard will ERASE everything currently stored on this card."
        say ""
        say "  1) Yes, this is the correct microSD card — erase it and continue"
        say "  2) No, let me choose a different device"
        say "  0) Quit without erasing anything"
        ask_menu "Choose: " 0 2
        confirm="$REPLY"
        case "$confirm" in
            1) SD_DEV="$selected"; return ;;
            2) continue ;;
            0) quit_cleanly ;;
        esac
    done
}

partition_path() {
    if [[ "$1" =~ [0-9]$ ]]; then printf '%sp1' "$1"; else printf '%s1' "$1"; fi
}

format_sd() {
    info "Formatting the SD card as one MBR/FAT32 partition..."
    cleanup_mount
    sudo umount "${SD_DEV}"?* >/dev/null 2>&1 || true
    sudo wipefs -a "$SD_DEV" >/dev/null
    printf 'label: dos\n, , c, *\n' | sudo sfdisk "$SD_DEV" >/dev/null
    sudo partprobe "$SD_DEV" 2>/dev/null || true
    sudo udevadm settle 2>/dev/null || sleep 2
    SD_PART="$(partition_path "$SD_DEV")"
    [[ -b "$SD_PART" ]] || { sleep 2; [[ -b "$SD_PART" ]] || die "Partition $SD_PART did not appear."; }
    sudo mkfs.vfat -F 32 -n "$SD_LABEL" "$SD_PART" >/dev/null
    mount_sd
    ok "SD card formatted."
}

mount_sd() {
    cleanup_mount
    mkdir -p "$MOUNT_DIR"
    if [[ -z "${SD_PART:-}" || ! -b "${SD_PART:-/nonexistent}" ]]; then
        SD_PART="$(lsblk -rpno NAME,LABEL,TYPE | awk -v l="$SD_LABEL" '$2==l && $3=="part" {print $1; exit}')"
    fi
    [[ -n "${SD_PART:-}" && -b "$SD_PART" ]] || die "Could not find the $SD_LABEL SD partition."
    sudo mount -o uid="$(id -u)",gid="$(id -g)",umask=022 "$SD_PART" "$MOUNT_DIR"
}

wait_for_sd_return() {
    say ""
    while true; do
        say "Put the prepared SD card back into this computer."
        say "If it appears in your file manager, open/mount it once."
        pause
        for _ in {1..10}; do
            SD_PART="$(lsblk -rpno NAME,LABEL,TYPE | awk -v l="$SD_LABEL" '$2==l && $3=="part" {print $1; exit}')"
            if [[ -n "$SD_PART" && -b "$SD_PART" ]]; then
                mount_sd
                return 0
            fi
            sleep 1
        done
        warn "I cannot find the prepared SD card yet."
        say "Check that it is inserted, then try again."
        say "  1) Try again"
        say "  0) Quit for now"
        ask_menu "Choose: " 0 1
        [[ "$REPLY" == "1" ]] || quit_cleanly
    done
}
shell_quote() {
    # Produce a POSIX-shell-safe single-quoted value.
    printf "'%s'" "${1//\'/\'\\\'\'}"
}

ask_wifi() {
    say ""
    say "${BOLD}Wi-Fi setup${RESET}"
    say "The camera uses 2.4 GHz Wi-Fi."
    say "Your password is hidden while you type."

    while true; do
        printf "Wi-Fi SSID: "
        read -r WIFI_SSID
        [[ -n "${WIFI_SSID//[[:space:]]/}" ]] && break
        warn "The SSID cannot be empty. Please try again."
    done

    local first second
    while true; do
        printf "Wi-Fi password: "
        read -rs first
        printf '\n'
        if [[ -z "$first" ]]; then
            warn "The Wi-Fi password cannot be empty. Please try again."
            continue
        fi
        printf "Wi-Fi password again: "
        read -rs second
        printf '\n'
        if [[ "$first" != "$second" ]]; then
            warn "The two passwords did not match. Please enter them again."
            continue
        fi
        WIFI_PASS="$first"
        ok "Wi-Fi password confirmed."
        break
    done
}
prepare_stage1_sd() {
    info "Preparing the SD card for safe camera access and backup..."
    rm -rf "$MOUNT_DIR"/* "$MOUNT_DIR"/.[!.]* "$MOUNT_DIR"/..?* 2>/dev/null || true
    cp -a "$SRC_DIR/toolkit/sd_card/." "$MOUNT_DIR/"

    # Skip the toolkit's large filesystem copy. We create a complete raw MTD backup instead.
    mkdir -p "$MOUNT_DIR/custom/state" "$MOUNT_DIR/logs" "$MOUNT_DIR/original_firmware"
    : > "$MOUNT_DIR/custom/state/dump.done"
    rm -f "$MOUNT_DIR/custom/state/shadow.done"

    cat > "$MOUNT_DIR/custom/configs/wifi.conf" <<EOF_WIFI
# Generated by LSC 3215672.2 Decloud Wizard
MODE=sta
SSID=$(shell_quote "$WIFI_SSID")
PASS=$(shell_quote "$WIFI_PASS")
SECURITY=3
DHCP=1
EOF_WIFI

    sed -i -E 's/^TELNET=.*/TELNET=1/; s/^TELNET_PORT=.*/TELNET_PORT=24/; s/^OFFLINE=.*/OFFLINE=1/' "$MOUNT_DIR/custom/configs/hack.conf"

    cp "$SELF_DIR/camera/decloud_stage1.sh" "$MOUNT_DIR/custom/scripts/decloud_stage1.sh"
    cp "$SELF_DIR/camera/decloud_flash.sh" "$MOUNT_DIR/custom/scripts/decloud_flash.sh"
    chmod +x "$MOUNT_DIR/custom/scripts/decloud_stage1.sh" "$MOUNT_DIR/custom/scripts/decloud_flash.sh"

    # Make entrypoint idempotent: stock firmware may call it as well as our direct hook.
    if ! grep -q 'DECLOUD_ENTRYPOINT_LOCK' "$MOUNT_DIR/custom/scripts/entrypoint.sh"; then
        sed -i '2i\# DECLOUD_ENTRYPOINT_LOCK\nmkdir /tmp/decloud_entrypoint.lock 2>/dev/null || exit 0' "$MOUNT_DIR/custom/scripts/entrypoint.sh"
    fi

    # The direct hook is important after anyka_ipc is removed: it keeps Wi-Fi + telnet available.
    if ! grep -q 'DECLOUD_WIZARD_HOOK' "$MOUNT_DIR/hack.sh"; then
        cat >> "$MOUNT_DIR/hack.sh" <<'EOF_HOOK'

# DECLOUD_WIZARD_HOOK
# Start our services directly. entrypoint.sh has an atomic once-per-boot lock,
# so this remains safe while the stock anyka_ipc wrapper also exists.
/bin/sh "${SCRIPTS_DIR}/entrypoint.sh" >/dev/null 2>&1 &
/bin/sh "${SCRIPTS_DIR}/decloud_stage1.sh" >/dev/null 2>&1 &
EOF_HOOK
    fi

    sync
    ok "Stage 1 SD card is ready."
}

stage1_physical_instructions() {
    cleanup_mount
    say ""
    say "${BOLD}STAGE 1 — Back up the camera and save Wi-Fi permanently${RESET}"
    say ""
    say "1. Make sure the camera is unplugged."
    say "2. Remove the SD card from the computer and insert it into the camera."
    say "3. Connect USB-C power to the camera."
    say "4. Leave it powered on for ${BOLD}two full minutes${RESET}."
    say "   The blue LED may keep blinking during this step; that is normal."
    say "   The factory voice prompt is intentionally muted by the wizard, so"
    say "   you will normally ${BOLD}not${RESET} hear the Chinese startup message."
    say "5. After two minutes, unplug USB-C power."
    say "6. Remove the SD card and put it back into this computer."
    wait_for_sd_return
}

verify_stage1() {
    info "Checking the camera backup..."
    if [[ ! -f "$MOUNT_DIR/STAGE1_SUCCESS" ]]; then
        warn "Stage 1 did not finish successfully."
        if [[ -f "$MOUNT_DIR/logs/decloud_stage1.log" ]]; then
            say ""
            say "The camera reported:"
            say "------------------"
            tail -n 80 "$MOUNT_DIR/logs/decloud_stage1.log"
            say "------------------"
        fi
        return 1
    fi

    local sizes=(204800 4096 4096 65536 1572864 1032192 262144 5242880)
    for i in {0..7}; do
        local f="$MOUNT_DIR/original_firmware/mtdblock${i}.bin"
        [[ -f "$f" ]] || die "Backup file missing: $f"
        local got
        got="$(stat -c%s "$f")"
        [[ "$got" -eq "${sizes[$i]}" ]] || die "Wrong size for mtdblock${i}.bin: $got"
    done

    local stamp backup_target
    stamp="$(date +%Y%m%d_%H%M%S)"
    backup_target="$CAMERA_BACKUP_DIR/$stamp"
    mkdir -p "$backup_target"
    cp -a "$MOUNT_DIR/original_firmware/." "$backup_target/"
    printf '%s\n' "$backup_target" > "$LATEST_BACKUP_FILE"
    ok "Full 8 MiB stock backup verified and copied to: $backup_target"

    if [[ -f "$MOUNT_DIR/STAGE1_STATUS" ]]; then
        say ""
        say "Camera information:"
        sed 's/^/  /' "$MOUNT_DIR/STAGE1_STATUS"
        CAMERA_IP="$(awk -F= '$1=="IP" {print $2}' "$MOUNT_DIR/STAGE1_STATUS" | tail -n1)"
    fi
}

run_stage1_until_success() {
    while true; do
        prepare_stage1_sd
        stage1_physical_instructions
        if verify_stage1; then
            return 0
        fi

        say ""
        say "Nothing has been flashed. You can safely try again."
        say "A wrong Wi-Fi SSID/password is the most common reason for this step to fail."
        say ""
        say "  1) Enter the Wi-Fi details again and retry"
        say "  2) Retry with the same Wi-Fi details"
        say "  0) Quit for now"
        ask_menu "Choose: " 0 2
        case "$REPLY" in
            1) ask_wifi ;;
            2) ;;
            0) quit_cleanly ;;
        esac
        # The card is still mounted after verification, so prepare_stage1_sd can
        # rebuild it immediately for the next attempt.
    done
}

patch_native_linux_build() {
    local akdir="$SRC_DIR/firmware/src/ak_rtsp"
    cat > "$akdir/gen_version.sh" <<'EOF_VERSION'
#!/usr/bin/env bash
set -e
BUILD_NUM_FILE="build_number.txt"
if [[ -f "$BUILD_NUM_FILE" ]]; then num=$(cat "$BUILD_NUM_FILE"); else num=0; fi
num=$((num + 1))
echo "$num" > "$BUILD_NUM_FILE"
git_hash=$(git describe --always --dirty=-dirty 2>/dev/null || echo unknown)
timestamp=$(date '+%Y-%m-%d %H:%M:%S')
cat > version_info.h <<EOF2
#pragma once
#define BUILD_NUMBER $num
#define BUILD_TIMESTAMP "$timestamp"
#define GIT_HASH "$git_hash"
EOF2
EOF_VERSION
    chmod +x "$akdir/gen_version.sh"
    sed -i 's|pwsh -NoProfile -NonInteractive -File gen_version.ps1|./gen_version.sh|' "$akdir/Makefile"

    # Give each camera a useful DHCP hostname (for example front-door).
    # CAMERA_HOSTNAME is strictly sanitized by ask_camera_name().
    local wrapper="$SRC_DIR/firmware/tools/firmware_patch_templates/ak_rtsp_wrapper.sh"
    sed -i -E "s/hostname:[A-Za-z0-9._-]+/hostname:${CAMERA_HOSTNAME}/" "$wrapper"
}


build_firmware() {
    info "Building the cloud-free RTSP firmware from YOUR camera backup..."
    local backup_path akdir smol app_extract outdir
    backup_path="$(cat "$LATEST_BACKUP_FILE")"
    akdir="$SRC_DIR/firmware/src/ak_rtsp"
    smol="$SRC_DIR/firmware/src/smolrtsp"
    app_extract="$CAMERA_BUILD_DIR/app_extracted"
    outdir="$CAMERA_BUILD_DIR/output"

    if [[ ! -d "$smol/.git" ]]; then
        rm -rf "$smol"
        git clone --depth 1 "$SMOLRTSP_REPO" "$smol"
    fi
    cmake -S "$smol" -B "$smol/build" >/dev/null

    patch_native_linux_build
    find "$akdir" "$smol" -name '*.o' -delete 2>/dev/null || true
    rm -f "$akdir/ak_rtsp" "$akdir/flash_tool"

    make -C "$akdir" ak_rtsp flash_tool 'CC=zig cc -target arm-linux-musleabi -mcpu=arm926ej_s' \
        || die "Cross-compilation failed. See the compiler output above."

    file "$akdir/ak_rtsp" | grep -q 'ARM' || die "ak_rtsp is not an ARM executable."
    file "$akdir/ak_rtsp" | grep -q 'statically linked' || die "ak_rtsp is not statically linked."
    file "$akdir/flash_tool" | grep -q 'ARM' || die "flash_tool is not an ARM executable."
    file "$akdir/flash_tool" | grep -q 'statically linked' || die "flash_tool is not statically linked."

    rm -rf "$app_extract" "$outdir"
    mkdir -p "$app_extract" "$outdir"
    unsquashfs -d "$app_extract" "$backup_path/mtdblock7.bin" >/dev/null \
        || die "Could not unpack the stock APP partition."

    APP_EXTRACTED="$app_extract" FW_DIR="$outdir" bash "$akdir/build_firmware.sh" \
        || die "Firmware packaging failed."

    local fw
    fw="$(find "$outdir" -maxdepth 1 -type f -name 'ak_rtsp_firmware_*.squashfs' | sort | tail -n1)"
    [[ -n "$fw" && -f "$fw" ]] || die "No firmware image was produced."
    [[ "$(stat -c%s "$fw")" -eq "$EXPECTED_APP_SIZE" ]] || die "Firmware image has the wrong size."

    mkdir -p "$MOUNT_DIR/custom_firmware"
    rm -f "$MOUNT_DIR/custom_firmware/ak_rtsp_firmware_"*.squashfs
    cp "$fw" "$MOUNT_DIR/custom_firmware/"
    cp "$akdir/flash_tool" "$MOUNT_DIR/flash_tool"
    chmod +x "$MOUNT_DIR/flash_tool"
    sync

    FIRMWARE_NAME="$(basename "$fw")"
    ok "Firmware built and verified: $FIRMWARE_NAME"
}

stage2_physical_instructions() {
    cleanup_mount
    say ""
    say "${BOLD}STAGE 2 — Flash the cloud-free firmware${RESET}"
    say ""
    say "1. Make sure the camera is unplugged."
    say "2. Insert the prepared SD card into the camera."
    say "3. Connect USB-C power."
    say "4. Wait about 45 seconds for the camera to join Wi-Fi."
    say ""
    say "The wizard will connect to the camera on the special local service port"
    say "and show the complete flash/verification output on this screen."
    pause
}

check_tcp() {
    local host="$1" port="$2"
    timeout 2 bash -c "</dev/tcp/$host/$port" >/dev/null 2>&1
}

ask_camera_ip() {
    local default_ip="${CAMERA_IP:-}"
    while true; do
        if [[ -n "$default_ip" ]]; then
            printf "Camera IP [%s]: " "$default_ip"
            read -r ip
            ip="${ip:-$default_ip}"
        else
            printf "Camera IP (check your router's DHCP/client list): "
            read -r ip
        fi
        if [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] && check_tcp "$ip" 24; then
            CAMERA_IP="$ip"
            ok "Camera found at $CAMERA_IP; maintenance port 24 is open."
            return
        fi
        warn "I cannot reach port 24 at '$ip'. Check the IP in your router and try again."
        default_ip=""
    done
}

flash_over_telnet() {
    say ""
    warn "The next step writes the APP partition. Do not unplug the camera while flashing."
    say "The script verifies the exact partition layout and checks that the camera's"
    say "current APP partition matches the stock backup before it writes anything."
    say ""
    say "  1) Flash the verified custom firmware now"
    say "  2) Not yet — show this confirmation again"
    say "  0) Quit without flashing"
    while true; do
        ask_menu "Choose: " 0 2
        confirm="$REPLY"
        case "$confirm" in
            1) break ;;
            2)
                say "Nothing has been written yet. When you are ready:"
                say "  1) Flash the verified custom firmware now"
                say "  2) Not yet"
                say "  0) Quit without flashing"
                ;;
            0) quit_cleanly ;;
        esac
    done

    info "Connecting to $CAMERA_IP and flashing. This can take a minute..."
    export CAMERA_IP
    set +e
    expect <<'EOF_EXPECT'
set timeout 300
log_user 1
spawn telnet $env(CAMERA_IP) 24
expect {
    -re {Connected|Escape character|[#\$] ?$} {}
    timeout { puts "\nERROR: Telnet connection timed out."; exit 10 }
    eof { puts "\nERROR: Telnet connection closed."; exit 11 }
}
after 1000
send -- "sh /tmp/sd/custom/scripts/decloud_flash.sh\r"
expect {
    "DECLOUD_FLASH_SUCCESS" { puts "\nWizard detected successful flash + verification."; send -- "exit\r"; exit 0 }
    "DECLOUD_RESTORE_SUCCESS" { puts "\nCustom flash failed, but stock APP was restored successfully. DO NOT continue as if flashed."; send -- "exit\r"; exit 20 }
    "DECLOUD_FLASH_FAILED" { puts "\nFlash/verification failed. Keep the camera powered and review the output."; exit 21 }
    timeout { puts "\nERROR: Timed out waiting for flash verification. KEEP CAMERA POWERED."; exit 22 }
    eof { puts "\nERROR: Connection closed before success was confirmed. KEEP CAMERA POWERED."; exit 23 }
}
EOF_EXPECT
    local rc=$?
    set -e
    case "$rc" in
        0) ok "Flash and per-block verification completed successfully." ;;
        20) die "Stock APP was restored. Camera is safe, but custom firmware was not installed." ;;
        *) die "Flashing was not confirmed successful. KEEP THE CAMERA POWERED until you understand the failure." ;;
    esac
}

final_boot() {
    say ""
    say "${BOLD}FINAL BOOT${RESET}"
    say ""
    say "1. Unplug USB-C power now."
    say "2. Remove the SD card from the camera."
    say "3. Wait 5 seconds."
    say "4. Plug USB-C power back in WITHOUT the SD card."
    say "5. Wait about 45 seconds."
    pause

    local ip="$CAMERA_IP"
    if check_tcp "$ip" 554; then
        ok "RTSP port 554 is reachable at $ip."
    else
        warn "RTSP was not found at $ip. DHCP may have assigned a different address."
        printf "Enter the camera's current IP from your router (or press Enter to skip): "
        read -r newip
        if [[ -n "$newip" ]] && check_tcp "$newip" 554; then
            CAMERA_IP="$newip"
            ok "RTSP port 554 is reachable at $CAMERA_IP."
        else
            warn "I could not automatically verify RTSP. The flash itself was verified successfully."
        fi
    fi

    say ""
    say "${GREEN}${BOLD}Done.${RESET} Camera ${BOLD}$CAMERA_NAME${RESET} is now running ak_rtsp instead of the Tuya anyka_ipc APP."
    say ""
    say "Camera name: ${BOLD}$CAMERA_NAME${RESET}"
    say "DHCP hostname: ${BOLD}$CAMERA_HOSTNAME${RESET}"
    say "RTSP URL: ${BOLD}rtsp://${CAMERA_IP}:554/${RESET}"
    say "Alternative path: rtsp://${CAMERA_IP}:554/main_ch"
    say ""
    say "Recommended next steps:"
    say "  • Create a DHCP reservation for the camera in your router."
    say "  • Put the camera in an isolated camera/IoT VLAN if you use one."
    say "  • After you are happy with the result, reformat the SD card: it still"
    say "    contains your Wi-Fi credentials and your private stock firmware backup."
    say "  • Keep the backup stored at: $(cat "$LATEST_BACKUP_FILE")"
}

main() {
    banner

    section 1 8 "Camera identification"
    confirm_model
    ask_camera_name

    section 2 8 "Computer checks"
    install_dependencies
    ensure_wizard_assets
    update_sources

    section 3 8 "Wi-Fi setup"
    ask_wifi

    section 4 8 "Prepare the microSD card"
    choose_sd_device
    format_sd

    section 5 8 "Back up the camera & save Wi-Fi"
    run_stage1_until_success

    section 6 8 "Build the cloud-free firmware"
    build_firmware

    section 7 8 "Flash & verify"
    stage2_physical_instructions
    ask_camera_ip
    flash_over_telnet

    section 8 8 "Final boot & RTSP check"
    final_boot
}

case "${1:-}" in
    --version|-V)
        echo "LSC 3215672.2 Decloud Wizard v$VERSION"
        exit 0
        ;;
    --help|-h)
        cat <<EOF_HELP
LSC 3215672.2 Decloud Wizard v$VERSION

Run without arguments to start the interactive installer.

Options:
  -h, --help       Show this help
  -V, --version    Show version

Supported camera: Action LSC Smart Connect 3215672.2 / SI B26101 only.
EOF_HELP
        exit 0
        ;;
esac

main "$@"
