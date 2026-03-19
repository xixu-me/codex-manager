#!/usr/bin/env bash
# shellcheck shell=bash

set -Eeuo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)"
# shellcheck disable=SC1091
# shellcheck source=../lib/codex-installer.sh
. "${SCRIPT_DIR}/../lib/codex-installer.sh"

assert_eq() {
    local actual="$1"
    local expected="$2"
    local message="$3"
    
    if [ "$actual" != "$expected" ]; then
        printf 'Assertion failed: %s\nExpected: %s\nActual:   %s\n' "$message" "$expected" "$actual" >&2
        exit 1
    fi
}

main() {
    local tmp_file
    
    assert_eq "$(normalize_arch arm64)" "aarch64" "arm64 normalizes to aarch64"
    assert_eq "$(normalize_arch amd64)" "x86_64" "amd64 normalizes to x86_64"
    assert_eq "$(normalize_release_ref latest)" "latest" "latest release remains latest"
    assert_eq "$(normalize_release_ref 0.115.0)" "rust-v0.115.0" "bare version is normalized"
    assert_eq "$(normalize_release_ref v0.115.0)" "rust-v0.115.0" "v-prefixed version is normalized"
    assert_eq "$(normalize_release_ref rust-v0.115.0)" "rust-v0.115.0" "full tag is preserved"
    
    assert_eq \
    "$(codex_release_asset_for darwin aarch64)" \
    "codex-aarch64-apple-darwin.tar.gz" \
    "darwin arm64 asset selection"
    assert_eq \
    "$(codex_release_asset_for darwin x86_64)" \
    "codex-x86_64-apple-darwin.tar.gz" \
    "darwin x86_64 asset selection"
    assert_eq \
    "$(codex_release_asset_for linux aarch64)" \
    "codex-aarch64-unknown-linux-musl.tar.gz" \
    "linux arm64 asset selection"
    assert_eq \
    "$(codex_release_asset_for linux x86_64)" \
    "codex-x86_64-unknown-linux-musl.tar.gz" \
    "linux x86_64 asset selection"
    assert_eq \
    "$(normalize_sha256 'sha256:abcdef')" \
    "abcdef" \
    "sha256 prefix is stripped"
    
    tmp_file="$(mktemp)"
    trap 'rm -f -- '"'"${tmp_file}"'"'' EXIT
    printf 'abc' >"$tmp_file"
    assert_eq \
    "$(sha256_file "$tmp_file")" \
    "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad" \
    "sha256_file extracts the digest without awk"
    
    printf 'Smoke tests passed.\n'
}

main "$@"
