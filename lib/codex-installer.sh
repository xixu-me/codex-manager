#!/usr/bin/env bash
# shellcheck shell=bash

CODEX_GITHUB_OWNER="openai"
CODEX_GITHUB_REPO="codex"
CODEX_RELEASES_API_URL="https://api.github.com/repos/${CODEX_GITHUB_OWNER}/${CODEX_GITHUB_REPO}/releases"

log_info() {
    printf '[INFO] %s\n' "$*" >&2
}

log_warn() {
    printf '[WARN] %s\n' "$*" >&2
}

log_error() {
    printf '[ERROR] %s\n' "$*" >&2
}

die() {
    log_error "$*"
    exit 1
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

detect_platform() {
    case "$(uname -s)" in
        Darwin)
            printf 'darwin\n'
        ;;
        Linux)
            printf 'linux\n'
        ;;
        *)
            return 1
        ;;
    esac
}

normalize_arch() {
    case "$1" in
        arm64 | aarch64)
            printf 'aarch64\n'
        ;;
        x86_64 | amd64)
            printf 'x86_64\n'
        ;;
        *)
            return 1
        ;;
    esac
}

detect_arch() {
    normalize_arch "$(uname -m)"
}

codex_release_asset_for() {
    local platform="$1"
    local arch="$2"
    
    case "${platform}:${arch}" in
        darwin:aarch64)
            printf 'codex-aarch64-apple-darwin.tar.gz\n'
        ;;
        darwin:x86_64)
            printf 'codex-x86_64-apple-darwin.tar.gz\n'
        ;;
        linux:aarch64)
            printf 'codex-aarch64-unknown-linux-musl.tar.gz\n'
        ;;
        linux:x86_64)
            printf 'codex-x86_64-unknown-linux-musl.tar.gz\n'
        ;;
        *)
            return 1
        ;;
    esac
}

normalize_release_ref() {
    local requested="${1:-latest}"
    
    case "$requested" in
        '' | latest)
            printf 'latest\n'
        ;;
        rust-v*)
            printf '%s\n' "$requested"
        ;;
        v*)
            printf 'rust-%s\n' "$requested"
        ;;
        *)
            printf 'rust-v%s\n' "$requested"
        ;;
    esac
}

default_install_dir() {
    if [ -n "${CODEX_INSTALL_DIR:-}" ]; then
        printf '%s\n' "$CODEX_INSTALL_DIR"
        return 0
    fi
    
    if [ "$(id -u)" -eq 0 ] || [ -w "/usr/local/bin" ] || command_exists sudo; then
        printf '/usr/local/bin\n'
        return 0
    fi
    
    printf '%s/.local/bin\n' "$HOME"
}

path_contains_dir() {
    case ":${PATH}:" in
        *":$1:"*)
            return 0
        ;;
        *)
            return 1
        ;;
    esac
}

shell_rc_file() {
    local current_shell="${SHELL:-}"
    
    case "${current_shell##*/}" in
        zsh)
            printf '%s/.zshrc\n' "$HOME"
        ;;
        bash)
            if [ -f "${HOME}/.bash_profile" ]; then
                printf '%s/.bash_profile\n' "$HOME"
            else
                printf '%s/.bashrc\n' "$HOME"
            fi
        ;;
        *)
            printf '%s\n' 'your shell profile'
        ;;
    esac
}

ensure_supported_platform() {
    local platform arch
    
    if ! platform="$(detect_platform)"; then
        die "Unsupported platform: $(uname -s). This installer supports macOS and Linux only."
    fi
    
    if ! arch="$(detect_arch)"; then
        die "Unsupported architecture: $(uname -m). Supported architectures are x86_64 and arm64/aarch64."
    fi
    
    log_info "Detected platform ${platform}/${arch}."
}

run_with_sudo() {
    if [ "$(id -u)" -eq 0 ]; then
        "$@"
        return
    fi
    
    if command_exists sudo; then
        sudo "$@"
        return
    fi
    
    "$@"
}

detect_package_manager() {
    local platform
    platform="$(detect_platform)" || return 1
    
    if [ "$platform" = "darwin" ]; then
        if command_exists brew; then
            printf 'brew\n'
            return 0
        fi
        return 1
    fi
    
    if command_exists apt-get; then
        printf 'apt-get\n'
        elif command_exists dnf; then
        printf 'dnf\n'
        elif command_exists yum; then
        printf 'yum\n'
        elif command_exists zypper; then
        printf 'zypper\n'
        elif command_exists apk; then
        printf 'apk\n'
    else
        return 1
    fi
}

install_missing_dependencies() {
    local platform package_manager
    
    platform="$(detect_platform)" || die "Could not determine platform for dependency installation."
    
    if command_exists curl && command_exists jq && command_exists tar; then
        return 0
    fi
    
    package_manager="$(detect_package_manager)" || {
        if [ "$platform" = "darwin" ]; then
            die "Missing dependency detected and Homebrew was not found. Install jq manually or install Homebrew first."
        fi
        die "Missing dependency detected and no supported package manager was found. Install curl, jq, tar, and ca-certificates manually."
    }
    
    log_info "Installing required packages with ${package_manager}."
    
    case "$package_manager" in
        brew)
            brew install jq
        ;;
        apt-get)
            run_with_sudo apt-get update
            run_with_sudo apt-get install -y ca-certificates curl jq tar
        ;;
        dnf)
            run_with_sudo dnf install -y ca-certificates curl jq tar
        ;;
        yum)
            run_with_sudo yum install -y ca-certificates curl jq tar
        ;;
        zypper)
            run_with_sudo zypper --non-interactive install ca-certificates curl jq tar
        ;;
        apk)
            run_with_sudo apk add --no-cache ca-certificates curl jq tar
        ;;
        *)
            die "Unsupported package manager: ${package_manager}"
        ;;
    esac
    
    command_exists curl || die "curl is still missing after dependency installation."
    command_exists jq || die "jq is still missing after dependency installation."
    command_exists tar || die "tar is still missing after dependency installation."
}

fetch_release_metadata() {
    local release_ref="$1"
    local url
    
    if [ "$release_ref" = "latest" ]; then
        url="${CODEX_RELEASES_API_URL}/latest"
    else
        url="${CODEX_RELEASES_API_URL}/tags/${release_ref}"
    fi
    
    if [ -n "${GITHUB_TOKEN:-}" ]; then
        curl -fsSL \
        -H "Accept: application/vnd.github+json" \
        -H "Authorization: Bearer ${GITHUB_TOKEN}" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "$url"
    else
        curl -fsSL \
        -H "Accept: application/vnd.github+json" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "$url"
    fi
}

release_tag_from_metadata() {
    jq -r '.tag_name'
}

release_asset_download_url() {
    local asset_name="$1"
    
    jq -r --arg asset_name "$asset_name" '
    .assets[]
    | select(.name == $asset_name)
    | .browser_download_url
    ' | head -n 1
}

release_asset_digest() {
    local asset_name="$1"
    
    jq -r --arg asset_name "$asset_name" '
    .assets[]
    | select(.name == $asset_name)
    | (.digest // "")
    ' | head -n 1
}

download_file() {
    local url="$1"
    local destination="$2"
    
    curl -fL --retry 3 --retry-delay 2 --output "$destination" "$url"
}

normalize_sha256() {
    case "$1" in
        sha256:*)
            printf '%s\n' "${1#sha256:}"
        ;;
        *)
            printf '%s\n' "$1"
        ;;
    esac
}

sha256_file() {
    local target="$1"
    local digest_line
    
    if command_exists shasum; then
        digest_line="$(shasum -a 256 "$target")" || return 1
        printf '%s\n' "${digest_line%% *}"
        return 0
    fi
    
    if command_exists sha256sum; then
        digest_line="$(sha256sum "$target")" || return 1
        printf '%s\n' "${digest_line%% *}"
        return 0
    fi
    
    return 1
}

verify_archive_checksum() {
    local archive_path="$1"
    local published_digest="$2"
    local expected actual
    
    expected="$(normalize_sha256 "$published_digest")"
    
    if [ -z "$expected" ]; then
        log_warn "GitHub did not publish a checksum for this asset. Skipping verification."
        return 0
    fi
    
    if ! actual="$(sha256_file "$archive_path")"; then
        log_warn "No SHA-256 tool was found. Skipping verification."
        return 0
    fi
    
    if [ "$actual" != "$expected" ]; then
        die "Checksum verification failed for $(basename "$archive_path")."
    fi
    
    log_info "Checksum verified for $(basename "$archive_path")."
}

extract_archive_binary() {
    local archive_path="$1"
    local output_dir="$2"
    local archive_entry
    
    archive_entry="$(tar -tzf "$archive_path" | sed -n '1p')"
    [ -n "$archive_entry" ] || die "Archive ${archive_path} did not contain an executable."
    
    tar -xzf "$archive_path" -C "$output_dir"
    
    archive_entry="${archive_entry#./}"
    printf '%s/%s\n' "$output_dir" "$archive_entry"
}

ensure_install_directory() {
    local install_dir="$1"
    
    if [ -d "$install_dir" ]; then
        return 0
    fi
    
    if [ -w "$(dirname "$install_dir")" ]; then
        mkdir -p "$install_dir"
        return 0
    fi
    
    run_with_sudo mkdir -p "$install_dir"
}

install_binary_to_dir() {
    local source_binary="$1"
    local install_dir="$2"
    local destination="${install_dir}/codex"
    
    ensure_install_directory "$install_dir"
    
    if [ -w "$install_dir" ]; then
        install -m 0755 "$source_binary" "$destination"
    else
        run_with_sudo install -m 0755 "$source_binary" "$destination"
    fi
    
    printf '%s\n' "$destination"
}

resolve_codex_binary() {
    local install_dir="${1:-}"
    
    if [ -n "$install_dir" ] && [ -x "${install_dir}/codex" ]; then
        printf '%s/codex\n' "$install_dir"
        return 0
    fi
    
    if command_exists codex; then
        command -v codex
        return 0
    fi
    
    return 1
}

codex_supports_device_auth() {
    local codex_path="$1"
    
    "$codex_path" login --help 2>&1 | grep -q -- '--device-auth'
}

login_with_device_code() {
    local codex_path="$1"
    
    if codex_supports_device_auth "$codex_path"; then
        "$codex_path" login --device-auth
        return 0
    fi
    
    log_warn "This Codex build does not advertise --device-auth. Falling back to the standard login command."
    "$codex_path" login
}

print_path_guidance() {
    local install_dir="$1"
    
    if path_contains_dir "$install_dir"; then
        return 0
    fi
    
    log_warn "${install_dir} is not on PATH for the current shell."
    printf "Add it with:\n  export PATH=\"%s:\$PATH\"\n" "$install_dir"
    printf 'Then append that line to %s if you want it to persist.\n' "$(shell_rc_file)"
}

remove_file() {
    local target="$1"
    
    if [ ! -e "$target" ]; then
        return 0
    fi
    
    if [ -w "$(dirname "$target")" ]; then
        rm -f "$target"
    else
        run_with_sudo rm -f "$target"
    fi
}
