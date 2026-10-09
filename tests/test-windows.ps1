[CmdletBinding()]
param([string]$ImportArchive)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-True {
    param(
        [Parameter(Mandatory)][bool]$Condition,
        [Parameter(Mandatory)][string]$Message
    )

    if (-not $Condition) {
        throw "ASSERTION FAILED: $Message"
    }
}

function Assert-FileText {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Expected
    )

    Assert-True (Test-Path -LiteralPath $Path -PathType Leaf) "Brak pliku: $Path"
    $actual = Get-Content -LiteralPath $Path -Raw
    Assert-True ($actual -eq $Expected) "Nieprawidłowa zawartość: $Path"
}

function Get-Process {
    param([string]$Name)

    # Test importu nie może zależeć od tego, czy Steam działa na maszynie testowej.
    return $null
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$scriptPath = Join-Path $repoRoot 'millennium-backup.ps1'
$fixtureRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('millennium-test-' + [guid]::NewGuid().ToString('N'))
$oldSteamPath = $env:STEAM_PATH

try {
    $steamRoot = Join-Path $fixtureRoot 'Steam'
    $millenniumRoot = Join-Path $steamRoot 'millennium'
    $archive = Join-Path $fixtureRoot 'backup.tar.gz'

    New-Item -ItemType Directory -Force -Path @(
        (Join-Path $steamRoot 'steamapps'),
        (Join-Path $millenniumRoot 'config'),
        (Join-Path $millenniumRoot 'plugin'),
        (Join-Path $millenniumRoot 'plugins'),
        (Join-Path $millenniumRoot 'themes'),
        (Join-Path $steamRoot 'plugins')
    ) | Out-Null

    Set-Content -LiteralPath (Join-Path $millenniumRoot 'config\settings.json') -Value '{"from":"windows"}' -NoNewline -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $millenniumRoot 'plugin\current.txt') -Value 'current-plugin' -NoNewline -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $millenniumRoot 'plugins\current.txt') -Value 'runtime-plugin' -NoNewline -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $millenniumRoot 'plugins\.settings') -Value 'hidden-data' -NoNewline -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $millenniumRoot 'config\config.json') -Value '{"themes":{"activeTheme":"dark"},"plugins":{"enabledPlugins":["example"]}}' -NoNewline -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $millenniumRoot 'config\quick.css') -Value 'runtime-css' -NoNewline -Encoding UTF8
    New-Item -ItemType Directory -Force -Path (Join-Path $steamRoot 'ext'), (Join-Path $steamRoot 'steamui\skins\Documented Theme') | Out-Null
    Set-Content -LiteralPath (Join-Path $steamRoot 'ext\config.json') -Value 'legacy-config' -NoNewline -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $steamRoot 'ext\quickcss.css') -Value 'legacy-css' -NoNewline -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $steamRoot 'steamui\skins\Documented Theme\skin.json') -Value '{"name":"Documented Theme"}' -NoNewline -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $steamRoot 'plugins\legacy.txt') -Value 'legacy-plugin' -NoNewline -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $millenniumRoot 'themes\dark.css') -Value 'dark-theme' -NoNewline -Encoding UTF8

    $env:STEAM_PATH = $steamRoot
    & $scriptPath export $archive
    Assert-True ($LASTEXITCODE -eq 0 -or $null -eq $LASTEXITCODE) 'Eksport Windows zakończył się błędem.'
    Assert-True (Test-Path -LiteralPath $archive -PathType Leaf) 'Eksport nie utworzył archiwum.'

    $entries = @( & tar.exe '-tzf' $archive ) | ForEach-Object { ([string]$_).Replace('\', '/') }
    Assert-True (@($entries | Where-Object { $_ -match 'manifest\.txt' }).Count -gt 0) 'Archiwum nie zawiera manifestu.'
    Assert-True (@($entries | Where-Object { $_ -match 'plugins/current\.txt' }).Count -gt 0) 'Archiwum nie zawiera aktualnego pluginu.'
    Assert-True (@($entries | Where-Object { $_ -match 'plugins/legacy\.txt' }).Count -gt 0) 'Archiwum nie zawiera starszego pluginu.'

    Set-Content -LiteralPath (Join-Path $millenniumRoot 'config\stale.txt') -Value 'stale' -NoNewline -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $millenniumRoot 'plugin\stale.txt') -Value 'stale' -NoNewline -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $millenniumRoot 'plugins\stale.txt') -Value 'stale' -NoNewline -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $millenniumRoot 'themes\stale.css') -Value 'stale' -NoNewline -Encoding UTF8

    & $scriptPath import $archive
    Assert-True ($LASTEXITCODE -eq 0 -or $null -eq $LASTEXITCODE) 'Import Windows zakończył się błędem.'
    Assert-FileText (Join-Path $millenniumRoot 'config\settings.json') '{"from":"windows"}'
    foreach ($target in @('plugins', 'plugin')) {
        Assert-FileText (Join-Path $millenniumRoot "$target\current.txt") 'runtime-plugin'
        Assert-FileText (Join-Path $millenniumRoot "$target\legacy.txt") 'legacy-plugin'
        Assert-FileText (Join-Path $millenniumRoot "$target\.settings") 'hidden-data'
        Assert-True (-not (Test-Path -LiteralPath (Join-Path $millenniumRoot "$target\stale.txt"))) 'Import nie usunął starego pluginu.'
    }
    Assert-FileText (Join-Path $millenniumRoot 'config\config.json') '{"themes":{"activeTheme":"dark"},"plugins":{"enabledPlugins":["example"]}}'
    Assert-FileText (Join-Path $millenniumRoot 'config\quick.css') 'runtime-css'
    Assert-FileText (Join-Path $millenniumRoot 'themes\Documented Theme\skin.json') '{"name":"Documented Theme"}'
    Assert-FileText (Join-Path $millenniumRoot 'themes\dark.css') 'dark-theme'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $millenniumRoot 'plugin\stale.txt'))) 'Import nie usunął starego pluginu.'
    $preBackups = @(Get-ChildItem -LiteralPath $fixtureRoot -Filter 'millennium-preimport-windows-*.tar.gz')
    Assert-True ($preBackups.Count -eq 1) 'Brak backupu przed importem.'
    $preStage = Join-Path $fixtureRoot 'prebackup'
    New-Item -ItemType Directory -Path $preStage | Out-Null
    & tar.exe '-xzf' $preBackups[0].FullName '-C' $preStage
    Assert-True ($LASTEXITCODE -eq 0) 'Nie udało się odczytać backupu przed importem.'
    Assert-FileText (Join-Path $preStage 'plugins\stale.txt') 'stale'

    # Restore an actual Bash export in the cross-platform CI job.
    if ($ImportArchive) {
        & $scriptPath import $ImportArchive
        Assert-FileText (Join-Path $millenniumRoot 'config\config.json') '{"themes":{"activeTheme":"Portable Theme"},"plugins":{"enabledPlugins":["portable"]}}'
        Assert-FileText (Join-Path $millenniumRoot 'config\quick.css') 'portable-css'
        foreach ($target in @('plugins', 'plugin')) {
            Assert-FileText (Join-Path $millenniumRoot "$target\portable\plugin.json") '{"name":"portable"}'
        }
        Assert-FileText (Join-Path $millenniumRoot 'themes\Portable Theme\skin.json') '{"name":"Portable Theme"}'
    }

    # Legacy-only installations must export and restore both config files.
    Remove-Item -LiteralPath $millenniumRoot -Recurse -Force
    Remove-Item -LiteralPath (Join-Path $steamRoot 'plugins'), (Join-Path $steamRoot 'steamui') -Recurse -Force
    & $scriptPath export $archive
    & $scriptPath import $archive
    Assert-FileText (Join-Path $millenniumRoot 'config\config.json') 'legacy-config'
    Assert-FileText (Join-Path $millenniumRoot 'config\quick.css') 'legacy-css'

    # Documentation-only plugin installation must restore to the runtime path.
    Remove-Item -LiteralPath $millenniumRoot, (Join-Path $steamRoot 'ext') -Recurse -Force
    New-Item -ItemType Directory -Path (Join-Path $millenniumRoot 'plugin\Documented Plugin') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $millenniumRoot 'plugin\Documented Plugin\plugin.json') -Value '{"name":"documented"}' -NoNewline -Encoding UTF8
    & $scriptPath export $archive
    & $scriptPath import $archive
    Assert-FileText (Join-Path $millenniumRoot 'plugins\Documented Plugin\plugin.json') '{"name":"documented"}'

    $corruptArchive = Join-Path $fixtureRoot 'corrupt.tar.gz'
    Set-Content -LiteralPath $corruptArchive -Value 'not a tar archive' -NoNewline -Encoding ascii
    $failed = $false

    try {
        & $scriptPath import $corruptArchive
    }
    catch {
        $failed = $true
    }

    Assert-True $failed 'Import uszkodzonego archiwum powinien się nie udać.'

    $emptyRoot = Join-Path $fixtureRoot 'EmptySteam'
    New-Item -ItemType Directory -Force -Path (Join-Path $emptyRoot 'steamapps') | Out-Null
    $env:STEAM_PATH = $emptyRoot
    $emptyArchive = Join-Path $fixtureRoot 'empty.tar.gz'
    $failed = $false

    try {
        & $scriptPath export $emptyArchive
    }
    catch {
        $failed = $true
    }

    Assert-True $failed 'Eksport pustej instalacji powinien się nie udać.'

    $env:STEAM_PATH = Join-Path $fixtureRoot 'MissingSteam'
    $failed = $false
    try { & $scriptPath import $archive } catch { $failed = $true }
    Assert-True $failed 'Nieprawidłowe STEAM_PATH nie może zostać pominięte.'

    if ($env:CROSS_EXPORT_ARCHIVE) {
        $env:STEAM_PATH = $emptyRoot
        $portableRoot = Join-Path $emptyRoot 'millennium'
        New-Item -ItemType Directory -Force -Path (Join-Path $portableRoot 'config'), (Join-Path $portableRoot 'plugins\portable'), (Join-Path $portableRoot 'themes\Portable Theme') | Out-Null
        $utf8 = [System.Text.UTF8Encoding]::new($false)
        [System.IO.File]::WriteAllText((Join-Path $portableRoot 'config\config.json'), '{"themes":{"activeTheme":"Portable Theme"},"plugins":{"enabledPlugins":["portable"]}}', $utf8)
        [System.IO.File]::WriteAllText((Join-Path $portableRoot 'config\quick.css'), 'portable-css', $utf8)
        [System.IO.File]::WriteAllText((Join-Path $portableRoot 'plugins\portable\plugin.json'), '{"name":"portable"}', $utf8)
        [System.IO.File]::WriteAllText((Join-Path $portableRoot 'themes\Portable Theme\skin.json'), '{"name":"Portable Theme"}', $utf8)
        & $scriptPath export $env:CROSS_EXPORT_ARCHIVE
    }
    Write-Host 'Windows tests: PASS'
}
finally {
    if ($null -eq $oldSteamPath) {
        Remove-Item Env:STEAM_PATH -ErrorAction SilentlyContinue
    }
    else {
        $env:STEAM_PATH = $oldSteamPath
    }

    Remove-Item -LiteralPath $fixtureRoot -Recurse -Force -ErrorAction SilentlyContinue
}

# A caught native tar error can leave LASTEXITCODE=1 even though all assertions passed.
exit 0
