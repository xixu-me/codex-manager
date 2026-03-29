# codex-installer

***[汉语](README.zh.md)***

Bootstrap installer for installing the Codex CLI on macOS/Linux from the official `openai/codex` GitHub releases and signing in with ChatGPT device code by default.

## What this repository does

- detects macOS vs. Linux and `x86_64` vs. `arm64`
- installs the minimum required packages for the bootstrap flow when possible
- fetches the correct Codex archive from the official GitHub release feed
- verifies the published SHA-256 digest when GitHub exposes it
- extracts the platform-specific executable and installs it as `codex`
- starts `codex login --device-auth` by default so the login flow works well on headless servers

## Why device-code login is the default

Current upstream Codex supports explicit device authentication with:

```bash
codex login --device-auth
```

That flow prints a verification URL and one-time code, which is ideal for a remote or headless machine. The upstream CLI also prefers device-code login in headless environments, but this repository uses the explicit flag to keep the server bootstrap behavior predictable.

## Supported upstream assets

These are the upstream archives this repository selects from the latest or pinned `openai/codex` release:

- macOS arm64: `codex-aarch64-apple-darwin.tar.gz`
- macOS x86_64: `codex-x86_64-apple-darwin.tar.gz`
- Linux arm64: `codex-aarch64-unknown-linux-musl.tar.gz`
- Linux x86_64: `codex-x86_64-unknown-linux-musl.tar.gz`

Each upstream archive contains a single platform-named executable, so the installer renames it to `codex` before putting it on disk.

## Quick start

Remote bootstrap:

```bash
curl -fsSL https://github.com/xixu-me/codex-installer/raw/refs/heads/main/install.sh | bash
```

This repository is designed around the remote-script entrypoint above. `install.sh` bootstraps itself by downloading the shared helper library from `xixu-me/codex-installer` before it talks to the official `openai/codex` release API.

## Default install behavior

`install.sh` will:

1. install missing bootstrap dependencies when possible
2. query the official `openai/codex` release metadata
3. download the correct archive for the current platform
4. verify the published digest if GitHub includes one
5. install `codex` into `/usr/local/bin` when possible, otherwise `~/.local/bin`
6. run the ChatGPT device-code login flow

The login step runs as the invoking user, even if the binary install needed `sudo`.

## Options

```text
install.sh [options]

  --install-dir DIR   Install the binary into DIR.
  --version VERSION   Install a specific release.
  --skip-deps         Skip package installation checks.
  --skip-login        Do not start device-code login after install.
  --login-only        Skip install and run login only.
  --help, -h          Show help.
```

`--version` accepts any of these forms:

- `latest`
- `0.115.0`
- `v0.115.0`
- `rust-v0.115.0`

## Environment variables

- `CODEX_INSTALL_DIR`: same as `--install-dir`
- `CODEX_VERSION`: same as `--version`
- `CODEX_SKIP_DEPS=1`: same as `--skip-deps`
- `CODEX_SKIP_LOGIN=1`: same as `--skip-login`
- `GITHUB_TOKEN`: optional token to avoid low anonymous GitHub API rate limits
- `CODEX_INSTALLER_REPO_OWNER`: override the remote bootstrap owner
- `CODEX_INSTALLER_REPO_NAME`: override the remote bootstrap repository name
- `CODEX_INSTALLER_REPO_REF`: override the remote bootstrap branch or tag

## Additional scripts

- `scripts/login-device.sh`: rerun device-code login without reinstalling
- `scripts/uninstall.sh`: remove the installed binary
- `scripts/uninstall.sh --purge-config`: also remove `${CODEX_HOME:-$HOME/.codex}`

## Dependency strategy

On Linux, the installer can use these package managers:

- `apt-get`
- `dnf`
- `yum`
- `zypper`
- `apk`

On macOS, the installer expects system `curl` and `tar`, and will use Homebrew to install `jq` if it is missing.

## Security notes

- Downloads are limited to the official `openai/codex` GitHub release feed.
- The installer uses GitHub release metadata instead of scraping HTML pages.
- When GitHub publishes a per-asset digest, the installer verifies it before installation.
- The default auth path uses ChatGPT device code, so no API key is required to get started.
- The remote bootstrap path makes one extra request to fetch `lib/codex-installer.sh` from this repository before it contacts the official `openai/codex` release API.

## CI

GitHub Actions validates the repository on both Ubuntu and macOS by running:

- `shellcheck`
- `bash -n`
- `bash tests/smoke.sh`

## License

This repository is licensed under the MIT License. See [`LICENSE`](LICENSE).
