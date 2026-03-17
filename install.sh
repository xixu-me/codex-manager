#!/usr/bin/env bash
# shellcheck shell=bash

set -Eeuo pipefail

BOOTSTRAP_REPO_OWNER="${CODEX_INSTALLER_REPO_OWNER:-xixu-me}"
BOOTSTRAP_REPO_NAME="${CODEX_INSTALLER_REPO_NAME:-codex-installer}"
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
    local installer_source script_dir local_lib
    
    installer_source="${BASH_SOURCE[0]:-}"
    [ -n "$installer_source" ] || return 1
    [ -r "$installer_source" ] || return 1
    
    script_dir="$(CDPATH='' cd -- "$(dirname -- "$installer_source")" && pwd -P)"
    local_lib="${script_dir}/lib/codex-installer.sh"
    [ -r "$local_lib" ] || return 1
    
    # shellcheck disable=SC1090,SC1091
    . "$local_lib"
}

bootstrap_source_remote_lib() {
    local lib_url
    
    command -v curl >/dev/null 2>&1 || {
        bootstrap_die "curl is required to bootstrap the remote installer."
    }
    
    BOOTSTRAP_TMP_LIB="$(mktemp)"
    lib_url="https://raw.githubusercontent.com/${BOOTSTRAP_REPO_OWNER}/${BOOTSTRAP_REPO_NAME}/${BOOTSTRAP_REPO_REF}/lib/codex-installer.sh"
    
    curl -fsSL "$lib_url" -o "$BOOTSTRAP_TMP_LIB" || {
        rm -f "$BOOTSTRAP_TMP_LIB"
        bootstrap_die "Failed to download helper library from ${lib_url}."
    }
    
    # shellcheck disable=SC1090
    . "$BOOTSTRAP_TMP_LIB"
}

if ! bootstrap_source_local_lib; then
    bootstrap_source_remote_lib
fi

print_help() {
  cat <<'EOF'
Install Codex CLI from the official openai/codex GitHub releases.

Usage:
  ./install.sh [options]

Options:
  --install-dir DIR   Install the binary into DIR.
  --version VERSION   Install a specific release. Accepts:
                      latest, 0.115.0, v0.115.0, or rust-v0.115.0
  --skip-deps         Skip package installation checks.
  --skip-login        Do not start device-code login after install.
  --login-only        Skip install and run the device-code login flow only.
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
  curl -fsSL https://github.com/xixu-me/codex-installer/raw/refs/heads/main/install.sh | bash
  curl -fsSL https://github.com/xixu-me/codex-installer/raw/refs/heads/main/install.sh | bash -s -- --version 0.115.0
  curl -fsSL https://github.com/xixu-me/codex-installer/raw/refs/heads/main/install.sh | CODEX_INSTALL_DIR="$HOME/bin" bash -s -- --skip-login
EOF
}

main() {
    local requested_version="${CODEX_VERSION:-latest}"
    local install_dir="${CODEX_INSTALL_DIR:-}"
    local skip_deps="${CODEX_SKIP_DEPS:-0}"
    local skip_login="${CODEX_SKIP_LOGIN:-0}"
    local login_only=0
    
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
            --login-only)
                login_only=1
                shift
            ;;
            --help | -h)
                print_help
                exit 0
            ;;
            *)
                die "Unknown argument: $1"
            ;;
        esac
    done
    
    ensure_supported_platform
    
    if [ -n "$install_dir" ]; then
        CODEX_INSTALL_DIR="$install_dir"
    fi
    
    install_dir="$(default_install_dir)"
    
    if [ "$skip_deps" != "1" ]; then
        install_missing_dependencies
    else
        command_exists curl || die "curl is required when --skip-deps is used."
        command_exists jq || die "jq is required when --skip-deps is used."
        command_exists tar || die "tar is required when --skip-deps is used."
    fi
    
    if [ "$login_only" = "1" ]; then
        local existing_codex
        
        if ! existing_codex="$(resolve_codex_binary "$install_dir")"; then
            die "Could not find an installed codex binary. Run ./install.sh first or put codex on PATH."
        fi
        
        log_info "Starting device-code login with ${existing_codex}."
        login_with_device_code "$existing_codex"
        return 0
    fi
    
    local platform arch asset_name normalized_ref
    local tmp_dir metadata_file archive_path extracted_binary
    local release_tag asset_url asset_digest installed_codex
    
    platform="$(detect_platform)" || die "Could not determine the operating system."
    arch="$(detect_arch)" || die "Could not determine the CPU architecture."
    asset_name="$(codex_release_asset_for "$platform" "$arch")" || {
        die "No release asset is defined for ${platform}/${arch}."
    }
    
    normalized_ref="$(normalize_release_ref "$requested_version")"
    tmp_dir="$(mktemp -d)"
    metadata_file="${tmp_dir}/release.json"
    archive_path="${tmp_dir}/${asset_name}"
    
    cleanup() {
        rm -rf "$tmp_dir"
        if [ -n "${BOOTSTRAP_TMP_LIB:-}" ]; then
            rm -f "$BOOTSTRAP_TMP_LIB"
        fi
    }
    trap cleanup EXIT
    
    log_info "Fetching release metadata for ${normalized_ref}."
    fetch_release_metadata "$normalized_ref" >"$metadata_file"
    
    release_tag="$(release_tag_from_metadata <"$metadata_file")"
    asset_url="$(release_asset_download_url "$asset_name" <"$metadata_file")"
    asset_digest="$(release_asset_digest "$asset_name" <"$metadata_file")"
    
    [ -n "$release_tag" ] || die "Could not determine the release tag."
    [ -n "$asset_url" ] || die "Could not find asset ${asset_name} in release ${release_tag}."
    
    log_info "Downloading ${asset_name} from ${release_tag}."
    download_file "$asset_url" "$archive_path"
    verify_archive_checksum "$archive_path" "$asset_digest"
    
    extracted_binary="$(extract_archive_binary "$archive_path" "$tmp_dir")"
    [ -x "$extracted_binary" ] || chmod +x "$extracted_binary"
    
    installed_codex="$(install_binary_to_dir "$extracted_binary" "$install_dir")"
    
    log_info "Installed Codex to ${installed_codex}."
    "${installed_codex}" --version
    print_path_guidance "$install_dir"
    
    if [ "$skip_login" = "1" ]; then
        log_info "Skipping login because --skip-login was requested."
        return 0
    fi
    
    log_info "Starting the default ChatGPT device-code login flow."
    login_with_device_code "$installed_codex"
}

main "$@"
