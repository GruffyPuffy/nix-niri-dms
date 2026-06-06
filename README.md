# Niri + DMS on Ubuntu 24.04 with Nix

This repo installs a Niri Wayland session with DMS on Ubuntu 24.04, using Nix for the desktop stack and GNU Stow for user configuration.

It includes:

- `install.sh`: interactive installer.
- `niri_configs/`: stow package for `~/.config/niri`.
- `kitty_configs/`: stow package for `~/.config/kitty`.
- `scripts/niri-nix-session`: session wrapper launched by the display manager.
- `scripts/niri-nix.desktop`: Wayland session entry.

## What It Installs

Ubuntu packages:

```bash
ca-certificates curl dbus-user-session swaylock stow
```

Nix profile packages:

```bash
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
```

The installer also enables these Nix experimental features in `~/.config/nix/nix.conf`:

```ini
experimental-features = nix-command flakes
```

This repo uses `nixGLIntel` for Intel/Mesa graphics and intentionally avoids the nixGL NVIDIA/default auto-detection path.

## Install

Run as your normal user, not root:

```bash
./install.sh
```

To preview actions without changing the system:

```bash
./install.sh --dry-run
```

To accept yes/no prompts automatically:

```bash
./install.sh --yes
```

`--yes` does not choose a browser for you. Browser selection is intentionally skipped so the current `Mod+W` binding is not changed by accident.

## Browser Binding

The installer can search for installed browsers and update the Niri `Mod+W` binding.

It looks for common browser commands such as Firefox, Chrome, Chromium, Vivaldi, Brave, Edge, LibreWolf, Zen, and Floorp. Only commands found in `PATH` are shown.

The binding edited is in:

```bash
niri_configs/.config/niri/dms/binds.kdl
```

## Config Stowing

The installer stows these config packages into `$HOME`:

```bash
niri_configs
kitty_configs
```

That creates links such as:

```bash
~/.config/niri
~/.config/kitty
```

If an existing config directory is found and it is not already a symlink, the installer offers to back it up before running Stow.

## Session Files

The installer copies:

```bash
scripts/niri-nix-session -> /usr/local/bin/niri-nix-session
scripts/niri-nix.desktop -> /usr/share/wayland-sessions/niri-nix.desktop
```

After installation, log out and choose `Niri (Nix)` from your display manager.

If Nix was installed for the first time, rebooting once is the simplest way to make sure the daemon and profile environment are available everywhere.

## Notes

- This installer targets Ubuntu 24.04.
- The Niri session is launched through `nixGLIntel`.
- The session wrapper sources `~/.profile` and then adds common Nix profile paths to `PATH`.
