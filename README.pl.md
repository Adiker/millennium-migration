# Skrypty migracji Millennium

[English](README.md)

Skrypty dla Windows i Linux tworzą oraz odtwarzają przenośny backup konfiguracji, pluginów i motywów Millennium for Steam.

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

Jeśli Steam jest zainstalowany w niestandardowym miejscu, ustaw `STEAM_PATH` przed uruchomieniem skryptu. Błędna jawna ścieżka jest odrzucana, zamiast kierować import do innej instalacji. Przed importem Steam musi być całkowicie zamknięty. Import tworzy backup stanu sprzed importu z unikalną nazwą obok wskazanego archiwum.

Skrypty sprawdzają manifest backupu, odrzucają ścieżki absolutne i ścieżki zawierające `..`, a podczas eksportu pokazują sumę SHA-256.

## Ścieżki

Skrypty odpowiadają **kodowi źródłowemu Millennium** i obsługują również ścieżki z dokumentacji. Zweryfikowano 2026-10-03 względem commitu upstream [`dd868c3`](https://github.com/SteamClientHomebrew/Millennium/commit/dd868c3c108780c4f63e9fb569a9d5a28a088a51) oraz definicji ścieżek v3.4.1.

| System | Dane | Ścieżka importu używana przez kod | Dodatkowa ścieżka importu dla zgodności |
| --- | --- | --- | --- |
| Windows | Konfiguracja | `Steam/millennium/config` | Taka sama |
| Windows | Pluginy | `Steam/millennium/plugins` | `Steam/millennium/plugin` |
| Windows | Motywy | `Steam/millennium/themes` | Taka sama |
| Linux | Konfiguracja | `${XDG_CONFIG_HOME:-~/.config}/millennium` | Taka sama |
| Linux | Pluginy | `${XDG_DATA_HOME:-~/.local/share}/millennium/plugins` | Taka sama |
| Linux | Motywy | `Steam/millennium/themes` | `Steam/steamui/skins` |

`Steam` oznacza wykrytą instalację lub `STEAM_PATH`. Na Linuksie zmienne `MILLENNIUM__CONFIG_PATH` i `MILLENNIUM__PLUGINS_PATH` nadpisują ścieżki konfiguracji i pluginów, tak jak w Millennium. Ustaw je tak samo jak przy uruchamianiu Steam. Przy nadpisaniach eksport sprawdza również ścieżki XDG, a import zapisuje konfigurację/pluginy wyłącznie do nadpisanych lokalizacji.

Tam, gdzie ścieżki kodu i dokumentacji różnią się, import zapisuje **osobne kopie** do obu lokalizacji, zastępując każdą importowaną kategorię po utworzeniu backupu. Dzięki temu bieżący skaner widzi motywy na Linuksie, a loader widzi pluginy na Windows; zachowany jest też układ dokumentowany dla wersji, które go używają. Kopie są synchronizowane tylko podczas importu; późniejsze zmiany w Millennium nie są automatycznie odzwierciedlane. Brak kategorii w archiwum pozostawia jej katalogi docelowe bez zmian.

Eksport sprawdza najpierw ścieżki kodu, następnie dokumentowane i starsze. Przy powtórzonej nazwie najwyższego poziomu (także całego katalogu dodatku) wygrywa pierwsze źródło; wersje dodatku nie są mieszane. Unikalne dodatki z lokalizacji zapasowych są uwzględniane. Pozostałe źródła eksportu:

- Linux, konfiguracja: `Steam/millennium/config`; pluginy: `Steam/millennium/plugins`, `Steam/millennium/plugin`, `Steam/plugins`; motywy: ścieżka dokumentowana, `${XDG_DATA_HOME:-~/.local/share}/millennium/themes`, `~/.millennium/themes`.
- Windows, pluginy: `Steam/millennium/plugin`, `Steam/plugins`; motywy: `Steam/steamui/skins`.
- Oba systemy: starsze `Steam/ext/config.json` i `Steam/ext/quickcss.css`, mapowane na `config/config.json` i `config/quick.css` tylko wtedy, gdy odpowiedniego pliku konfiguracji nie zebrano wcześniej.

Zachowywany jest cały katalog konfiguracji, w tym `config.json` (aktywny motyw, opcje motywów, włączone pluginy i ich ustawienia), `quick.css` oraz starszy `themes.json`. Millennium samodzielnie migruje swój schemat konfiguracji. Przenośny format archiwum `millennium-user-backup-v1` pozostaje bez zmian — dotychczasowe backupy nadal można importować.

Źródła zachowania: [`environment.cc`](https://github.com/SteamClientHomebrew/Millennium/blob/dd868c3c108780c4f63e9fb569a9d5a28a088a51/src/system/environment.cc), [`filesystem.cc`](https://github.com/SteamClientHomebrew/Millennium/blob/dd868c3c108780c4f63e9fb569a9d5a28a088a51/src/system/filesystem.cc), [`scan.cc`](https://github.com/SteamClientHomebrew/Millennium/blob/dd868c3c108780c4f63e9fb569a9d5a28a088a51/src/bindings/scan.cc), [`plugin_mgr.cc`](https://github.com/SteamClientHomebrew/Millennium/blob/dd868c3c108780c4f63e9fb569a9d5a28a088a51/src/bindings/plugin_mgr.cc), [`entry_point.cc`](https://github.com/SteamClientHomebrew/Millennium/blob/dd868c3c108780c4f63e9fb569a9d5a28a088a51/src/bindings/entry_point.cc) i [`windows.cc`](https://github.com/SteamClientHomebrew/Millennium/blob/dd868c3c108780c4f63e9fb569a9d5a28a088a51/src/platform/windows.cc). Przy zmianie układu upstream sprawdź skaner, instalator, loader i inicjalizację środowiska przed zmianą tabeli oraz testów.

## Zakres backupu

Backup obejmuje konfigurację użytkownika Millennium i pliki dodatków. Millennium należy zainstalować osobno na systemie docelowym. Biblioteki wykonawcze, logi, raporty awarii, środowiska Python i profil Chromium Steam (`config/htmlcache`) nie są migrowane. Przykładowo rozszerzenia Chrome zainstalowane przez Extendium i ustawienia ich profilu wymagają osobnej migracji — przeniesienie pluginu Millennium nie odtwarza tego stanu. Binaria pluginów zależne od systemu oraz ścieżki absolutne w plikach dodatków mogą wymagać ponownej instalacji lub dostosowania na docelowym systemie.

## Testy

Testy używają wyłącznie tymczasowych katalogów — nie wymagają zainstalowanego Steam ani Millennium. Obejmują ścieżki kodu i dokumentacji, pierwszeństwo duplikatów, starszą konfigurację/QuickCSS, nadpisania na Linuksie, backup przed importem, błędne ścieżki Steam i uszkodzone archiwa:

```powershell
.\tests\test-windows.ps1
```

```bash
bash ./tests/test-linux.sh
```

CI dodatkowo eksportuje na Windows i importuje to archiwum na Linuksie oraz eksportuje na Linuksie i importuje na Windows w PowerShell 7 i Windows PowerShell 5.1.

Dokumentacja: [Millennium File System Structure](https://docs.steambrew.app/users/getting-started/structure).
