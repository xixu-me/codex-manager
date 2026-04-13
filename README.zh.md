# codex-manager

[![CI](https://github.com/xixu-me/codex-manager/actions/workflows/ci.yml/badge.svg)](https://github.com/xixu-me/codex-manager/actions/workflows/ci.yml)

**_[English](./README.md)_**

一个基于 Bash 的小型管理器，从 [GitHub releases](https://github.com/openai/codex/releases) 安装、更新和移除官方的 Codex CLI。

`codex-manager` 专为 Linux 和 macOS 上直接通过 shell 安装而设计。它会为当前平台获取正确的发布资源，在可用时校验官方发布的校验和，将 `codex` 二进制安装到合适的位置，并且可以在安装后按需启动设备码登录流程。

> [!NOTE]
> 安装器仅支持 Linux 和 macOS 目标平台。你可以在其他环境中编辑该存储库，但受管理的 Codex 安装流程仅面向类 Unix 系统。

## 亮点

- 从 GitHub releases 安装官方 `codex` 二进制。
- 支持 `install`、`update` 和 `remove` 工作流。
- 接受 `latest`、`0.115.0`、`v0.115.0` 和 `rust-v0.115.0` 这些版本格式。
- 当 GitHub 发布校验和时进行校验。
- 除非你选择跳过，否则会自动安装缺失的依赖。
- 兼容常见包管理器，包括 `apt`、`dnf`、`brew`、`zypper`、`apk` 和 `yum`。

## 为什么默认使用设备码登录

该安装器会显式执行：

```bash
codex login --device-auth
```

该流程会输出验证链接和一次性代码，更适合远程或无头机器。该存储库显式传入该参数，是为了让登录路径更可预测。若设备码登录不可用，Codex 会回退到标准的浏览器登录流程。

## 快速开始

安装最新版 Codex 并启动登录：

```bash
curl -fsSL https://github.com/xixu-me/codex-manager/raw/refs/heads/main/manage.sh | bash -s -- install
```

安装指定版本：

```bash
curl -fsSL https://github.com/xixu-me/codex-manager/raw/refs/heads/main/manage.sh | bash -s -- install --version 0.115.0
```

安装但不启动登录：

```bash
curl -fsSL https://github.com/xixu-me/codex-manager/raw/refs/heads/main/manage.sh | bash -s -- install --skip-login
```

使用自定义安装目录：

```bash
curl -fsSL https://github.com/xixu-me/codex-manager/raw/refs/heads/main/manage.sh | CODEX_INSTALL_DIR="$HOME/bin" bash -s -- install
```

## 命令

如果你想在本地运行该管理器，可以先克隆存储库：

```bash
git clone https://github.com/xixu-me/codex-manager.git
cd codex-manager
chmod +x manage.sh
```

然后使用主入口：

```bash
./manage.sh <command> [options]
```

### `install`

将 Codex 安装到默认目录或指定目录，并可选择启动设备码登录流程。如果设备码登录不可用，Codex 会回退到标准的浏览器登录流程。

```bash
./manage.sh install
./manage.sh install --version 0.115.0
./manage.sh install --install-dir "$HOME/.local/bin" --skip-login
```

常用选项：

- `--install-dir DIR`
- `--version VERSION`
- `--skip-deps`
- `--skip-login`

### `update`

原地更新现有的 Codex 安装，不会触发登录。

```bash
./manage.sh update
./manage.sh update --version latest
./manage.sh update --install-dir "$HOME/.local/bin"
```

常用选项：

- `--install-dir DIR`
- `--version VERSION`
- `--skip-deps`

### `remove`

移除已安装的 `codex` 二进制，并可选择清理 Codex 配置数据。

```bash
./manage.sh remove
./manage.sh remove --install-dir "$HOME/.local/bin"
./manage.sh remove --purge-config
```

常用选项：

- `--install-dir DIR`
- `--purge-config`

> [!TIP]
> 如果安装目录尚未加入 `PATH`，脚本会打印出需要添加的确切 `export` 命令，并提示你应更新哪个 shell 启动文件。

## 环境变量

这些变量与 CLI 标志对应，适合用于自动化：

| 变量 | 说明 |
| --- | --- |
| `CODEX_INSTALL_DIR` | `install` 或 `update` 的默认目标目录。 |
| `CODEX_VERSION` | 发布选择器，例如 `latest` 或 `0.115.0`。 |
| `CODEX_SKIP_DEPS=1` | 跳过依赖安装检查。 |
| `CODEX_SKIP_LOGIN=1` | 在 `install` 之后跳过登录。 |
| `GITHUB_TOKEN` | 可选的 GitHub token，用于提高 release API 的速率限制。 |
| `CODEX_INSTALLER_REPO_OWNER` | 覆盖引导辅助存储库的 owner。 |
| `CODEX_INSTALLER_REPO_NAME` | 覆盖引导辅助存储库的名称。 |
| `CODEX_INSTALLER_REPO_REF` | 覆盖引导辅助存储库的 ref。 |

## 工作原理

该存储库刻意保持精简：

- [`manage.sh`](./manage.sh) 是公开入口和 CLI 接口。
- [`lib/common.sh`](./lib/common.sh) 包含平台检测、依赖安装、发布查询、校验和校验、解压、安装、登录和移除等辅助逻辑。
- [`tests/smoke.sh`](./tests/smoke.sh) 覆盖核心 shell 行为，并防止破坏性边界情况。

当 `manage.sh` 在非完整克隆环境中执行时，它可以从本存储库引导 `lib/common.sh`，这样单行 `curl | bash` 流程仍然可用。

## 开发

项目提供 GitHub Actions CI，用于：

- ShellCheck lint
- Bash 语法校验
- Smoke tests

本地开发就是标准的 shell 脚本工作流：

```bash
shellcheck -x manage.sh lib/*.sh tests/*.sh
bash -n manage.sh lib/*.sh tests/*.sh
bash tests/smoke.sh
```

Dependabot 会保持 GitHub Actions 依赖项为最新状态，成功的 Dependabot PR 也会通过存储库工作流自动合并。

## 许可证

基于 MIT License 发布。参见 [`LICENSE`](./LICENSE)。
