# Millennium migration scripts

Skrypty tworzą i odtwarzają przenośny backup konfiguracji, pluginów i motywów Millennium for Steam między Windows i Linux.

## Użycie

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

Jeżeli Steam jest zainstalowany w niestandardowym miejscu, ustaw `STEAM_PATH` przed uruchomieniem skryptu. Przed importem Steam musi być całkowicie zamknięty. Import tworzy backup stanu sprzed importu w katalogu wskazanego archiwum.

Skrypty sprawdzają manifest backupu, odrzucają ścieżki absolutne i ścieżki zawierające `..`, a podczas eksportu pokazują sumę SHA-256.

## Ścieżki

Ścieżki odpowiadają aktualnej dokumentacji Millennium:

- Windows: `Steam/millennium/config`, `Steam/millennium/plugin`, `Steam/millennium/themes`
- Linux: `~/.config/millennium`, `~/.local/share/millennium/plugins`, `Steam/steamui/skins`

Eksport uwzględnia również starsze lokalizacje pluginów i konfiguracji, jeśli istnieją.

## Testy

Testy używają wyłącznie tymczasowych, sztucznych katalogów — nie wymagają zainstalowanego Millennium ani Steam:

```powershell
.\tests\test-windows.ps1
```

```bash
bash ./tests/test-linux.sh
```

Źródło ścieżek: [Millennium File System Structure](https://docs.steambrew.app/users/getting-started/structure).
