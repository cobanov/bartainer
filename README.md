# Bartainer

**A tidy macOS menu bar for your Docker containers.**

Bartainer keeps local and remote Docker containers close without opening a terminal. Click the menu bar icon, scan the table, copy what you need, and get back to work.

## Download

Install with Homebrew:

```sh
brew install --cask cobanov/tap/bartainer
```

Or download the latest macOS build from **[GitHub Releases](https://github.com/cobanov/bartainer/releases/latest)**:

1. Download `Bartainer-*-macos.zip`.
2. Unzip it.
3. Move `Bartainer.app` to your **Applications** folder.
4. Open Bartainer.

If macOS says the app cannot be opened because it was downloaded from the internet, right-click `Bartainer.app`, choose **Open**, then confirm once.

## What it does

- Shows Docker containers from your Mac in the menu bar.
- Supports remote Docker hosts over SSH.
- Groups containers by host.
- Shows ID, name, image tag, state, status, and ports.
- Click a cell to copy its full value.

## Pricing

Bartainer is free for local containers and one remote host.

**Bartainer Pro** is a one-time **$2** purchase that unlocks more remote hosts. Open **Settings → Pro** in the app to activate a license.

## Requirements

- macOS 13 or newer
- Docker CLI
- SSH access for remote hosts (optional)

## Remote hosts

In the app, open **Settings → Hosts** and add a remote host. For the smoothest setup, use SSH keys so this works without a password prompt:

```sh
ssh user@host docker ps
```

Password-based SSH is optional; passwords are stored in the macOS Keychain.

## Local Docker

Make sure Docker Desktop (or your Docker runtime) is running before opening Bartainer from the menu bar.
