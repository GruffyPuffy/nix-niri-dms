#!/usr/bin/env bash
set -Eeuo pipefail

REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SESSION_WRAPPER_SRC="$REPO_DIR/scripts/niri-nix-session"
SESSION_DESKTOP_SRC="$REPO_DIR/scripts/niri-nix.desktop"
LOCK_WRAPPER_SRC="$REPO_DIR/scripts/lock.sh"
LOCK_SPLASH_SRC="$REPO_DIR/scripts/lock-splash/shell.qml"
SESSION_WRAPPER_DST="/usr/local/bin/niri-nix-session"
SESSION_DESKTOP_DST="/usr/share/wayland-sessions/niri-nix.desktop"
LOCK_WRAPPER_DST="/usr/local/bin/niri-gdm-lock"
LOCK_SPLASH_DST="/usr/local/share/niri-nix-dms/lock-splash/shell.qml"

APT_PACKAGES=(
  ca-certificates
  curl
  dbus-user-session
  stow
)

NIX_PACKAGES=(
  nixpkgs#cliphist
  nixpkgs#dgop
  nixpkgs#dms-shell
  nixpkgs#fuzzel
  github:nix-community/nixGL#nixGLIntel
  nixpkgs#kitty
  nixpkgs#mako
  nixpkgs#niri
  nixpkgs#polkit_gnome
  nixpkgs#quickshell
  nixpkgs#swww
  nixpkgs#thunar
  nixpkgs#waybar
  nixpkgs#wl-clipboard
  nixpkgs#xdg-desktop-portal-gnome
  nixpkgs#xdg-utils
  nixpkgs#xwayland-satellite
)

BROWSER_LABELS=()
BROWSER_COMMANDS=()

ASSUME_YES=0
DRY_RUN=0

usage() {
  cat <<'USAGE'
Usage: ./install.sh [--yes] [--dry-run]

Installs a Niri + DMS Wayland session on Ubuntu 24.04 using Nix packages.

Options:
  -y, --yes      Answer yes to installer prompts.
      --dry-run  Print the actions without changing the system.
  -h, --help     Show this help.
USAGE
}

log() {
  printf '\n==> %s\n' "$*"
}

warn() {
  printf 'Warning: %s\n' "$*" >&2
}

die() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

confirm() {
  local prompt="$1"
  local default="${2:-y}"
  local reply suffix

  if [ "$ASSUME_YES" -eq 1 ]; then
    printf '%s yes\n' "$prompt"
    return 0
  fi

  if [ "$default" = "y" ]; then
    suffix="[Y/n]"
  else
    suffix="[y/N]"
  fi

  read -r -p "$prompt $suffix " reply
  reply="${reply,,}"

  if [ -z "$reply" ]; then
    reply="$default"
  fi

  [[ "$reply" == "y" || "$reply" == "yes" ]]
}

run() {
  printf '+'
  printf ' %q' "$@"
  printf '\n'

  if [ "$DRY_RUN" -eq 0 ]; then
    "$@"
  fi
}

have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

add_browser_option() {
  local label="$1"
  local command_line="$2"
  local command_name="${command_line%% *}"

  if have_cmd "$command_name"; then
    BROWSER_LABELS+=("$label")
    BROWSER_COMMANDS+=("$command_line")
  fi
}

discover_browsers() {
  BROWSER_LABELS=()
  BROWSER_COMMANDS=()

  add_browser_option "Chrome" "google-chrome-stable"
  add_browser_option "Chrome" "google-chrome"
  add_browser_option "Chromium" "chromium-browser"
  add_browser_option "Chromium" "chromium"
  add_browser_option "Firefox" "firefox"
  add_browser_option "Vivaldi" "vivaldi-stable --password-store=gnome-libsecret"
  add_browser_option "Vivaldi" "vivaldi --password-store=gnome-libsecret"
  add_browser_option "Vivaldi (snap)" "vivaldi.vivaldi-stable --password-store=gnome-libsecret"
  add_browser_option "Brave" "brave-browser"
  add_browser_option "Microsoft Edge" "microsoft-edge"
  add_browser_option "LibreWolf" "librewolf"
  add_browser_option "Zen" "zen-browser"
  add_browser_option "Zen" "zen"
  add_browser_option "Floorp" "floorp"
}

load_nix_environment() {
  local profile

  for profile in \
    "$HOME/.nix-profile/etc/profile.d/nix.sh" \
    "/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh" \
    "/nix/var/nix/profiles/default/etc/profile.d/nix.sh"; do
    if [ -r "$profile" ]; then
      # shellcheck disable=SC1090
      . "$profile"
    fi
  done

  export PATH="$HOME/.nix-profile/bin:$HOME/.local/state/nix/profile/bin:/nix/var/nix/profiles/default/bin:$PATH"
}

require_ubuntu_24() {
  if [ ! -r /etc/os-release ]; then
    warn "Could not read /etc/os-release; continuing anyway."
    return
  fi

  # shellcheck disable=SC1091
  . /etc/os-release

  if [ "${ID:-}" != "ubuntu" ]; then
    warn "This installer is written for Ubuntu 24.04; detected ${PRETTY_NAME:-unknown OS}."
  elif [[ "${VERSION_ID:-}" != 24.* ]]; then
    warn "This installer is written for Ubuntu 24.04; detected ${PRETTY_NAME:-Ubuntu}."
  fi
}

select_stow_packages() {
  local packages=()

  if [ -d "$REPO_DIR/niri" ]; then
    packages+=("niri")
  elif [ -d "$REPO_DIR/niri_configs" ]; then
    packages+=("niri_configs")
  fi

  if [ -d "$REPO_DIR/kitty" ]; then
    packages+=("kitty")
  elif [ -d "$REPO_DIR/kitty_configs" ]; then
    packages+=("kitty_configs")
  fi

  if [ "${#packages[@]}" -eq 0 ]; then
    die "Could not find stow packages named 'niri', 'niri_configs', 'kitty', or 'kitty_configs' in $REPO_DIR."
  fi

  printf '%s\n' "${packages[@]}"
}

install_apt_packages() {
  if ! have_cmd apt-get; then
    die "apt-get was not found. This script expects Ubuntu or another apt-based system."
  fi

  log "Installing Ubuntu packages"
  run sudo apt-get update
  run sudo apt-get install -y "${APT_PACKAGES[@]}"
}

install_nix_daemon() {
  if have_cmd nix; then
    log "Nix is already installed"
    return
  fi

  log "Installing Nix daemon"
  if [ "$DRY_RUN" -eq 1 ]; then
    printf '+ sh <(curl -L https://nixos.org/nix/install) --daemon\n'
    return
  fi

  sh <(curl -L https://nixos.org/nix/install) --daemon
  load_nix_environment
}

enable_nix_experimental_features() {
  local nix_conf="$HOME/.config/nix/nix.conf"
  local existing_features
  local merged_features

  log "Enabling Nix experimental features"

  if [ "$DRY_RUN" -eq 1 ]; then
    printf '+ mkdir -p %q\n' "$(dirname "$nix_conf")"
    printf '+ touch %q\n' "$nix_conf"
    printf '+ update %q with: experimental-features = nix-command flakes\n' "$nix_conf"
    printf '+ nix config show | grep experimental-features\n'
    return
  fi

  mkdir -p "$(dirname "$nix_conf")"
  touch "$nix_conf"

  if grep -Eq '^[[:space:]]*experimental-features[[:space:]]*=' "$nix_conf"; then
    existing_features="$(
      sed -nE 's/^[[:space:]]*experimental-features[[:space:]]*=[[:space:]]*(.*)$/\1/p' "$nix_conf" |
        tail -n 1
    )"
    merged_features="$(
      printf '%s\n%s\n' "$existing_features" "nix-command flakes" |
        tr ' ' '\n' |
        sed '/^$/d' |
        awk '!seen[$0]++' |
        tr '\n' ' ' |
        sed 's/[[:space:]]*$//'
    )"
    sed -i -E "0,/^[[:space:]]*experimental-features[[:space:]]*=.*/s//experimental-features = $merged_features/" "$nix_conf"
  else
    printf '\nexperimental-features = nix-command flakes\n' >> "$nix_conf"
  fi

  if have_cmd nix; then
    nix config show | grep experimental-features || true
  fi
}

install_nix_packages() {
  load_nix_environment

  if [ "$DRY_RUN" -eq 0 ] && ! have_cmd nix; then
    die "nix is not available. Open a new shell after Nix installation, then rerun this script."
  fi

  log "Installing Nix profile packages"
  run nix --extra-experimental-features "nix-command flakes" profile add "${NIX_PACKAGES[@]}"
}

remove_legacy_nixgl_default() {
  local profile_json

  if [ "$DRY_RUN" -eq 1 ]; then
    printf '+ check Nix profile for legacy github:nix-community/nixGL#default entry\n'
    printf '+ remove legacy nixGL default entry if present: nix profile remove nixGL\n'
    return
  fi

  profile_json="$(NO_COLOR=1 nix --extra-experimental-features "nix-command flakes" profile list --json)"

  if ! printf '%s' "$profile_json" | grep -Eq '"nixGL":\{[^}]*"attrPath":"packages\.[^"]+\.default"'; then
    return
  fi

  warn "Removing legacy nixGL default profile entry. This installer uses nixGLIntel instead."
  run nix --extra-experimental-features "nix-command flakes" profile remove nixGL
}

update_nix_profile_packages() {
  load_nix_environment

  if [ "$DRY_RUN" -eq 0 ] && ! have_cmd nix; then
    die "nix is not available. Open a new shell after Nix installation, then rerun this script."
  fi

  remove_legacy_nixgl_default

  log "Updating all Nix profile packages"
  run nix --extra-experimental-features "nix-command flakes" profile upgrade --all
}

configure_mod_w_browser() {
  local binds_file="$REPO_DIR/niri_configs/.config/niri/dms/binds.kdl"
  local choice label command_line escaped_label escaped_command

  [ -f "$binds_file" ] || die "Missing $binds_file"

  log "Searching for browsers"
  discover_browsers

  if [ "${#BROWSER_COMMANDS[@]}" -eq 0 ]; then
    warn "No known browser commands were found in PATH. Keeping the current Mod+W binding."
    return
  fi

  printf 'Found browsers:\n'
  for choice in "${!BROWSER_COMMANDS[@]}"; do
    printf '  %d) %s (%s)\n' "$((choice + 1))" "${BROWSER_LABELS[$choice]}" "${BROWSER_COMMANDS[$choice]}"
  done

  if [ "$ASSUME_YES" -eq 1 ]; then
    warn "--yes is enabled, so browser selection is skipped. Keeping the current Mod+W binding."
    return
  fi

  if ! read -r -p "Select browser for Mod+W, or press Enter to keep current: " choice; then
    warn "No browser selection received. Keeping the current Mod+W binding."
    return
  fi

  if [ -z "$choice" ]; then
    log "Keeping current Mod+W browser binding"
    return
  fi

  if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt "${#BROWSER_COMMANDS[@]}" ]; then
    warn "Invalid browser selection. Keeping the current Mod+W binding."
    return
  fi

  label="${BROWSER_LABELS[$((choice - 1))]}"
  command_line="${BROWSER_COMMANDS[$((choice - 1))]}"

  log "Setting Mod+W browser to $label"

  if [ "$DRY_RUN" -eq 1 ]; then
    printf '+ update %q Mod+W binding to: %s\n' "$binds_file" "$command_line"
    return
  fi

  escaped_label="${label//\\/\\\\}"
  escaped_label="${escaped_label//&/\\&}"
  escaped_command="${command_line//\\/\\\\}"
  escaped_command="${escaped_command//&/\\&}"

  sed -i -E \
    "s|^[[:space:]]*Mod\\+W hotkey-overlay-title=.*$|    Mod+W hotkey-overlay-title=\"Open $escaped_label\" { spawn-sh \"$escaped_command\"; }|" \
    "$binds_file"
}

path_points_to_package() {
  local path="$1"
  local package="$2"
  local package_name="${package%_configs}"
  local expected="$REPO_DIR/$package/.config/$package_name"
  local resolved
  local expected_resolved

  if [ ! -L "$path" ]; then
    return 1
  fi

  resolved="$(readlink -f "$path" 2>/dev/null || true)"
  expected_resolved="$(readlink -f "$expected" 2>/dev/null || true)"
  [ -n "$resolved" ] && [ -n "$expected_resolved" ] && [ "$resolved" = "$expected_resolved" ]
}

stow_configs() {
  local package package_name config_dir
  local backup_path
  local packages=()
  mapfile -t packages < <(select_stow_packages)

  if [ "$DRY_RUN" -eq 0 ] && ! have_cmd stow; then
    die "stow is not available. Install apt packages first or run: sudo apt-get install stow"
  fi

  log "Stowing configs into $HOME"
  run mkdir -p "$HOME/.config"

  for package in "${packages[@]}"; do
    package_name="${package%_configs}"
    config_dir="$HOME/.config/$package_name"

    if { [ -e "$config_dir" ] || [ -L "$config_dir" ]; } && ! path_points_to_package "$config_dir" "$package"; then
      if [ -L "$config_dir" ]; then
        warn "$config_dir is a symlink to $(readlink "$config_dir"), not this repo."
      else
        warn "$config_dir already exists and is not a symlink."
      fi
      backup_path="$config_dir.backup.$(date +%Y%m%d-%H%M%S)"

      if confirm "Back up existing ${config_dir#$HOME/} to ${backup_path#$HOME/}?"; then
        run mv "$config_dir" "$backup_path"
      else
        warn "Skipping $package because the existing config would conflict with GNU Stow."
        continue
      fi
    fi

    run stow --dir "$REPO_DIR" --target "$HOME" "$package"
  done
}

install_session_files() {
  [ -f "$SESSION_WRAPPER_SRC" ] || die "Missing $SESSION_WRAPPER_SRC"
  [ -f "$SESSION_DESKTOP_SRC" ] || die "Missing $SESSION_DESKTOP_SRC"
  [ -f "$LOCK_WRAPPER_SRC" ] || die "Missing $LOCK_WRAPPER_SRC"
  [ -f "$LOCK_SPLASH_SRC" ] || die "Missing $LOCK_SPLASH_SRC"

  log "Installing Niri session files and lock helper"
  run sudo install -Dm755 "$SESSION_WRAPPER_SRC" "$SESSION_WRAPPER_DST"
  run sudo install -Dm644 "$SESSION_DESKTOP_SRC" "$SESSION_DESKTOP_DST"
  run sudo install -Dm755 "$LOCK_WRAPPER_SRC" "$LOCK_WRAPPER_DST"
  run sudo install -Dm644 "$LOCK_SPLASH_SRC" "$LOCK_SPLASH_DST"
}

print_done() {
  cat <<EOF

Done.

Log out, choose "Niri (Nix)" from your display manager's session menu, then log in.
If Nix was installed for the first time, rebooting once is the simplest way to make sure
the daemon and profile environment are available everywhere.

Installed session files:
  $SESSION_WRAPPER_DST
  $SESSION_DESKTOP_DST
  $LOCK_WRAPPER_DST
EOF
}

print_intro() {
  cat <<'INTRO'
Niri + DMS installer for Ubuntu 24.04 using nixpkgs.

This can:
  - install Ubuntu packages: ca-certificates, curl, dbus-user-session, stow
  - install the Nix daemon if nix is missing
  - enable Nix experimental features: nix-command, flakes
  - install Niri, DMS, and supporting tools into your Nix profile
  - update all packages in your Nix profile
  - optionally select a detected browser for Mod+W
  - stow the repo's Niri and Kitty configs into ~/.config
  - install the display-manager session files and GDM lock helper
INTRO
}

run_all() {
  install_apt_packages
  install_nix_daemon
  enable_nix_experimental_features
  install_nix_packages
  configure_mod_w_browser
  stow_configs
  install_session_files
}

print_menu() {
  cat <<'MENU'

Select an action:
  1) Re/install all
  2) Install/update Ubuntu packages
  3) Install Nix daemon if missing
  4) Enable Nix experimental features
  5) Install/update Nix profile packages
  6) Update all Nix profile packages
  7) Search browsers and set Mod+W
  8) Stow Niri and Kitty configs
  9) Install session files and lock helper
  q) Quit
MENU
}

run_menu() {
  local choice

  while true; do
    print_menu
    read -r -p "Choice: " choice

    case "$choice" in
      1)
        run_all
        print_done
        return
        ;;
      2)
        install_apt_packages
        ;;
      3)
        install_nix_daemon
        ;;
      4)
        enable_nix_experimental_features
        ;;
      5)
        install_nix_packages
        ;;
      6)
        update_nix_profile_packages
        ;;
      7)
        configure_mod_w_browser
        ;;
      8)
        stow_configs
        ;;
      9)
        install_session_files
        ;;
      q|Q|"")
        return
        ;;
      *)
        warn "Unknown menu choice: $choice"
        ;;
    esac
  done
}

main() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      -y|--yes)
        ASSUME_YES=1
        ;;
      --dry-run)
        DRY_RUN=1
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die "Unknown option: $1"
        ;;
    esac
    shift
  done

  if [ "${EUID:-$(id -u)}" -eq 0 ]; then
    die "Run this as your normal user, not root. The script will use sudo when needed."
  fi

  require_ubuntu_24

  print_intro

  if [ "$ASSUME_YES" -eq 1 ]; then
    run_all
    print_done
    return
  fi

  run_menu
}

main "$@"
