#!/usr/bin/env bash
# shellcheck shell=bash

set -Eeuo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)"
# shellcheck disable=SC1091
# shellcheck source=../lib/common.sh
. "${SCRIPT_DIR}/../lib/common.sh"

assert_eq() {
    local actual="$1"
    local expected="$2"
    local message="$3"
    
    if [ "$actual" != "$expected" ]; then
        printf 'Assertion failed: %s\nExpected: %s\nActual:   %s\n' "$message" "$expected" "$actual" >&2
        exit 1
    fi
}

assert_file_content_eq() {
    local path="$1"
    local expected="$2"
    local message="$3"
    local actual

    actual="$(cat "$path")"
    assert_eq "$actual" "$expected" "$message"
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local message="$3"

    if [[ "$haystack" != *"$needle"* ]]; then
        printf 'Assertion failed: %s\nExpected output to contain: %s\nActual output:\n%s\n' "$message" "$needle" "$haystack" >&2
        exit 1
    fi
}

run_manage_command() {
    local output_file="$1"
    shift

    if bash "${SCRIPT_DIR}/../manage.sh" "$@" >"$output_file" 2>&1; then
        return 0
    fi

    return 1
}

main() {
    local tmp_file temp_root real_tar fake_tar_bin fake_install_bin
    local archive_input_dir archive_path install_dir source_binary extracted_path
    local installed_path old_path fake_path_bin fake_codex_bin real_dirname real_bash
    local existing_install_dir preserved_file other_exec_file path_candidate_dir
    local wrong_install_dir explicit_result
    local install_target_dir result_path command_output dangerous_cli_bin remove_log update_log
    local readme readme_zh
    
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
    trap 'rm -f -- "${tmp_file:-}"' EXIT
    printf 'abc' >"$tmp_file"
    assert_eq \
    "$(sha256_file "$tmp_file")" \
    "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad" \
    "sha256_file extracts the digest without awk"

    temp_root="$(mktemp -d)"
    real_tar="$(command -v tar)"
    trap 'rm -f -- "${tmp_file:-}"; rm -rf -- "${temp_root:-}"' EXIT

    archive_input_dir="${temp_root}/archive-input"
    archive_path="${temp_root}/codex.tar.gz"
    mkdir -p "$archive_input_dir"
    printf 'codex-binary' >"${archive_input_dir}/codex-x86_64-unknown-linux-musl"
    tar -czf "$archive_path" -C "$archive_input_dir" codex-x86_64-unknown-linux-musl

    fake_tar_bin="${temp_root}/fake-tar-bin"
    mkdir -p "$fake_tar_bin"
    cat >"${fake_tar_bin}/tar" <<EOF
#!/usr/bin/env bash
if [ "\$1" = "-tzf" ]; then
    exec "$real_tar" "\$@"
fi

if [ "\$1" = "-xzf" ]; then
    printf 'simulated tar extraction failure\n' >&2
    exit 1
fi

exec "$real_tar" "\$@"
EOF
    chmod +x "${fake_tar_bin}/tar"

    old_path="$PATH"
    PATH="${fake_tar_bin}:$PATH"
    if extracted_path="$(extract_archive_binary "$archive_path" "${temp_root}/extract-output")"; then
        printf 'Assertion failed: extract_archive_binary should fail when tar extraction fails\n' >&2
        exit 1
    fi
    printf '%s' "${extracted_path:-}" >/dev/null
    PATH="$old_path"

    install_dir="${temp_root}/install-dir"
    mkdir -p "$install_dir"
    printf 'existing-binary' >"${install_dir}/codex"
    source_binary="${temp_root}/replacement-codex"
    printf 'replacement-binary' >"$source_binary"
    chmod +x "$source_binary"

    fake_install_bin="${temp_root}/fake-install-bin"
    mkdir -p "$fake_install_bin"
    cat >"${fake_install_bin}/install" <<EOF
#!/usr/bin/env bash
destination="\${!#}"
printf 'partial-binary' >"\$destination"
exit 1
EOF
    chmod +x "${fake_install_bin}/install"

    PATH="${fake_install_bin}:$old_path"
    if installed_path="$(install_binary_to_dir "$source_binary" "$install_dir")"; then
        printf 'Assertion failed: install_binary_to_dir should fail when install exits non-zero\n' >&2
        exit 1
    fi
    printf '%s' "${installed_path:-}" >/dev/null
    PATH="$old_path"

    assert_file_content_eq \
    "${install_dir}/codex" \
    "existing-binary" \
    "failed install keeps the previous codex binary intact"

    fake_path_bin="${temp_root}/fake-path-bin"
    mkdir -p "$fake_path_bin"
    real_bash="$(command -v bash)"
    real_dirname="$(command -v dirname)"
    cat >"${fake_path_bin}/dirname" <<EOF
#!${real_bash}
exec "$real_dirname" "\$@"
EOF
    chmod +x "${fake_path_bin}/dirname"
    fake_codex_bin="${fake_path_bin}/codex"
    cat >"$fake_codex_bin" <<EOF
#!${real_bash}
exit 0
EOF
    chmod +x "$fake_codex_bin"

    install_target_dir="$(PATH="$fake_path_bin" install_target_dir_for_existing_binary)"
    assert_eq \
    "$install_target_dir" \
    "$fake_path_bin" \
    "install_target_dir_for_existing_binary returns the parent directory of a found codex binary"

    fake_path_bin="${temp_root}/empty-path-bin"
    mkdir -p "$fake_path_bin"
    if result_path="$(PATH="$fake_path_bin" install_target_dir_for_existing_binary)"; then
        printf 'Assertion failed: install_target_dir_for_existing_binary should fail when codex is missing\n' >&2
        exit 1
    fi
    printf '%s' "${result_path:-}" >/dev/null

    path_candidate_dir="${temp_root}/path-candidate"
    mkdir -p "$path_candidate_dir"
    cat >"${path_candidate_dir}/codex" <<EOF
#!${real_bash}
exit 0
EOF
    chmod +x "${path_candidate_dir}/codex"
    other_exec_file="${path_candidate_dir}/not-codex"
    cat >"$other_exec_file" <<EOF
#!${real_bash}
exit 0
EOF
    chmod +x "$other_exec_file"

    existing_install_dir="${temp_root}/remove-install"
    mkdir -p "$existing_install_dir"
    cat >"${existing_install_dir}/codex" <<EOF
#!${real_bash}
exit 0
EOF
    chmod +x "${existing_install_dir}/codex"
    cat >"${existing_install_dir}/not-codex" <<EOF
#!${real_bash}
exit 0
EOF
    chmod +x "${existing_install_dir}/not-codex"
    preserved_file="${existing_install_dir}/keep-me.txt"
    printf 'keep-me' >"$preserved_file"
    PATH="${path_candidate_dir}:$PATH" remove_codex_install "$existing_install_dir"
    if [ -e "${existing_install_dir}/codex" ]; then
        printf 'Assertion failed: remove_codex_install should delete the codex binary\n' >&2
        exit 1
    fi
    assert_file_content_eq \
    "$preserved_file" \
    "keep-me" \
    "remove_codex_install preserves unrelated files"
    if [ ! -e "${path_candidate_dir}/codex" ]; then
        printf 'Assertion failed: remove_codex_install should not remove the PATH codex candidate\n' >&2
        exit 1
    fi
    if [ ! -e "${existing_install_dir}/not-codex" ]; then
        printf 'Assertion failed: remove_codex_install should not remove unrelated executables in the install dir\n' >&2
        exit 1
    fi
    if [ ! -e "$other_exec_file" ]; then
        printf 'Assertion failed: remove_codex_install should not remove unrelated executables on PATH\n' >&2
        exit 1
    fi

    wrong_install_dir="${temp_root}/wrong-install-dir"
    mkdir -p "$wrong_install_dir"
    printf 'not-executable-codex' >"${wrong_install_dir}/codex"
    chmod 0644 "${wrong_install_dir}/codex"
    if explicit_result="$(PATH="${path_candidate_dir}:$PATH" install_target_dir_for_existing_binary "$wrong_install_dir")"; then
        printf 'Assertion failed: install_target_dir_for_existing_binary should fail closed for a non-executable explicit install dir\n' >&2
        exit 1
    fi
    printf '%s' "${explicit_result:-}" >/dev/null
    if PATH="${path_candidate_dir}:$PATH" remove_codex_install "$wrong_install_dir"; then
        printf 'Assertion failed: remove_codex_install should fail closed for a non-executable explicit install dir\n' >&2
        exit 1
    fi
    if [ ! -e "${path_candidate_dir}/codex" ]; then
        printf 'Assertion failed: remove_codex_install should not delete the PATH codex candidate when explicit install dir is wrong\n' >&2
        exit 1
    fi

    command_output="${temp_root}/manage-output.txt"

    if run_manage_command "$command_output"; then
        printf 'Assertion failed: manage.sh should fail when no subcommand is provided\n' >&2
        exit 1
    fi
    assert_contains "$(cat "$command_output")" "Usage:" "manage.sh without a subcommand prints help"
    assert_contains "$(cat "$command_output")" "install" "manage.sh help mentions install"
    assert_contains "$(cat "$command_output")" "update" "manage.sh help mentions update"
    assert_contains "$(cat "$command_output")" "remove" "manage.sh help mentions remove"

    if ! run_manage_command "$command_output" install --help; then
        printf 'Assertion failed: manage.sh install --help should succeed\n' >&2
        exit 1
    fi
    assert_contains "$(cat "$command_output")" "manage.sh install" "install help is shown"

    if ! run_manage_command "$command_output" update --help; then
        printf 'Assertion failed: manage.sh update --help should succeed\n' >&2
        exit 1
    fi
    assert_contains "$(cat "$command_output")" "manage.sh update" "update help is shown"

    if ! run_manage_command "$command_output" remove --help; then
        printf 'Assertion failed: manage.sh remove --help should succeed\n' >&2
        exit 1
    fi
    assert_contains "$(cat "$command_output")" "manage.sh remove" "remove help is shown"
    assert_contains "$(cat "$command_output")" "default install directory" "remove help describes the default install directory behavior"
    if [[ "$(cat "$command_output")" == *"detected install"* ]]; then
        printf 'Assertion failed: remove help should not mention a detected install fallback\n' >&2
        exit 1
    fi

    if run_manage_command "$command_output" login; then
        printf 'Assertion failed: manage.sh should reject unsupported subcommands\n' >&2
        exit 1
    fi
    assert_contains "$(cat "$command_output")" "Unknown subcommand" "manage.sh reports unsupported subcommands"

    dangerous_cli_bin="${temp_root}/dangerous-cli-bin"
    mkdir -p "$dangerous_cli_bin"
    remove_log="${temp_root}/remove.log"
    cat >"${dangerous_cli_bin}/codex" <<EOF
#!${real_bash}
exit 0
EOF
    chmod +x "${dangerous_cli_bin}/codex"
    cat >"${dangerous_cli_bin}/rm" <<EOF
#!${real_bash}
printf '%s\n' "\$*" >>"$remove_log"
exit 0
EOF
    chmod +x "${dangerous_cli_bin}/rm"

    if PATH="${dangerous_cli_bin}:$old_path" run_manage_command "$command_output" remove; then
        printf 'Assertion failed: manage.sh remove should fail closed instead of deleting a PATH codex when no install dir is configured\n' >&2
        exit 1
    fi
    if [ -s "$remove_log" ]; then
        printf 'Assertion failed: manage.sh remove should not invoke rm for a PATH codex fallback\n' >&2
        exit 1
    fi
    assert_contains "$(cat "$command_output")" "Could not find a codex binary to remove." "manage.sh remove fails closed without deleting a PATH codex"

    update_log="${temp_root}/update.log"
    cat >"${dangerous_cli_bin}/dirname" <<EOF
#!${real_bash}
printf '%s\n' "\$*" >>"$update_log"
exec "$real_dirname" "\$@"
EOF
    chmod +x "${dangerous_cli_bin}/dirname"
    cat >"${dangerous_cli_bin}/uname" <<EOF
#!${real_bash}
if [ "\${1:-}" = "-s" ]; then
    printf 'Linux\n'
    exit 0
fi
if [ "\${1:-}" = "-m" ]; then
    printf 'x86_64\n'
    exit 0
fi
printf 'Linux\n'
EOF
    chmod +x "${dangerous_cli_bin}/uname"

    if HOME="${temp_root}/update-home" PATH="${dangerous_cli_bin}:/usr/bin" run_manage_command "$command_output" update; then
        printf 'Assertion failed: manage.sh update should fail closed instead of following a PATH codex when no install dir is configured\n' >&2
        exit 1
    fi
    if grep -Fq "${dangerous_cli_bin}/codex" "$update_log"; then
        printf 'Assertion failed: manage.sh update should not resolve the PATH codex fallback\n' >&2
        exit 1
    fi
    assert_contains "$(cat "$command_output")" "Could not find an installed codex binary." "manage.sh update fails closed without following a PATH codex"

    readme="$(cat "${SCRIPT_DIR}/../README.md")"
    readme_zh="$(cat "${SCRIPT_DIR}/../README.zh.md")"

    assert_contains "$readme" "\`xixu-me/codex-manager\` provides \`manage.sh\`" "README.md uses the new repository name and entrypoint wording"
    assert_contains "$readme_zh" "\`xixu-me/codex-manager\` 提供 \`manage.sh\`" "README.zh.md uses the new repository name and entrypoint wording"
    assert_contains "$readme" './manage.sh <command> [options]' "README.md documents the command entrypoint"
    assert_contains "$readme_zh" './manage.sh <command> [options]' "README.zh.md documents the command entrypoint"
    assert_contains "$readme" 'curl -fsSL https://github.com/xixu-me/codex-manager/raw/refs/heads/main/manage.sh | bash -s -- <command>' "README.md shows the streaming example"
    assert_contains "$readme_zh" 'curl -fsSL https://github.com/xixu-me/codex-manager/raw/refs/heads/main/manage.sh | bash -s -- <command>' "README.zh.md shows the streaming example"
    assert_contains "$readme" './manage.sh install [options]' "README.md documents install"
    assert_contains "$readme" './manage.sh update [options]' "README.md documents update"
    assert_contains "$readme" './manage.sh remove [options]' "README.md documents remove"
    assert_contains "$readme_zh" './manage.sh install [options]' "README.zh.md documents install"
    assert_contains "$readme_zh" './manage.sh update [options]' "README.zh.md documents update"
    assert_contains "$readme_zh" './manage.sh remove [options]' "README.zh.md documents remove"
    assert_contains "$readme" 'macOS and Linux only' "README.md documents platform constraints"
    assert_contains "$readme" "\`x86_64\` and \`arm64\`" "README.md documents architecture constraints"
    assert_contains "$readme_zh" '仅支持 macOS 和 Linux' "README.zh.md documents platform constraints"
    assert_contains "$readme_zh" "\`x86_64\` 与 \`arm64\`" "README.zh.md documents architecture constraints"
    assert_contains "$readme" "Supported managers include \`apt-get\`, \`dnf\`, \`yum\`, \`zypper\`, and \`apk\`" "README.md documents dependency auto-install behavior"
    assert_contains "$readme_zh" "Linux 上支持的包管理器包括 \`apt-get\`、\`dnf\`、\`yum\`、\`zypper\` 和 \`apk\`" "README.zh.md documents dependency auto-install behavior"
    assert_contains "$readme" "Homebrew to install \`jq\` if it is missing" "README.md documents Homebrew fallback"
    assert_contains "$readme_zh" "缺少 \`jq\` 时可以通过 Homebrew 安装" "README.zh.md documents Homebrew fallback"
    if [[ "$readme" == *"install.sh | bash"* || "$readme_zh" == *"install.sh | bash"* ]]; then
        printf 'Assertion failed: README files should not reference install.sh bootstrap usage\n' >&2
        exit 1
    fi
    if [[ "$readme" == *"install.sh [options]"* || "$readme_zh" == *"install.sh [options]"* ]]; then
        printf 'Assertion failed: README files should not document install.sh options\n' >&2
        exit 1
    fi
    if [[ "$readme" == *"scripts/login-device.sh"* || "$readme_zh" == *"scripts/login-device.sh"* ]]; then
        printf 'Assertion failed: README files should not reference scripts/login-device.sh\n' >&2
        exit 1
    fi
    if [[ "$readme" == *"scripts/uninstall.sh"* || "$readme_zh" == *"scripts/uninstall.sh"* ]]; then
        printf 'Assertion failed: README files should not reference scripts/uninstall.sh\n' >&2
        exit 1
    fi
    if [[ "$readme" == *"codex-installer"* || "$readme_zh" == *"codex-installer"* ]]; then
        printf 'Assertion failed: README files should not use the old repository name\n' >&2
        exit 1
    fi
    
    printf 'Smoke tests passed.\n'
}

main "$@"
