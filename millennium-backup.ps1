[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateSet('export', 'import')]
    [string]$Mode,

    [Parameter(Position = 1)]
    [string]$Archive
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($env:OS -ne 'Windows_NT') {
    throw 'Ten skrypt jest przeznaczony dla Windows.'
}

function Write-Log {
    param([string]$Message)
    Write-Host $Message
}

function Convert-ToFullPath {
    param([Parameter(Mandatory)][string]$Path)

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return [System.IO.Path]::GetFullPath($Path)
    }

    return [System.IO.Path]::GetFullPath(
        (Join-Path (Get-Location).Path $Path)
    )
}

function Get-SteamRoot {
    $candidates = [System.Collections.Generic.List[string]]::new()

    if ($env:STEAM_PATH) {
        $candidates.Add($env:STEAM_PATH)
    }

    foreach ($registryPath in @(
        'HKCU:\Software\Valve\Steam',
        'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam',
        'HKLM:\SOFTWARE\Valve\Steam'
    )) {
        try {
            $props = Get-ItemProperty -LiteralPath $registryPath -ErrorAction Stop

            if ($props.SteamPath) {
                $candidates.Add([string]$props.SteamPath)
            }

            if ($props.InstallPath) {
                $candidates.Add([string]$props.InstallPath)
            }
        }
        catch {
            # Brak danego klucza jest normalny.
        }
    }

    $pf86 = [Environment]::GetEnvironmentVariable('ProgramFiles(x86)')
    $pf   = [Environment]::GetEnvironmentVariable('ProgramFiles')

    if ($pf86) {
        $candidates.Add((Join-Path $pf86 'Steam'))
    }

    if ($pf) {
        $candidates.Add((Join-Path $pf 'Steam'))
    }

    foreach ($candidate in ($candidates | Select-Object -Unique)) {
        if (
            (Test-Path -LiteralPath $candidate -PathType Container) -and
            (
                (Test-Path -LiteralPath (Join-Path $candidate 'steam.exe')) -or
                (Test-Path -LiteralPath (Join-Path $candidate 'steamapps') -PathType Container)
            )
        ) {
            return [System.IO.Path]::GetFullPath($candidate)
        }
    }

    throw @'
Nie znalazłam katalogu Steam.
Możesz ustawić go ręcznie:

$env:STEAM_PATH = 'D:\Steam'
.\millennium-backup.ps1 export
'@
}

function Test-SteamRunning {
    return $null -ne (
        Get-Process -Name 'steam' -ErrorAction SilentlyContinue |
        Select-Object -First 1
    )
}

function New-TempDirectory {
    $path = Join-Path `
        ([System.IO.Path]::GetTempPath()) `
        ('millennium-backup-' + [guid]::NewGuid().ToString('N'))

    New-Item -ItemType Directory -Path $path -Force | Out-Null
    return $path
}

function Test-DirectoryHasEntries {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        return $false
    }

    return $null -ne (
        Get-ChildItem -LiteralPath $Path -Force |
        Select-Object -First 1
    )
}

function Merge-Directories {
    param(
        [Parameter(Mandatory)][string[]]$Sources,
        [Parameter(Mandatory)][string]$Destination,
        [Parameter(Mandatory)][string]$Label
    )

    foreach ($source in $Sources) {
        if (-not (Test-Path -LiteralPath $source -PathType Container)) {
            continue
        }

        New-Item -ItemType Directory -Path $Destination -Force | Out-Null

        foreach ($item in Get-ChildItem -LiteralPath $source -Force) {
            $target = Join-Path $Destination $item.Name

            if (Test-Path -LiteralPath $target) {
                Write-Log "  [=] $Label/$($item.Name) już zebrane; pomijam duplikat z: $source"
                continue
            }

            Copy-Item `
                -LiteralPath $item.FullName `
                -Destination $Destination `
                -Recurse `
                -Force
        }
    }
}

function Test-HasUserData {
    foreach ($path in (
        $script:ConfigSources +
        $script:PluginSources +
        $script:ThemeSources
    )) {
        if (Test-DirectoryHasEntries -Path $path) {
            return $true
        }
    }

    foreach ($path in @(
        $script:LegacyConfigJson,
        $script:LegacyQuickCss
    )) {
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            return $true
        }
    }

    return $false
}

function Add-LegacyConfig {
    param([Parameter(Mandatory)][string]$Destination)

    if (
        (Test-Path -LiteralPath $script:LegacyConfigJson -PathType Leaf) -and
        -not (Test-Path -LiteralPath (Join-Path $Destination 'config.json'))
    ) {
        New-Item -ItemType Directory -Path $Destination -Force | Out-Null

        Copy-Item `
            -LiteralPath $script:LegacyConfigJson `
            -Destination (Join-Path $Destination 'config.json') `
            -Force
    }

    if (
        (Test-Path -LiteralPath $script:LegacyQuickCss -PathType Leaf) -and
        -not (Test-Path -LiteralPath (Join-Path $Destination 'quick.css'))
    ) {
        New-Item -ItemType Directory -Path $Destination -Force | Out-Null

        Copy-Item `
            -LiteralPath $script:LegacyQuickCss `
            -Destination (Join-Path $Destination 'quick.css') `
            -Force
    }
}

function Export-MillenniumBackup {
    param([Parameter(Mandatory)][string]$OutPath)

    $stage = New-TempDirectory

    try {
        $manifest = @(
            'format=millennium-user-backup-v1'
            'source_os=windows'
            "created_utc=$([DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ'))"
        ) -join "`n"

        # ASCII celowo: manifest będzie identycznie czytelny pod Bash/Linux.
        [System.IO.File]::WriteAllText(
            (Join-Path $stage 'manifest.txt'),
            $manifest + "`n",
            [System.Text.Encoding]::ASCII
        )

        Merge-Directories `
            -Sources $script:ConfigSources `
            -Destination (Join-Path $stage 'config') `
            -Label 'config'

        Add-LegacyConfig `
            -Destination (Join-Path $stage 'config')

        Merge-Directories `
            -Sources $script:PluginSources `
            -Destination (Join-Path $stage 'plugins') `
            -Label 'plugins'

        Merge-Directories `
            -Sources $script:ThemeSources `
            -Destination (Join-Path $stage 'themes') `
            -Label 'themes'

        $hasData =
            (Test-DirectoryHasEntries -Path (Join-Path $stage 'config')) -or
            (Test-DirectoryHasEntries -Path (Join-Path $stage 'plugins')) -or
            (Test-DirectoryHasEntries -Path (Join-Path $stage 'themes'))

        if (-not $hasData) {
            throw 'Nie znalazłam żadnych danych użytkownika Millennium do eksportu.'
        }

        $parent = Split-Path -Parent $OutPath

        if ($parent) {
            New-Item -ItemType Directory -Path $parent -Force | Out-Null
        }

        if (Test-Path -LiteralPath $OutPath) {
            Remove-Item -LiteralPath $OutPath -Force
        }

        & $script:TarExe `
            '-czf' $OutPath `
            '-C' $stage `
            '.'

        if ($LASTEXITCODE -ne 0) {
            throw "tar zakończył się kodem $LASTEXITCODE"
        }

        Write-Log ""
        Write-Log "Backup zapisany:"
        Write-Log "  $OutPath"

        $hash = Get-FileHash -LiteralPath $OutPath -Algorithm SHA256
        Write-Log ""
        Write-Log "SHA256:"
        Write-Log "  $($hash.Hash)"
    }
    finally {
        Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Test-BackupArchive {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Nie ma pliku: $Path"
    }

    $entries = & $script:TarExe '-tzf' $Path

    if ($LASTEXITCODE -ne 0) {
        throw 'Nie udało się odczytać archiwum.'
    }

    foreach ($entry in $entries) {
        $normalized = ([string]$entry) -replace '\\', '/'

        if (
            $normalized -match '^/' -or
            $normalized -match '^[A-Za-z]:' -or
            $normalized -match '(^|/)\.\.(/|$)'
        ) {
            throw "Podejrzana ścieżka w archiwum: $entry"
        }
    }
}

function Replace-Directory {
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Destination,
        [Parameter(Mandatory)][string]$Label
    )

    if (-not (Test-Path -LiteralPath $Source -PathType Container)) {
        return
    }

    Write-Log "  -> ${Label}: $Destination"

    if (Test-Path -LiteralPath $Destination) {
        Remove-Item `
            -LiteralPath $Destination `
            -Recurse `
            -Force
    }

    $parent = Split-Path -Parent $Destination

    if ($parent) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    Copy-Item `
        -LiteralPath $Source `
        -Destination $Destination `
        -Recurse `
        -Force
}

function Import-MillenniumBackup {
    param([Parameter(Mandatory)][string]$InputArchive)

    Test-BackupArchive -Path $InputArchive

    if (Test-SteamRunning) {
        throw 'Steam działa. Zamknij go całkowicie przed importem.'
    }

    $stage = New-TempDirectory

    try {
        & $script:TarExe `
            '-xzf' $InputArchive `
            '-C' $stage

        if ($LASTEXITCODE -ne 0) {
            throw "tar zakończył się kodem $LASTEXITCODE"
        }

        $manifestPath = Join-Path $stage 'manifest.txt'

        if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
            throw 'Brak manifest.txt — to nie wygląda na backup z tego skryptu.'
        }

        $manifest = Get-Content -LiteralPath $manifestPath

        if ($manifest -notcontains 'format=millennium-user-backup-v1') {
            throw 'Nieobsługiwany format backupu.'
        }

        if (Test-HasUserData) {
            $archiveDirectory = Split-Path -Parent $InputArchive

            $preBackup = Join-Path `
                $archiveDirectory `
                ('millennium-preimport-windows-{0}.tar.gz' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))

            Write-Log 'Tworzę backup stanu sprzed importu...'
            Export-MillenniumBackup -OutPath $preBackup

            Write-Log ""
            Write-Log "Backup sprzed importu:"
            Write-Log "  $preBackup"
            Write-Log ""
        }
        else {
            Write-Log 'Brak istniejących danych Millennium — pomijam backup przed importem.'
        }

        Write-Log 'Importuję:'

        Replace-Directory `
            -Source (Join-Path $stage 'config') `
            -Destination $script:ConfigTarget `
            -Label 'config'

        Replace-Directory `
            -Source (Join-Path $stage 'plugins') `
            -Destination $script:PluginTarget `
            -Label 'plugins'

        Replace-Directory `
            -Source (Join-Path $stage 'themes') `
            -Destination $script:ThemeTarget `
            -Label 'themes'

        Write-Log ""
        Write-Log 'Import zakończony.'
        Write-Log 'Uruchom ponownie Steam.'
    }
    finally {
        Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
    }
}

$tarCommand = Get-Command 'tar.exe' -ErrorAction SilentlyContinue

if (-not $tarCommand) {
    $tarCommand = Get-Command 'tar' -ErrorAction SilentlyContinue
}

if (-not $tarCommand) {
    throw 'Nie znalazłam tar.exe. Windows 10/11 powinien mieć go domyślnie.'
}

$script:TarExe = $tarCommand.Source

$script:SteamRoot = Get-SteamRoot
$script:MillenniumRoot = Join-Path $script:SteamRoot 'millennium'

#
# Aktualny Millennium
#
$script:ConfigTarget = Join-Path $script:MillenniumRoot 'config'
$script:PluginTarget = Join-Path $script:MillenniumRoot 'plugin'
$script:ThemeTarget  = Join-Path $script:MillenniumRoot 'themes'

#
# Aktualne + starsze lokalizacje, żeby eksport nie zgubił starej instalacji.
#
$script:ConfigSources = @(
    $script:ConfigTarget
)

$script:PluginSources = @(
    $script:PluginTarget,
    (Join-Path $script:MillenniumRoot 'plugins'),
    (Join-Path $script:SteamRoot 'plugins')
)

$script:ThemeSources = @(
    $script:ThemeTarget,
    (Join-Path $script:SteamRoot 'steamui\skins')
)

#
# Legacy Millennium 2.x.
#
$script:LegacyConfigJson = Join-Path $script:SteamRoot 'ext\config.json'
$script:LegacyQuickCss   = Join-Path $script:SteamRoot 'ext\quickcss.css'

Write-Log "Steam:"
Write-Log "  $script:SteamRoot"
Write-Log ""

switch ($Mode) {
    'export' {
        if (Test-SteamRunning) {
            Write-Log 'UWAGA: Steam działa.'
            Write-Log 'Eksport wykonam, ale najpewniejszy backup jest po jego zamknięciu.'
            Write-Log ''
        }

        if ([string]::IsNullOrWhiteSpace($Archive)) {
            $Archive = Join-Path `
                (Get-Location).Path `
                ('millennium-backup-windows-{0}.tar.gz' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
        }
        else {
            $Archive = Convert-ToFullPath $Archive
        }

        Export-MillenniumBackup -OutPath $Archive
    }

    'import' {
        if ([string]::IsNullOrWhiteSpace($Archive)) {
            throw 'Podaj plik backupu do importu.'
        }

        $Archive = Convert-ToFullPath $Archive
        Import-MillenniumBackup -InputArchive $Archive
    }
}
