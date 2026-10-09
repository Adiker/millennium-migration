#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
script_path="$script_dir/../millennium-backup.sh"
fixture_root="$(mktemp -d "${TMPDIR:-/tmp}/millennium-test.XXXXXXXX")"

# Steam on the host and inherited Millennium overrides must not affect fixtures.
mkdir -p "$fixture_root/bin"
printf '#!/usr/bin/env bash\nexit 1\n' >"$fixture_root/bin/pgrep"
chmod +x "$fixture_root/bin/pgrep"
export PATH="$fixture_root/bin:$PATH"
unset MILLENNIUM__CONFIG_PATH MILLENNIUM__PLUGINS_PATH

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
theme_root="$steam_root/millennium/themes"
theme_compat_root="$steam_root/steamui/skins"

mkdir -p -- \
    "$steam_root/steamapps" \
    "$config_root" \
    "$plugin_root" \
    "$theme_root/Runtime Theme" \
    "$theme_compat_root/Runtime Theme" \
    "$theme_compat_root/Documented Theme" \
    "$steam_root/millennium/plugin/Legacy Plugin"

printf '%s' '{"from":"linux"}' >"$config_root/settings.json"
printf '%s' 'linux-plugin' >"$plugin_root/current.txt"
printf '%s' '{"themes":{"activeTheme":"Runtime Theme"},"plugins":{"enabledPlugins":["example"]}}' >"$config_root/config.json"
printf '%s' 'body { color: red; }' >"$config_root/quick.css"
printf '%s' '{"name":"Runtime Theme"}' >"$theme_root/Runtime Theme/skin.json"
printf '%s' 'linux-theme' >"$theme_root/Runtime Theme/style.css"
printf '%s' 'old-theme' >"$theme_compat_root/Runtime Theme/style.css"
printf '%s' '{"name":"Documented Theme"}' >"$theme_compat_root/Documented Theme/skin.json"
printf '%s' 'legacy-plugin' >"$steam_root/millennium/plugin/Legacy Plugin/plugin.lua"
mkdir -p "$plugin_root/example"
printf '%s' '{"name":"example"}' >"$plugin_root/example/plugin.json"
printf '%s' 'return {}' >"$plugin_root/example/main.lua"
printf '%s' 'hidden-data' >"$plugin_root/example/.settings"

bash "$script_path" export "$archive"
[[ -f "$archive" ]] || fail 'Eksport nie utworzył archiwum.'
tar -tzf "$archive" | grep -Fq './manifest.txt' || fail 'Archiwum nie zawiera manifestu.'
tar -tzf "$archive" | grep -Fq './plugins/current.txt' || fail 'Archiwum nie zawiera pluginu.'
tar -tzf "$archive" | grep -Fq './themes/Runtime Theme/skin.json' || fail 'Archiwum nie zawiera motywu.'

printf '%s' 'stale' >"$config_root/stale.txt"
printf '%s' 'stale' >"$plugin_root/stale.txt"
printf '%s' 'stale' >"$theme_root/stale.css"
printf '%s' 'stale' >"$theme_compat_root/stale.css"

bash "$script_path" import "$archive"
assert_file_text "$config_root/settings.json" '{"from":"linux"}'
assert_file_text "$plugin_root/current.txt" 'linux-plugin'
for target in "$theme_root" "$theme_compat_root"; do
    assert_file_text "$target/Runtime Theme/style.css" 'linux-theme'
    assert_file_text "$target/Documented Theme/skin.json" '{"name":"Documented Theme"}'
    [[ ! -e "$target/stale.css" ]] || fail 'Import nie usunął starego motywu.'
done
assert_file_text "$config_root/config.json" '{"themes":{"activeTheme":"Runtime Theme"},"plugins":{"enabledPlugins":["example"]}}'
assert_file_text "$config_root/quick.css" 'body { color: red; }'
assert_file_text "$plugin_root/Legacy Plugin/plugin.lua" 'legacy-plugin'
assert_file_text "$plugin_root/example/.settings" 'hidden-data'
[[ ! -e "$theme_root/stale.css" ]] || fail 'Import nie usunął starego motywu.'
prebackups=("$fixture_root"/millennium-preimport-linux-*.tar.gz)
[[ -f "${prebackups[0]}" ]] || fail 'Brak backupu przed importem.'
mkdir "$fixture_root/prebackup"
tar -xzf "${prebackups[0]}" -C "$fixture_root/prebackup"
assert_file_text "$fixture_root/prebackup/config/stale.txt" 'stale'
assert_file_text "$fixture_root/prebackup/themes/stale.css" 'stale'

# A real Windows export supplied by CI can also be restored by Bash.
if [[ -n "${1:-}" ]]; then
    bash "$script_path" import "$1"
    assert_file_text "$config_root/config.json" '{"themes":{"activeTheme":"Portable Theme"},"plugins":{"enabledPlugins":["portable"]}}'
    assert_file_text "$config_root/quick.css" 'portable-css'
    assert_file_text "$plugin_root/portable/plugin.json" '{"name":"portable"}'
    assert_file_text "$theme_root/Portable Theme/skin.json" '{"name":"Portable Theme"}'
    assert_file_text "$theme_compat_root/Portable Theme/skin.json" '{"name":"Portable Theme"}'
fi

corrupt_archive="$fixture_root/corrupt.tar.gz"
printf '%s' 'not a tar archive' >"$corrupt_archive"
if bash "$script_path" import "$corrupt_archive" >/dev/null 2>&1; then
    fail 'Import uszkodzonego archiwum powinien się nie udać.'
fi

rm -rf -- "$config_home/millennium" "$data_home/millennium" "$steam_root/steamui" "$steam_root/millennium"

# A documentation-only installation must be found even without a runtime tree.
mkdir -p "$theme_compat_root/Documented Theme"
printf '%s' '{"name":"Documented Theme"}' >"$theme_compat_root/Documented Theme/skin.json"
bash "$script_path" export "$archive"
bash "$script_path" import "$archive"
assert_file_text "$theme_root/Documented Theme/skin.json" '{"name":"Documented Theme"}'
rm -rf "$steam_root/steamui" "$steam_root/millennium"

# Flat legacy config and QuickCSS map to the names read by current Millennium.
mkdir -p "$steam_root/ext"
printf '%s' 'legacy-config' >"$steam_root/ext/config.json"
printf '%s' 'legacy-css' >"$steam_root/ext/quickcss.css"
bash "$script_path" export "$archive"
bash "$script_path" import "$archive"
assert_file_text "$config_root/config.json" 'legacy-config'
assert_file_text "$config_root/quick.css" 'legacy-css'
rm -rf "$steam_root/ext" "$config_root"

# Runtime overrides take precedence over XDG/documented sources.
export MILLENNIUM__CONFIG_PATH="$fixture_root/custom config"
export MILLENNIUM__PLUGINS_PATH="$fixture_root/custom plugins"
mkdir -p "$MILLENNIUM__CONFIG_PATH" "$MILLENNIUM__PLUGINS_PATH" "$config_root" "$plugin_root"
printf '%s' 'custom-config' >"$MILLENNIUM__CONFIG_PATH/config.json"
printf '%s' 'documented-config' >"$config_root/config.json"
printf '%s' 'custom-plugin' >"$MILLENNIUM__PLUGINS_PATH/plugin.txt"
printf '%s' 'documented-plugin' >"$plugin_root/plugin.txt"
bash "$script_path" export "$archive"
printf '%s' 'modified' >"$MILLENNIUM__CONFIG_PATH/config.json"
bash "$script_path" import "$archive"
assert_file_text "$MILLENNIUM__CONFIG_PATH/config.json" 'custom-config'
assert_file_text "$MILLENNIUM__PLUGINS_PATH/plugin.txt" 'custom-plugin'
assert_file_text "$config_root/config.json" 'documented-config'
rm -rf "$MILLENNIUM__CONFIG_PATH" "$MILLENNIUM__PLUGINS_PATH" "$config_root" "$data_home/millennium"
unset MILLENNIUM__CONFIG_PATH MILLENNIUM__PLUGINS_PATH

# Invalid explicit Steam paths must not fall back to a different installation.
if STEAM_PATH="$fixture_root/missing" bash "$script_path" import "$archive" >/dev/null 2>&1; then
    fail 'Nieprawidłowe STEAM_PATH nie może zostać pominięte.'
fi

empty_archive="$fixture_root/empty.tar.gz"
if bash "$script_path" export "$empty_archive" >/dev/null 2>&1; then
    fail 'Eksport pustej instalacji powinien się nie udać.'
fi

# Portable fixture exported for the Windows import job.
mkdir -p "$config_root" "$plugin_root/portable" "$theme_root/Portable Theme"
printf '%s' '{"themes":{"activeTheme":"Portable Theme"},"plugins":{"enabledPlugins":["portable"]}}' >"$config_root/config.json"
printf '%s' 'portable-css' >"$config_root/quick.css"
printf '%s' '{"name":"portable"}' >"$plugin_root/portable/plugin.json"
printf '%s' '{"name":"Portable Theme"}' >"$theme_root/Portable Theme/skin.json"
if [[ -n "${CROSS_EXPORT_ARCHIVE:-}" ]]; then
    bash "$script_path" export "$CROSS_EXPORT_ARCHIVE"
fi

printf '%s\n' 'Linux tests: PASS'
