#!/usr/bin/env bash
# shellcheck shell=bash

set -Eeuo pipefail

BOOTSTRAP_REPO_OWNER="${CODEX_INSTALLER_REPO_OWNER:-xixu-me}"
BOOTSTRAP_REPO_NAME="${CODEX_INSTALLER_REPO_NAME:-codex-manager}"
BOOTSTRAP_REPO_REF="${CODEX_INSTALLER_REPO_REF:-main}"
BOOTSTRAP_TMP_LIB=""

bootstrap_log_error() {
    printf '[ERROR] %s\n' "$*" >&2
}

bootstrap_die() {
    bootstrap_log_error "$*"
    exit 1
}

bootstrap_source_local_lib() {
    local script_source script_dir local_lib

    script_source="${BASH_SOURCE[0]:-}"
    [ -n "$script_source" ] || return 1
    [ -r "$script_source" ] || return 1

    script_dir="$(CDPATH='' cd -- "$(dirname -- "$script_source")" && pwd -P)"
    local_lib="${script_dir}/lib/common.sh"
    [ -r "$local_lib" ] || return 1

    # shellcheck disable=SC1090,SC1091
    . "$local_lib"
}

bootstrap_source_remote_lib() {
    local lib_url

    command -v curl >/dev/null 2>&1 || {
        bootstrap_die "curl is required to bootstrap the remote helper library."
    }

    BOOTSTRAP_TMP_LIB="$(mktemp)"
    lib_url="https://raw.githubusercontent.com/${BOOTSTRAP_REPO_OWNER}/${BOOTSTRAP_REPO_NAME}/${BOOTSTRAP_REPO_REF}/lib/common.sh"

    curl -fsSL "$lib_url" -o "$BOOTSTRAP_TMP_LIB" || {
        rm -f "$BOOTSTRAP_TMP_LIB"
        bootstrap_die "Failed to download helper library from ${lib_url}."
    }

    # shellcheck disable=SC1090
    . "$BOOTSTRAP_TMP_LIB"
}

cleanup_bootstrap() {
    if [ -n "${BOOTSTRAP_TMP_LIB:-}" ]; then
        rm -f "$BOOTSTRAP_TMP_LIB"
    fi
}

if ! bootstrap_source_local_lib; then
    bootstrap_source_remote_lib
fi

trap cleanup_bootstrap EXIT

# Keep bootstrap installs working if a cached remote helper lags behind manage.sh.
if ! command -v preferred_tmp_root >/dev/null 2>&1; then
    preferred_tmp_root() {
        if [ -n "${TMPDIR:-}" ] && [ -d "${TMPDIR}" ] && [ -w "${TMPDIR}" ]; then
            printf '%s\n' "$TMPDIR"
            return 0
        fi

        if [ -d /var/tmp ] && [ -w /var/tmp ]; then
            printf '/var/tmp\n'
            return 0
        fi

        if [ -d /tmp ] && [ -w /tmp ]; then
            printf '/tmp\n'
            return 0
        fi

        return 1
    }
fi

print_root_help() {
    cat <<'EOF'
Manage Codex CLI installs from the official openai/codex GitHub releases.

Usage:
  ./manage.sh <command> [options]

Commands:
  install   Install Codex and optionally start device-code login.
  update    Update an existing Codex install without logging in.
  remove    Remove the installed codex binary and optionally purge config.

Run `./manage.sh <command> --help` for command-specific options.
EOF
}

print_install_help() {
    cat <<'EOF'
Install Codex CLI from the official openai/codex GitHub releases.

Usage:
  ./manage.sh install [options]

Options:
  --install-dir DIR   Install the binary into DIR.
  --version VERSION   Install a specific release. Accepts:
                      latest, 0.115.0, v0.115.0, or rust-v0.115.0
  --skip-deps         Skip package installation checks.
  --skip-login        Do not start device-code login after install.
  --help, -h          Show this help text.

Environment variables:
  CODEX_INSTALL_DIR   Default install directory override.
  CODEX_VERSION       Same as --version.
  CODEX_SKIP_DEPS=1   Same as --skip-deps.
  CODEX_SKIP_LOGIN=1  Same as --skip-login.
  GITHUB_TOKEN        Optional token to raise GitHub API rate limits.
  CODEX_INSTALLER_REPO_OWNER  Override the bootstrap helper repository owner.
  CODEX_INSTALLER_REPO_NAME   Override the bootstrap helper repository name.
  CODEX_INSTALLER_REPO_REF    Override the bootstrap helper git ref.

Examples:
  curl -fsSL https://github.com/xixu-me/codex-manager/raw/refs/heads/main/manage.sh | bash -s -- install
  curl -fsSL https://github.com/xixu-me/codex-manager/raw/refs/heads/main/manage.sh | bash -s -- install --version 0.115.0
  curl -fsSL https://github.com/xixu-me/codex-manager/raw/refs/heads/main/manage.sh | CODEX_INSTALL_DIR="$HOME/bin" bash -s -- install --skip-login
EOF
}

print_update_help() {
    cat <<'EOF'
Update an existing Codex CLI installation.

Usage:
  ./manage.sh update [options]

Options:
  --install-dir DIR   Update the codex binary already installed in DIR.
  --version VERSION   Install a specific release. Accepts:
                      latest, 0.115.0, v0.115.0, or rust-v0.115.0
  --skip-deps         Skip package installation checks.
  --help, -h          Show this help text.

Environment variables:
  CODEX_INSTALL_DIR   Default install directory override.
  CODEX_VERSION       Same as --version.
  CODEX_SKIP_DEPS=1   Same as --skip-deps.
  GITHUB_TOKEN        Optional token to raise GitHub API rate limits.
EOF
}

print_remove_help() {
    cat <<'EOF'
Remove a Codex installation created by this repository.

Usage:
  ./manage.sh remove [options]

Options:
  --install-dir DIR   Remove codex from DIR if it exists there, or use the default install directory when no directory is provided.
  --purge-config      Also remove ${CODEX_HOME:-$HOME/.codex}.
  --help, -h          Show this help text.
EOF
}

ensure_dependencies() {
    local skip_deps="$1"

    if [ "$skip_deps" != "1" ]; then
        install_missing_dependencies
        return 0
    fi

    command_exists curl || die "curl is required when --skip-deps is used."
    command_exists jq || die "jq is required when --skip-deps is used."
    command_exists tar || die "tar is required when --skip-deps is used."
}

install_release_binary() (
    set -Eeuo pipefail

    local requested_version="$1"
    local install_dir="$2"
    local platform arch asset_name normalized_ref
    local tmp_root
    local tmp_dir metadata_file archive_path extracted_binary
    local release_tag asset_url asset_digest installed_codex

    platform="$(detect_platform)" || die "Could not determine the operating system."
    arch="$(detect_arch)" || die "Could not determine the CPU architecture."
    asset_name="$(codex_release_asset_for "$platform" "$arch")" || {
        die "No release asset is defined for ${platform}/${arch}."
    }

    normalized_ref="$(normalize_release_ref "$requested_version")"
    tmp_root="$(preferred_tmp_root)" || {
        die "Could not determine a writable temporary directory. Set TMPDIR to a writable directory with enough free space."
    }
    tmp_dir="$(mktemp -d "${tmp_root%/}/codex-install.XXXXXX")"
    trap 'rm -rf "$tmp_dir"' EXIT

    metadata_file="${tmp_dir}/release.json"
    archive_path="${tmp_dir}/${asset_name}"

    log_info "Fetching release metadata for ${normalized_ref}."
    fetch_release_metadata_to_file "$normalized_ref" "$metadata_file" || {
        die "Failed to fetch release metadata for ${normalized_ref}."
    }

    release_tag="$(release_tag_from_metadata <"$metadata_file")"
    asset_url="$(release_asset_download_url "$asset_name" <"$metadata_file")"
    asset_digest="$(release_asset_digest "$asset_name" <"$metadata_file")"

    [ -n "$release_tag" ] || die "Could not determine the release tag."
    [ -n "$asset_url" ] || die "Could not find asset ${asset_name} in release ${release_tag}."

    log_info "Downloading ${asset_name} from ${release_tag}."
    download_file "$asset_url" "$archive_path"
    verify_archive_checksum "$archive_path" "$asset_digest"

    if ! extracted_binary="$(extract_archive_binary "$archive_path" "$tmp_dir")"; then
        return 1
    fi
    [ -x "$extracted_binary" ] || chmod +x "$extracted_binary" || return 1

    if ! installed_codex="$(install_binary_to_dir "$extracted_binary" "$install_dir")"; then
        return 1
    fi
    printf '%s\n' "$installed_codex"
)

resolve_update_install_dir() {
    local install_dir="${1:-}"
    local resolved_dir

    if [ -z "$install_dir" ]; then
        install_dir="$(default_install_dir)"
    fi

    if ! resolved_dir="$(install_target_dir_for_existing_binary "$install_dir")"; then
        if [ -n "${1:-}" ]; then
            die "Could not find an installed codex binary in ${install_dir}."
        fi
        die "Could not find an installed codex binary. Run ./manage.sh install first or provide --install-dir."
    fi

    printf '%s\n' "$resolved_dir"
}

run_install_command() {
    local requested_version="${CODEX_VERSION:-latest}"
    local install_dir="${CODEX_INSTALL_DIR:-}"
    local skip_deps="${CODEX_SKIP_DEPS:-0}"
    local skip_login="${CODEX_SKIP_LOGIN:-0}"
    local installed_codex

    while [ "$#" -gt 0 ]; do
        case "$1" in
            --install-dir)
                [ "$#" -ge 2 ] || die "--install-dir requires a value."
                install_dir="$2"
                shift 2
            ;;
            --version)
                [ "$#" -ge 2 ] || die "--version requires a value."
                requested_version="$2"
                shift 2
            ;;
            --skip-deps)
                skip_deps=1
                shift
            ;;
            --skip-login)
                skip_login=1
                shift
            ;;
            --help | -h)
                print_install_help
                return 0
            ;;
            *)
                die "Unknown argument for install: $1"
            ;;
        esac
    done

    ensure_supported_platform

    if [ -n "$install_dir" ]; then
        CODEX_INSTALL_DIR="$install_dir"
    fi

    install_dir="$(default_install_dir)"
    ensure_dependencies "$skip_deps"
    if ! installed_codex="$(install_release_binary "$requested_version" "$install_dir")"; then
        die "Failed to install Codex to ${install_dir}."
    fi

    log_info "Installed Codex to ${installed_codex}."
    "$installed_codex" --version
    print_path_guidance "$install_dir"

    if [ "$skip_login" = "1" ]; then
        log_info "Skipping login because --skip-login was requested."
        return 0
    fi

    log_info "Starting the device-code login flow."
    login_with_device_code "$installed_codex"
}

run_update_command() {
    local requested_version="${CODEX_VERSION:-latest}"
    local install_dir="${CODEX_INSTALL_DIR:-}"
    local skip_deps="${CODEX_SKIP_DEPS:-0}"
    local installed_codex

    while [ "$#" -gt 0 ]; do
        case "$1" in
            --install-dir)
                [ "$#" -ge 2 ] || die "--install-dir requires a value."
                install_dir="$2"
                shift 2
            ;;
            --version)
                [ "$#" -ge 2 ] || die "--version requires a value."
                requested_version="$2"
                shift 2
            ;;
            --skip-deps)
                skip_deps=1
                shift
            ;;
            --help | -h)
                print_update_help
                return 0
            ;;
            *)
                die "Unknown argument for update: $1"
            ;;
        esac
    done

    ensure_supported_platform
    install_dir="$(resolve_update_install_dir "$install_dir")"
    CODEX_INSTALL_DIR="$install_dir"

    ensure_dependencies "$skip_deps"
    if ! installed_codex="$(install_release_binary "$requested_version" "$install_dir")"; then
        die "Failed to update Codex in ${install_dir}."
    fi

    log_info "Updated Codex in ${installed_codex}."
    "$installed_codex" --version
    print_path_guidance "$install_dir"
}

run_remove_command() {
    local install_dir="${CODEX_INSTALL_DIR:-}"
    local purge_config=0
    local codex_path codex_home

    while [ "$#" -gt 0 ]; do
        case "$1" in
            --install-dir)
                [ "$#" -ge 2 ] || die "--install-dir requires a value."
                install_dir="$2"
                shift 2
            ;;
            --purge-config)
                purge_config=1
                shift
            ;;
            --help | -h)
                print_remove_help
                return 0
            ;;
            *)
                die "Unknown argument for remove: $1"
            ;;
        esac
    done

    if [ -z "$install_dir" ]; then
        install_dir="$(default_install_dir)"
    fi

    codex_path="${install_dir}/codex"
    if ! remove_codex_install "$install_dir"; then
        die "Could not find a codex binary to remove."
    fi

    log_info "Removed ${codex_path}."

    if [ "$purge_config" != "1" ]; then
        return 0
    fi

    codex_home="${CODEX_HOME:-${HOME}/.codex}"
    if [ ! -d "$codex_home" ]; then
        log_info "Codex home ${codex_home} does not exist, so nothing else was removed."
        return 0
    fi

    rm -rf "$codex_home"
    log_info "Removed ${codex_home}."
}

main() {
    local subcommand="${1:-}"

    case "$subcommand" in
        install)
            shift
            run_install_command "$@"
        ;;
        update)
            shift
            run_update_command "$@"
        ;;
        remove)
            shift
            run_remove_command "$@"
        ;;
        "")
            print_root_help >&2
            return 1
        ;;
        *)
            log_error "Unknown subcommand: ${subcommand}"
            print_root_help >&2
            return 1
        ;;
    esac
}

main "$@"
