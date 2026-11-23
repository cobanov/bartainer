<p align="center">
  <img src="assets/bartainer-logo.png" alt="Bartainer" width="128" height="128" />
</p>

<h1 align="center">Bartainer</h1>

<p align="center">
  <strong>Docker containers in your menu bar.</strong><br />
  A compact macOS app for local and remote Docker — without living in Terminal.
</p>

<p align="center">
  <a href="https://github.com/cobanov/bartainer/releases/latest"><img src="https://img.shields.io/github/v/release/cobanov/bartainer?label=Download&color=0a7c75&logo=github" alt="Latest release" /></a>
  <img src="https://img.shields.io/badge/macOS-13%2B-000000?logo=apple" alt="macOS 13+" />
</p>

> [!IMPORTANT]
> **This menu bar app is retired.** Bartainer is now **Bartainer Native**, a full native Mac app for local and remote Docker that also lives in your menu bar.
> Download it from **[bartainer.app](https://bartainer.app/download)**. It is free for local Docker and one remote host; [Bartainer Pro](https://bartainer.app/pro/) unlocks every remote host.
> The builds below stay available but won't be updated.

---

## Download

**Homebrew**

```bash
brew install --cask cobanov/tap/bartainer
```

**Manual install** — grab the latest zip from [**Releases**](https://github.com/cobanov/bartainer/releases/latest):

1. Download `Bartainer-*-macos.zip`
2. Unzip and move **Bartainer.app** to **Applications**
3. Open the app

If Gatekeeper blocks the app, **right‑click** `Bartainer.app` → **Open** → confirm once.

---

## What you get

| | |
| --- | --- |
| **Menu bar first** | One click: see every container, grouped by host |
| **Local + remote** | SSH-backed remote hosts alongside your Mac |
| **Fast at a glance** | ID, name, tag, state, status, ports in a tight table |
| **Copy anything** | Click a cell to copy; hover clipped text for the full value |
| **Native settings** | Launch at login, refresh interval, columns, hosts — all in System-style UI |

---

## Pro

Bartainer Pro is sold for Bartainer Native only. See [bartainer.app/pro](https://bartainer.app/pro/).

---

## Requirements

- **macOS 13** (Ventura) or newer  
- **Docker CLI** (Docker Desktop or your runtime of choice)  
- **SSH** to remote hosts (optional; key-based login recommended)

Remote check from Terminal (should run without a password prompt for the smoothest experience):

```bash
ssh user@host docker ps
```

---

## Links

| | |
| --- | --- |
| **Website** | [bartainer.app](https://bartainer.app) |
| **Latest build** | [GitHub Releases](https://github.com/cobanov/bartainer/releases/latest) |

---

<p align="center">
  <sub>Built for people who live in Docker but want macOS to stay quiet.</sub>
</p>
