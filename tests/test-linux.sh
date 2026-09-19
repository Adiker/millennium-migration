#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
script_path="$script_dir/../millennium-backup.sh"
fixture_root="$(mktemp -d "${TMPDIR:-/tmp}/millennium-test.XXXXXXXX")"

cleanup() {
    rm -rf -- "$fixture_root"
}
trap cleanup EXIT

fail() {
    printf 'ASSERTION FAILED: %s\n' "$*" >&2
    exit 1
}

assert_file_text() {
    local path="$1"
    local expected="$2"
    [[ -f "$path" ]] || fail "Brak pliku: $path"
    [[ "$(<"$path")" == "$expected" ]] || fail "Nieprawidłowa zawartość: $path"
}

home="$fixture_root/home"
data_home="$fixture_root/data"
config_home="$fixture_root/config"
steam_root="$fixture_root/Steam"
archive="$fixture_root/backup.tar.gz"

export HOME="$home"
export XDG_DATA_HOME="$data_home"
export XDG_CONFIG_HOME="$config_home"
export STEAM_PATH="$steam_root"

config_root="$config_home/millennium"
plugin_root="$data_home/millennium/plugins"
theme_root="$steam_root/steamui/skins"

mkdir -p -- \
    "$steam_root/steamapps" \
    "$config_root" \
    "$plugin_root" \
    "$theme_root"

printf '%s' '{"from":"linux"}' >"$config_root/settings.json"
printf '%s' 'linux-plugin' >"$plugin_root/current.txt"
printf '%s' 'linux-theme' >"$theme_root/dark.css"

bash "$script_path" export "$archive"
[[ -f "$archive" ]] || fail 'Eksport nie utworzył archiwum.'
tar -tzf "$archive" | grep -Fq './manifest.txt' || fail 'Archiwum nie zawiera manifestu.'
tar -tzf "$archive" | grep -Fq './plugins/current.txt' || fail 'Archiwum nie zawiera pluginu.'
tar -tzf "$archive" | grep -Fq './themes/dark.css' || fail 'Archiwum nie zawiera motywu.'

printf '%s' 'stale' >"$config_root/stale.txt"
printf '%s' 'stale' >"$plugin_root/stale.txt"
printf '%s' 'stale' >"$theme_root/stale.css"

bash "$script_path" import "$archive"
assert_file_text "$config_root/settings.json" '{"from":"linux"}'
assert_file_text "$plugin_root/current.txt" 'linux-plugin'
assert_file_text "$theme_root/dark.css" 'linux-theme'
[[ ! -e "$theme_root/stale.css" ]] || fail 'Import nie usunął starego motywu.'
[[ ! -d "$steam_root/millennium/themes" ]] || fail 'Import użył nieprawidłowej ścieżki motywów.'

corrupt_archive="$fixture_root/corrupt.tar.gz"
printf '%s' 'not a tar archive' >"$corrupt_archive"
if bash "$script_path" import "$corrupt_archive" >/dev/null 2>&1; then
    fail 'Import uszkodzonego archiwum powinien się nie udać.'
fi

rm -rf -- "$config_home/millennium" "$data_home/millennium" "$steam_root/steamui"
empty_archive="$fixture_root/empty.tar.gz"
if bash "$script_path" export "$empty_archive" >/dev/null 2>&1; then
    fail 'Eksport pustej instalacji powinien się nie udać.'
fi

printf '%s\n' 'Linux tests: PASS'
