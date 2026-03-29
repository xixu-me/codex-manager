# codex-installer

***[English](README.md)***

用于在 macOS/Linux 上安装 Codex CLI 的引导安装器。它从官方 `openai/codex` GitHub Releases 下载程序，并默认通过 ChatGPT 设备码方式登录。

## 这个存储库做什么

- 检测 macOS 或 Linux，以及 `x86_64` 或 `arm64`
- 在可行时为引导安装流程安装最少的必需依赖
- 从官方 GitHub release 源获取正确的 Codex 压缩包
- 在 GitHub 提供 SHA-256 摘要时进行校验
- 解压对应平台的可执行文件，并以 `codex` 名称安装
- 默认启动 `codex login --device-auth`，让无头服务器上的登录流程更顺畅

## 为什么默认使用设备码登录

当前上游 Codex 明确支持以下设备认证方式：

```bash
codex login --device-auth
```

这个流程会输出验证 URL 和一次性验证码，非常适合远程或无头机器。上游 CLI 在无头环境下也会偏向设备码登录，但这个存储库显式使用该参数，以便让服务器引导安装行为更可预测。

## 支持的上游资源

本存储库会从最新版本或指定版本的 `openai/codex` release 中选择以下压缩包：

- macOS arm64: `codex-aarch64-apple-darwin.tar.gz`
- macOS x86_64: `codex-x86_64-apple-darwin.tar.gz`
- Linux arm64: `codex-aarch64-unknown-linux-musl.tar.gz`
- Linux x86_64: `codex-x86_64-unknown-linux-musl.tar.gz`

每个上游压缩包都只包含一个按平台命名的可执行文件，因此安装器会在写入磁盘前将其重命名为 `codex`。

## 快速开始

远程引导安装：

```bash
curl -fsSL https://github.com/xixu-me/codex-installer/raw/refs/heads/main/install.sh | bash
```

这个存储库围绕上述远程脚本入口设计。`install.sh` 会先从 `xixu-me/codex-installer` 下载共享辅助库，再访问官方 `openai/codex` release API。

## 默认安装行为

`install.sh` 会：

1. 在可行时安装缺失的引导依赖
2. 查询官方 `openai/codex` release 元数据
3. 下载适用于当前平台的压缩包
4. 如果 GitHub 提供摘要则校验发布内容
5. 尽可能将 `codex` 安装到 `/usr/local/bin`，否则安装到 `~/.local/bin`
6. 运行 ChatGPT 设备码登录流程

即使二进制安装步骤需要 `sudo`，登录步骤也会以当前调用用户身份运行。

## 选项

```text
install.sh [options]

  --install-dir DIR   将二进制安装到 DIR。
  --version VERSION   安装指定版本。
  --skip-deps         跳过依赖安装检查。
  --skip-login        安装后不启动设备码登录。
  --login-only        跳过安装，仅执行登录。
  --help, -h          显示帮助。
```

`--version` 支持以下任意形式：

- `latest`
- `0.115.0`
- `v0.115.0`
- `rust-v0.115.0`

## 环境变量

- `CODEX_INSTALL_DIR`：等同于 `--install-dir`
- `CODEX_VERSION`：等同于 `--version`
- `CODEX_SKIP_DEPS=1`：等同于 `--skip-deps`
- `CODEX_SKIP_LOGIN=1`：等同于 `--skip-login`
- `GITHUB_TOKEN`：可选，用于避免 GitHub 匿名 API 的较低速率限制
- `CODEX_INSTALLER_REPO_OWNER`：覆盖远程引导使用的存储库 owner
- `CODEX_INSTALLER_REPO_NAME`：覆盖远程引导使用的存储库名称
- `CODEX_INSTALLER_REPO_REF`：覆盖远程引导使用的分支或标签

## 附加脚本

- `scripts/login-device.sh`：无需重新安装，重新执行设备码登录
- `scripts/uninstall.sh`：移除已安装的二进制文件
- `scripts/uninstall.sh --purge-config`：同时删除 `${CODEX_HOME:-$HOME/.codex}`

## 依赖策略

在 Linux 上，安装器可使用以下包管理器：

- `apt-get`
- `dnf`
- `yum`
- `zypper`
- `apk`

在 macOS 上，安装器依赖系统自带的 `curl` 和 `tar`；如果缺少 `jq`，则会使用 Homebrew 安装。

## 安全说明

- 下载范围仅限官方 `openai/codex` GitHub release 源。
- 安装器使用 GitHub release 元数据，而不是抓取 HTML 页面。
- 当 GitHub 为单个资源提供摘要时，安装前会先进行校验。
- 默认认证路径使用 ChatGPT 设备码，因此无需 API key 即可开始使用。
- 远程引导路径会额外请求一次本存储库中的 `lib/codex-installer.sh`，之后才会访问官方 `openai/codex` release API。

## CI

GitHub Actions 会在 Ubuntu 和 macOS 上运行以下检查来验证存储库：

- `shellcheck`
- `bash -n`
- `bash tests/smoke.sh`

## 许可证

本存储库基于 MIT License 发布。详见 [`LICENSE`](LICENSE)。
