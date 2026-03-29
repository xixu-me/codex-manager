# codex-manager

***[汉语](README.zh.md)***

`xixu-me/codex-manager` provides `manage.sh`, the only entrypoint for installing, updating, and removing the Codex CLI from the official `openai/codex` GitHub releases.

It supports macOS and Linux only, on `x86_64` and `arm64` systems.

## Entry point

Use `manage.sh` for every operation:

```bash
./manage.sh <command> [options]
```

You can also stream it directly from this repository:

```bash
curl -fsSL https://github.com/xixu-me/codex-manager/raw/refs/heads/main/manage.sh | bash -s -- <command>
```

## Commands

- `install`: install Codex and optionally start device-code login.
- `update`: update an existing Codex install without logging in.
- `remove`: remove the installed `codex` binary and optionally purge config.

Run `./manage.sh <command> --help` for command-specific options.

## Install

```bash
./manage.sh install [options]
```

Common options:

- `--install-dir DIR`: install the binary into `DIR`.
- `--version VERSION`: install a specific release. Accepted values are `latest`, `0.115.0`, `v0.115.0`, and `rust-v0.115.0`.
- `--skip-deps`: skip package installation checks.
- `--skip-login`: do not start device-code login after install.
- `--help`, `-h`: show help.

## Update

```bash
./manage.sh update [options]
```

Common options:

- `--install-dir DIR`: update the `codex` binary already installed in `DIR`.
- `--version VERSION`: install a specific release.
- `--skip-deps`: skip package installation checks.
- `--help`, `-h`: show help.

## Remove

```bash
./manage.sh remove [options]
```

Common options:

- `--install-dir DIR`: remove `codex` from `DIR` if it exists there, or use the default install directory when no directory is provided.
- `--purge-config`: also remove `${CODEX_HOME:-$HOME/.codex}`.
- `--help`, `-h`: show help.

## Platform and dependency support

`manage.sh` is designed for macOS and Linux only, and it only handles `x86_64` and `arm64` hosts.

When dependencies are missing, the installer tries to install them automatically using the available package manager on Linux. Supported managers include `apt-get`, `dnf`, `yum`, `zypper`, and `apk`. On macOS, it relies on the system tools it needs and can use Homebrew to install `jq` if it is missing.

## Environment variables

- `CODEX_INSTALL_DIR`: default install directory override.
- `CODEX_VERSION`: same as `--version`.
- `CODEX_SKIP_DEPS=1`: same as `--skip-deps`.
- `CODEX_SKIP_LOGIN=1`: same as `--skip-login`.
- `GITHUB_TOKEN`: optional token to raise GitHub API rate limits.
- `CODEX_INSTALLER_REPO_OWNER`: override the bootstrap helper repository owner.
- `CODEX_INSTALLER_REPO_NAME`: override the bootstrap helper repository name.
- `CODEX_INSTALLER_REPO_REF`: override the bootstrap helper git ref.

## License

This repository is licensed under the MIT License. See [`LICENSE`](LICENSE).
