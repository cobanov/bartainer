# Bartainer

Bartainer is a small macOS menu bar app for keeping an eye on Docker containers across your Mac and remote machines.

It is inspired by the clean terminal table style of [`better-docker-ps`](https://github.com/Mikescher/better-docker-ps), but lives quietly in the top bar.

## Features

- Minimal macOS menu bar app
- Compact liquid-glass popover UI
- Local and remote Docker container list
- Host-separated container sections
- Container ID, name, tag, state, status, and ports
- Hover any table cell to see the full value
- Click any table cell to copy the full value
- Remote hosts managed inside the popover
- Launch-at-login control
- Temporary password-based SSH support for testing

## Remote Hosts

Open Bartainer from the menu bar and switch to the `Hosts` tab.

Each remote host supports:

- Name
- Address
- SSH user
- SSH port
- Password, temporarily stored plainly for testing
- Enabled/disabled state
- Inline edit and remove controls

Bartainer reads remote Docker state over SSH:

```sh
ssh -p 22 user@host "docker ps -a --format '{{json .}}'"
```

For SSH-key based access, make sure this works without a password prompt:

```sh
ssh user@100.124.170.43 docker ps
```

## Security Note

Password support is currently for local testing only. Passwords are stored in plain `UserDefaults` and passed to SSH through a temporary askpass helper.

Before using Bartainer seriously, password storage should be moved to macOS Keychain. SSH keys are the preferred long-term path.

## Build

Requirements:

- macOS 13 or newer
- Swift 6 toolchain
- Docker CLI for local containers
- SSH access for remote containers

Build the app bundle:

```sh
chmod +x scripts/build_app.sh
./scripts/build_app.sh
```

Open it:

```sh
open build/Bartainer.app
```

The app bundle is created at:

```sh
build/Bartainer.app
```

## Development

Run a debug build:

```sh
swift build
```

Package a release app:

```sh
./scripts/build_app.sh
```

## Roadmap

- Store remote passwords in macOS Keychain
- Add connection test feedback per host
- Add start, stop, restart actions
- Add filtering by host, name, and state
- Add signed/notarized app distribution
