[CmdletBinding()]
param()

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
        (Join-Path $millenniumRoot 'themes'),
        (Join-Path $steamRoot 'plugins')
    ) | Out-Null

    Set-Content -LiteralPath (Join-Path $millenniumRoot 'config\settings.json') -Value '{"from":"windows"}' -NoNewline -Encoding utf8NoBOM
    Set-Content -LiteralPath (Join-Path $millenniumRoot 'plugin\current.txt') -Value 'current-plugin' -NoNewline -Encoding utf8NoBOM
    Set-Content -LiteralPath (Join-Path $steamRoot 'plugins\legacy.txt') -Value 'legacy-plugin' -NoNewline -Encoding utf8NoBOM
    Set-Content -LiteralPath (Join-Path $millenniumRoot 'themes\dark.css') -Value 'dark-theme' -NoNewline -Encoding utf8NoBOM

    $env:STEAM_PATH = $steamRoot
    & $scriptPath export $archive
    Assert-True ($LASTEXITCODE -eq 0 -or $null -eq $LASTEXITCODE) 'Eksport Windows zakończył się błędem.'
    Assert-True (Test-Path -LiteralPath $archive -PathType Leaf) 'Eksport nie utworzył archiwum.'

    $entries = @( & tar.exe '-tzf' $archive ) | ForEach-Object { ([string]$_).Replace('\', '/') }
    Assert-True (@($entries | Where-Object { $_ -match 'manifest\.txt' }).Count -gt 0) 'Archiwum nie zawiera manifestu.'
    Assert-True (@($entries | Where-Object { $_ -match 'plugins/current\.txt' }).Count -gt 0) 'Archiwum nie zawiera aktualnego pluginu.'
    Assert-True (@($entries | Where-Object { $_ -match 'plugins/legacy\.txt' }).Count -gt 0) 'Archiwum nie zawiera starszego pluginu.'

    Set-Content -LiteralPath (Join-Path $millenniumRoot 'config\stale.txt') -Value 'stale' -NoNewline -Encoding utf8NoBOM
    Set-Content -LiteralPath (Join-Path $millenniumRoot 'plugin\stale.txt') -Value 'stale' -NoNewline -Encoding utf8NoBOM
    Set-Content -LiteralPath (Join-Path $millenniumRoot 'themes\stale.css') -Value 'stale' -NoNewline -Encoding utf8NoBOM

    & $scriptPath import $archive
    Assert-True ($LASTEXITCODE -eq 0 -or $null -eq $LASTEXITCODE) 'Import Windows zakończył się błędem.'
    Assert-FileText (Join-Path $millenniumRoot 'config\settings.json') '{"from":"windows"}'
    Assert-FileText (Join-Path $millenniumRoot 'plugin\current.txt') 'current-plugin'
    Assert-FileText (Join-Path $millenniumRoot 'plugin\legacy.txt') 'legacy-plugin'
    Assert-FileText (Join-Path $millenniumRoot 'themes\dark.css') 'dark-theme'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $millenniumRoot 'plugin\stale.txt'))) 'Import nie usunął starego pluginu.'

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
