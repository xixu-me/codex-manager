# codex-manager

***[English](README.md)***

`xixu-me/codex-manager` 提供 `manage.sh`，它是安装、更新和移除 Codex CLI 的唯一入口，程序来源于官方 `openai/codex` GitHub Releases。

它仅支持 macOS 和 Linux，并且只适用于 `x86_64` 与 `arm64` 架构。

## 入口

所有操作都通过 `manage.sh` 完成：

```bash
./manage.sh <command> [options]
```

也可以直接从本仓库流式执行：

```bash
curl -fsSL https://github.com/xixu-me/codex-manager/raw/refs/heads/main/manage.sh | bash -s -- <command>
```

## 命令

- `install`：安装 Codex，并在需要时启动设备码登录。
- `update`：更新已有的 Codex 安装，不会自动登录。
- `remove`：移除已安装的 `codex` 二进制，并可选清理配置。

可运行 `./manage.sh <command> --help` 查看各命令的详细参数。

## 安装

```bash
./manage.sh install [options]
```

常用选项：

- `--install-dir DIR`：将二进制安装到 `DIR`。
- `--version VERSION`：安装指定版本，可用值包括 `latest`、`0.115.0`、`v0.115.0` 和 `rust-v0.115.0`。
- `--skip-deps`：跳过依赖安装检查。
- `--skip-login`：安装后不启动设备码登录。
- `--help`, `-h`：显示帮助。

## 更新

```bash
./manage.sh update [options]
```

常用选项：

- `--install-dir DIR`：更新已经安装在 `DIR` 中的 `codex`。
- `--version VERSION`：安装指定版本。
- `--skip-deps`：跳过依赖安装检查。
- `--help`, `-h`：显示帮助。

## 移除

```bash
./manage.sh remove [options]
```

常用选项：

- `--install-dir DIR`：如果 `DIR` 中存在 `codex`，就从那里移除；如果未提供目录，则使用默认安装目录。
- `--purge-config`：同时删除 `${CODEX_HOME:-$HOME/.codex}`。
- `--help`, `-h`：显示帮助。

## 平台与依赖支持

`manage.sh` 仅面向 macOS 和 Linux，并且只处理 `x86_64` 和 `arm64` 主机。

当缺少依赖时，安装器会尽可能借助可用的包管理器自动安装。Linux 上支持的包管理器包括 `apt-get`、`dnf`、`yum`、`zypper` 和 `apk`。在 macOS 上，它会使用所需的系统工具，并且在缺少 `jq` 时可以通过 Homebrew 安装。

## 环境变量

- `CODEX_INSTALL_DIR`：默认安装目录覆盖值。
- `CODEX_VERSION`：等同于 `--version`。
- `CODEX_SKIP_DEPS=1`：等同于 `--skip-deps`。
- `CODEX_SKIP_LOGIN=1`：等同于 `--skip-login`。
- `GITHUB_TOKEN`：可选令牌，用于提高 GitHub API 的速率限制。
- `CODEX_INSTALLER_REPO_OWNER`：覆盖 bootstrap helper 仓库 owner。
- `CODEX_INSTALLER_REPO_NAME`：覆盖 bootstrap helper 仓库名称。
- `CODEX_INSTALLER_REPO_REF`：覆盖 bootstrap helper git ref。

## 许可证

本存储库基于 MIT License 发布。详见 [`LICENSE`](LICENSE)。
