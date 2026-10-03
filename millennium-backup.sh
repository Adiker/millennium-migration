#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

MODE="${1:-}"
ARCHIVE="${2:-}"
TEMP_DIRS=()

usage() {
    cat <<'USAGE'
Użycie:
  ./millennium-backup.sh export [backup.tar.gz]
  ./millennium-backup.sh import <backup.tar.gz>
USAGE
}

die() {
    printf 'BŁĄD: %s\n' "$*" >&2
    exit 1
}

log() {
    printf '%s\n' "$*"
}

cleanup() {
    local p

    for p in "${TEMP_DIRS[@]:-}"; do
        [[ -n "$p" ]] && rm -rf -- "$p"
    done
}

trap cleanup EXIT

new_temp_dir() {
    local __var="$1"
    local p

    p="$(mktemp -d "${TMPDIR:-/tmp}/millennium-backup.XXXXXXXX")"
    TEMP_DIRS+=("$p")

    printf -v "$__var" '%s' "$p"
}

if [[ "$MODE" != "export" && "$MODE" != "import" ]]; then
    usage
    exit 2
fi

command -v tar >/dev/null 2>&1 ||
    die "Brak programu tar."

steam_running() {
    pgrep -x steam >/dev/null 2>&1 ||
        pgrep -f '(^|/)steam( |$)' >/dev/null 2>&1
}

detect_steam_root() {
    local candidates=()
    local d

    [[ -n "${STEAM_PATH:-}" ]] &&
        candidates+=("$STEAM_PATH")

    if [[ -z "${STEAM_PATH:-}" ]]; then
        candidates+=(
            "$HOME/.steam/steam"
            "$HOME/.local/share/Steam"
            "$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam"
        )
    fi

    for d in "${candidates[@]}"; do
        [[ -n "$d" && -d "$d" ]] || continue

        if [[
            -d "$d/steamui" ||
            -d "$d/steamapps" ||
            -e "$d/ubuntu12_32/steam"
        ]]; then
            printf '%s\n' "$d"
            return 0
        fi
    done

    return 1
}

STEAM_ROOT="$(detect_steam_root)" ||
    die "Nie znalazłem katalogu Steam. Ustaw np. STEAM_PATH=\"$HOME/.local/share/Steam\"."

DATA_ROOT="${XDG_DATA_HOME:-$HOME/.local/share}/millennium"
CONFIG_ROOT="${XDG_CONFIG_HOME:-$HOME/.config}/millennium"
MILLENNIUM_ROOT="$STEAM_ROOT/millennium"

#
# Ścieżki z kodu upstream (environment.cc, filesystem.cc, scan.cc).
# Linux respektuje nadpisania MILLENNIUM__CONFIG_PATH / __PLUGINS_PATH.
# Dokumentowane ścieżki pozostają źródłami i celami kompatybilności.
#
CONFIG_TARGET="${MILLENNIUM__CONFIG_PATH:-$CONFIG_ROOT}"
PLUGIN_TARGET="${MILLENNIUM__PLUGINS_PATH:-$DATA_ROOT/plugins}"
THEME_TARGET="$MILLENNIUM_ROOT/themes"
THEME_COMPAT_TARGET="$STEAM_ROOT/steamui/skins"

CONFIG_SOURCES=(
    "$CONFIG_TARGET"
    "$CONFIG_ROOT"
    "$MILLENNIUM_ROOT/config"
)

PLUGIN_SOURCES=(
    "$PLUGIN_TARGET"
    "$DATA_ROOT/plugins"
    "$MILLENNIUM_ROOT/plugins"
    "$MILLENNIUM_ROOT/plugin"
    "$STEAM_ROOT/plugins"
)

THEME_SOURCES=(
    "$MILLENNIUM_ROOT/themes"
    "$THEME_COMPAT_TARGET"
    "$DATA_ROOT/themes"
    "$HOME/.millennium/themes"
)

LEGACY_CONFIG_JSON="$STEAM_ROOT/ext/config.json"
LEGACY_QUICK_CSS="$STEAM_ROOT/ext/quickcss.css"

add_legacy_config() {
    local dest="$1"
    local name src

    for name in config.json quick.css; do
        src="$LEGACY_CONFIG_JSON"
        [[ "$name" == quick.css ]] && src="$LEGACY_QUICK_CSS"
        if [[ -f "$src" && ! -e "$dest/$name" && ! -L "$dest/$name" ]]; then
            mkdir -p -- "$dest"
            cp -a -- "$src" "$dest/$name"
        fi
    done
}

merge_sources() {
    local dest="$1"
    local label="$2"

    shift 2

    local src
    local item
    local name
    local -A seen=()

    for src in "$@"; do
        [[ -z "${seen[$src]:-}" ]] || continue
        seen[$src]=1
        [[ -d "$src" ]] || continue

        mkdir -p -- "$dest"

        while IFS= read -r -d '' item; do
            name="${item##*/}"

            if [[ -e "$dest/$name" || -L "$dest/$name" ]]; then
                log "  [=] $label/$name już zebrane; pomijam duplikat z: $src"
                continue
            fi

            cp -a -- "$item" "$dest/"
        done < <(
            find "$src" \
                -mindepth 1 \
                -maxdepth 1 \
                -print0
        )
    done
}

write_manifest() {
    local stage="$1"

    cat >"$stage/manifest.txt" <<EOF
format=millennium-user-backup-v1
source_os=linux
created_utc=$(date -u +'%Y-%m-%dT%H:%M:%SZ')
EOF
}

has_user_data() {
    local p

    for p in \
        "${CONFIG_SOURCES[@]}" \
        "${PLUGIN_SOURCES[@]}" \
        "${THEME_SOURCES[@]}"
    do
        has_directory_entries "$p" && return 0
    done

    [[ -f "$LEGACY_CONFIG_JSON" || -f "$LEGACY_QUICK_CSS" ]] && return 0

    return 1
}

has_directory_entries() {
    local dir="$1"

    [[ -d "$dir" ]] || return 1
    [[ -n "$(find "$dir" -mindepth 1 -print -quit)" ]]
}

export_backup() {
    local out="$1"
    local stage

    new_temp_dir stage

    write_manifest "$stage"

    merge_sources \
        "$stage/config" \
        "config" \
        "${CONFIG_SOURCES[@]}"

    add_legacy_config "$stage/config"

    merge_sources \
        "$stage/plugins" \
        "plugins" \
        "${PLUGIN_SOURCES[@]}"

    merge_sources \
        "$stage/themes" \
        "themes" \
        "${THEME_SOURCES[@]}"

    if ! has_directory_entries "$stage/config" &&
        ! has_directory_entries "$stage/plugins" &&
        ! has_directory_entries "$stage/themes"; then
        die "Nie znalazłem żadnych danych użytkownika Millennium do eksportu."
    fi

    mkdir -p -- "$(dirname -- "$out")"
    rm -f -- "$out"

    tar \
        -C "$stage" \
        -czf "$out" \
        .

    log ""
    log "Backup zapisany:"
    log "  $out"

    if command -v sha256sum >/dev/null 2>&1; then
        log ""
        log "SHA256:"
        sha256sum -- "$out"
    fi
}

validate_archive() {
    local archive="$1"
    local entry
    local normalized

    [[ -f "$archive" ]] ||
        die "Nie ma pliku: $archive"

    local listing_dir
    local listing_file

    new_temp_dir listing_dir
    listing_file="$listing_dir/entries.txt"

    tar -tzf "$archive" >"$listing_file" ||
        die "Nie udało się odczytać archiwum."

    while IFS= read -r entry; do
        normalized="${entry//\\//}"

        [[ "$normalized" != /* ]] ||
            die "Archiwum zawiera ścieżkę absolutną: $entry"

        [[ ! "$normalized" =~ ^[A-Za-z]: ]] ||
            die "Archiwum zawiera ścieżkę dyskową: $entry"

        [[ ! "$normalized" =~ (^|/)\.\.(/|$) ]] ||
            die "Archiwum zawiera niedozwolone '..': $entry"

    done <"$listing_file"
}

replace_dir() {
    local src="$1"
    local dst="$2"
    local label="$3"

    [[ -d "$src" ]] ||
        return 0

    log "  -> $label: $dst"

    rm -rf -- "$dst"

    mkdir -p -- "$(dirname -- "$dst")"

    cp -a -- "$src" "$dst"
}

import_backup() {
    local archive="$1"
    local stage
    local archive_dir
    local prebackup

    validate_archive "$archive"

    if steam_running; then
        die "Steam działa. Zamknij go całkowicie przed importem."
    fi

    new_temp_dir stage

    tar \
        -C "$stage" \
        -xzf "$archive"

    [[ -f "$stage/manifest.txt" ]] ||
        die "Brak manifest.txt — to nie wygląda na backup z tego skryptu."

    grep -qx \
        'format=millennium-user-backup-v1' \
        "$stage/manifest.txt" ||
        die "Nieobsługiwany format backupu."

    archive_dir="$(
        cd -- "$(dirname -- "$archive")"
        pwd -P
    )"

    if has_user_data; then
        prebackup="$archive_dir/millennium-preimport-linux-$(date +'%Y%m%d-%H%M%S')-${stage##*.}.tar.gz"

        log "Tworzę backup stanu sprzed importu..."

        export_backup "$prebackup"

        log ""
        log "Backup sprzed importu:"
        log "  $prebackup"
        log ""
    else
        log "Brak istniejących danych Millennium — pomijam backup przed importem."
    fi

    log "Importuję:"

    replace_dir \
        "$stage/config" \
        "$CONFIG_TARGET" \
        "config"

    replace_dir \
        "$stage/plugins" \
        "$PLUGIN_TARGET" \
        "plugins"

    replace_dir \
        "$stage/themes" \
        "$THEME_TARGET" \
        "themes"

    replace_dir \
        "$stage/themes" \
        "$THEME_COMPAT_TARGET" \
        "themes (zgodność z dokumentacją)"

    log ""
    log "Import zakończony."
    log "Uruchom ponownie Steam."
}

case "$MODE" in
    export)
        if steam_running; then
            log "UWAGA: Steam działa."
            log "Eksport wykonam, ale najpewniejszy backup jest po jego zamknięciu."
            log ""
        fi

        if [[ -z "$ARCHIVE" ]]; then
            ARCHIVE="$PWD/millennium-backup-linux-$(date +'%Y%m%d-%H%M%S').tar.gz"
        elif [[ "$ARCHIVE" != /* ]]; then
            ARCHIVE="$PWD/$ARCHIVE"
        fi

        export_backup "$ARCHIVE"
        ;;

    import)
        [[ -n "$ARCHIVE" ]] ||
            die "Podaj plik backupu do importu."

        [[ "$ARCHIVE" == /* ]] ||
            ARCHIVE="$PWD/$ARCHIVE"

        import_backup "$ARCHIVE"
        ;;
esac
