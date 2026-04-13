# codex-manager

[![CI](https://github.com/xixu-me/codex-manager/actions/workflows/ci.yml/badge.svg)](https://github.com/xixu-me/codex-manager/actions/workflows/ci.yml)

**_[汉语](./README.zh.md)_**

Install, update, and remove the official Codex CLI from [GitHub releases](https://github.com/openai/codex/releases) with a small Bash-based manager.

`codex-manager` is designed for straightforward shell installs on Linux and macOS. It fetches the correct release asset for the current platform, verifies published checksums when available, installs the `codex` binary into a sensible location, and can optionally start the device-code login flow after install.

> [!NOTE]
> The installer supports Linux and macOS targets only. You can edit this repository from other environments, but the managed Codex install flow is intended for Unix-like systems.

## Highlights

- Installs the official `codex` binary from GitHub releases.
- Supports `install`, `update`, and `remove` workflows.
- Accepts `latest`, `0.115.0`, `v0.115.0`, and `rust-v0.115.0` version formats.
- Verifies release checksums when GitHub publishes them.
- Installs missing dependencies automatically unless you opt out.
- Works with common package managers including `apt`, `dnf`, `brew`, `zypper`, `apk`, and `yum`.

## Why Device-Code Login Is The Default

This installer explicitly runs:

```bash
codex login --device-auth
```

This flow prints a verification URL and one-time code, which works well on remote or headless machines. This repository passes the flag explicitly so the login path stays predictable. If device-code login is unavailable, Codex falls back to the standard browser-based login flow.

## Quick Start

Install the latest Codex release and start login:

```bash
curl -fsSL https://github.com/xixu-me/codex-manager/raw/refs/heads/main/manage.sh | bash -s -- install
```

Install a specific version:

```bash
curl -fsSL https://github.com/xixu-me/codex-manager/raw/refs/heads/main/manage.sh | bash -s -- install --version 0.115.0
```

Install without launching login:

```bash
curl -fsSL https://github.com/xixu-me/codex-manager/raw/refs/heads/main/manage.sh | bash -s -- install --skip-login
```

Use a custom install directory:

```bash
curl -fsSL https://github.com/xixu-me/codex-manager/raw/refs/heads/main/manage.sh | CODEX_INSTALL_DIR="$HOME/bin" bash -s -- install
```

## Commands

Clone the repository if you want to run the manager locally:

```bash
git clone https://github.com/xixu-me/codex-manager.git
cd codex-manager
chmod +x manage.sh
```

Then use the main entrypoint:

```bash
./manage.sh <command> [options]
```

### `install`

Installs Codex into the default or requested directory and optionally starts the device-code login flow. If device code login is unavailable, Codex falls back to the standard browser-based login flow.

```bash
./manage.sh install
./manage.sh install --version 0.115.0
./manage.sh install --install-dir "$HOME/.local/bin" --skip-login
```

Common options:

- `--install-dir DIR`
- `--version VERSION`
- `--skip-deps`
- `--skip-login`

### `update`

Updates an existing Codex installation in place without triggering login.

```bash
./manage.sh update
./manage.sh update --version latest
./manage.sh update --install-dir "$HOME/.local/bin"
```

Common options:

- `--install-dir DIR`
- `--version VERSION`
- `--skip-deps`

### `remove`

Removes the installed `codex` binary and can optionally purge Codex config data.

```bash
./manage.sh remove
./manage.sh remove --install-dir "$HOME/.local/bin"
./manage.sh remove --purge-config
```

Common options:

- `--install-dir DIR`
- `--purge-config`

> [!TIP]
> If the install directory is not already on `PATH`, the script prints the exact export command to add it and suggests which shell startup file to update.

## Environment Variables

These variables mirror the CLI flags and are useful for automation:

| Variable | Description |
| --- | --- |
| `CODEX_INSTALL_DIR` | Default target directory for install or update. |
| `CODEX_VERSION` | Release selector such as `latest` or `0.115.0`. |
| `CODEX_SKIP_DEPS=1` | Skip dependency installation checks. |
| `CODEX_SKIP_LOGIN=1` | Skip login after `install`. |
| `GITHUB_TOKEN` | Optional GitHub token to raise release API rate limits. |
| `CODEX_INSTALLER_REPO_OWNER` | Override the bootstrap helper repository owner. |
| `CODEX_INSTALLER_REPO_NAME` | Override the bootstrap helper repository name. |
| `CODEX_INSTALLER_REPO_REF` | Override the bootstrap helper repository ref. |

## How It Works

The repository is intentionally small:

- [`manage.sh`](./manage.sh) is the public entrypoint and CLI surface.
- [`lib/common.sh`](./lib/common.sh) contains platform detection, dependency installation, release lookup, checksum verification, extraction, install, login, and removal helpers.
- [`tests/smoke.sh`](./tests/smoke.sh) exercises the core shell behavior and guards against destructive edge cases.

When `manage.sh` is executed outside a full clone, it can bootstrap `lib/common.sh` from this repository so the one-line `curl | bash` flow still works.

## Development

The project ships with GitHub Actions CI for:

- ShellCheck linting
- Bash syntax validation
- Smoke tests

Local development is standard shell scripting:

```bash
shellcheck -x manage.sh lib/*.sh tests/*.sh
bash -n manage.sh lib/*.sh tests/*.sh
bash tests/smoke.sh
```

Dependabot keeps GitHub Actions dependencies current, and successful Dependabot PRs are auto-merged through the repository workflow.

## License

Licensed under the MIT License. See [`LICENSE`](./LICENSE).
