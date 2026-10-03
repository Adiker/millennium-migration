# Millennium Migration Scripts

[Polski](README.pl.md)

Cross-platform scripts for creating and restoring a portable backup of Millennium for Steam configuration, plugins, and themes between Windows and Linux.

## Usage

Windows PowerShell:

```powershell
.\millennium-backup.ps1 export [backup.tar.gz]
.\millennium-backup.ps1 import <backup.tar.gz>
```

Linux:

```bash
chmod +x ./millennium-backup.sh
./millennium-backup.sh export [backup.tar.gz]
./millennium-backup.sh import <backup.tar.gz>
```

If Steam is installed in a non-standard location, set `STEAM_PATH` before running the script. An invalid explicit path is rejected instead of falling back to another installation. Steam must be fully closed before importing. The import creates a uniquely named backup of the pre-import state next to the selected archive.

The scripts validate the backup manifest, reject absolute paths and paths containing `..`, and print a SHA-256 checksum during export.

## Paths

The scripts follow the **Millennium source code**, while also supporting the paths in the documentation. Verified on 2026-10-03 against upstream commit [`dd868c3`](https://github.com/SteamClientHomebrew/Millennium/commit/dd868c3c108780c4f63e9fb569a9d5a28a088a51) and the v3.4.1 path definitions.

| Platform | Data | Runtime import path | Additional compatibility import path |
| --- | --- | --- | --- |
| Windows | Configuration | `Steam/millennium/config` | Same as runtime |
| Windows | Plugins | `Steam/millennium/plugins` | `Steam/millennium/plugin` |
| Windows | Themes | `Steam/millennium/themes` | Same as runtime |
| Linux | Configuration | `${XDG_CONFIG_HOME:-~/.config}/millennium` | Same as runtime |
| Linux | Plugins | `${XDG_DATA_HOME:-~/.local/share}/millennium/plugins` | Same as runtime |
| Linux | Themes | `Steam/millennium/themes` | `Steam/steamui/skins` |

`Steam` means the detected installation or `STEAM_PATH`. On Linux, `MILLENNIUM__CONFIG_PATH` and `MILLENNIUM__PLUGINS_PATH` override the configuration and plugin paths, just as they do in Millennium. Set these to the same values used to launch Steam. With overrides, export also checks the XDG paths; import writes configuration/plugins only to the overridden destinations.

Import writes **separate copies** to both runtime and compatibility paths where they differ, replacing each imported category after creating the pre-import backup. This keeps Linux themes visible to the current scanner and Windows plugins visible to the current loader, while retaining the documented layout for versions that use it. The copies are synchronized only during import; later changes made by Millennium are not mirrored automatically. Missing categories in an archive leave their destinations untouched.

Export checks runtime paths first, then documented and legacy paths. A duplicate top-level name (including an entire addon directory) uses the first source; addon versions are not mixed. Unique addons from fallback locations are included. Other export sources are:

- Linux configuration: `Steam/millennium/config`; plugins: `Steam/millennium/plugins`, `Steam/millennium/plugin`, `Steam/plugins`; themes: the documented path, `${XDG_DATA_HOME:-~/.local/share}/millennium/themes`, `~/.millennium/themes`.
- Windows plugins: `Steam/millennium/plugin`, `Steam/plugins`; themes: `Steam/steamui/skins`.
- Both platforms: legacy `Steam/ext/config.json` and `Steam/ext/quickcss.css`, mapped to `config/config.json` and `config/quick.css` only when the corresponding configuration file has not already been collected.

The whole configuration directory is preserved, including `config.json` (active theme, theme options, enabled plugins and plugin settings), `quick.css`, and legacy `themes.json`. Millennium handles its own configuration schema migrations. The portable `millennium-user-backup-v1` archive format is unchanged, so existing backups remain importable.

Runtime references: [`environment.cc`](https://github.com/SteamClientHomebrew/Millennium/blob/dd868c3c108780c4f63e9fb569a9d5a28a088a51/src/system/environment.cc), [`filesystem.cc`](https://github.com/SteamClientHomebrew/Millennium/blob/dd868c3c108780c4f63e9fb569a9d5a28a088a51/src/system/filesystem.cc), [`scan.cc`](https://github.com/SteamClientHomebrew/Millennium/blob/dd868c3c108780c4f63e9fb569a9d5a28a088a51/src/bindings/scan.cc), [`plugin_mgr.cc`](https://github.com/SteamClientHomebrew/Millennium/blob/dd868c3c108780c4f63e9fb569a9d5a28a088a51/src/bindings/plugin_mgr.cc), [`entry_point.cc`](https://github.com/SteamClientHomebrew/Millennium/blob/dd868c3c108780c4f63e9fb569a9d5a28a088a51/src/bindings/entry_point.cc), and [`windows.cc`](https://github.com/SteamClientHomebrew/Millennium/blob/dd868c3c108780c4f63e9fb569a9d5a28a088a51/src/platform/windows.cc). When upstream changes the layout, check the scanner/installer/loader and environment setup before updating the table and tests.

## Backup scope

This is a backup of Millennium user configuration and addon files. Install Millennium separately on the destination system. Runtime libraries, logs, crashes, Python environments and Steam's Chromium profile (`config/htmlcache`) are not migrated. For example, Extendium's installed Chrome extensions and their profile settings need a separate migration; copying its Millennium plugin does not restore that state. Platform-specific plugin binaries and absolute paths in addon files may require reinstallation or adjustment on the destination OS.

## Tests

The tests use temporary fixture directories only; they do not require Steam or Millennium to be installed. They cover runtime and documented paths, duplicate precedence, legacy configuration/QuickCSS, Linux overrides, pre-import backups, invalid Steam paths and malformed archives:

```powershell
.\tests\test-windows.ps1
```

```bash
bash ./tests/test-linux.sh
```

CI also exports on Windows and imports that archive on Linux, and exports on Linux and imports on Windows with both PowerShell 7 and Windows PowerShell 5.1.

Documentation reference: [Millennium File System Structure](https://docs.steambrew.app/users/getting-started/structure).
