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

If Steam is installed in a non-standard location, set `STEAM_PATH` before running the script. Steam must be fully closed before importing. The import creates a backup of the pre-import state next to the selected archive.

The scripts validate the backup manifest, reject absolute paths and paths containing `..`, and print a SHA-256 checksum during export.

## Paths

The paths follow the current Millennium documentation:

- Windows: `Steam/millennium/config`, `Steam/millennium/plugin`, `Steam/millennium/themes`
- Linux: `~/.config/millennium`, `~/.local/share/millennium/plugins`, `Steam/steamui/skins`

Exports also include older plugin and configuration locations when they exist.

## Tests

The tests use temporary fixture directories only; they do not require Steam or Millennium to be installed:

```powershell
.\tests\test-windows.ps1
```

```bash
bash ./tests/test-linux.sh
```

Path reference: [Millennium File System Structure](https://docs.steambrew.app/users/getting-started/structure).
