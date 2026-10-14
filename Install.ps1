[CmdletBinding()]
param(
    [string]$GameDir,
    [switch]$Remove
)

$ErrorActionPreference = 'Stop'

function Write-Step {
    param([string]$Text)
    Write-Host ''
    Write-Host $Text -ForegroundColor Cyan
}

function Find-GameDir {
    $steam = (Get-ItemProperty 'HKCU:\Software\Valve\Steam' -ErrorAction SilentlyContinue).SteamPath
    if (-not $steam) { return $null }
    $libs = @($steam)
    $vdf = Join-Path $steam 'steamapps\libraryfolders.vdf'
    if (Test-Path $vdf) {
        Select-String -Path $vdf -Pattern '"path"\s+"(.+?)"' -AllMatches |
            ForEach-Object { $_.Matches } |
            ForEach-Object { $libs += $_.Groups[1].Value.Replace('\\','\') }
    }
    foreach ($lib in $libs) {
        $candidate = Join-Path $lib 'steamapps\common\Sons Of The Forest'
        if (Test-Path (Join-Path $candidate 'SonsOfTheForest.exe')) { return $candidate }
    }
    return $null
}

function Get-ReleaseZip {
    param([string]$Repo, [string]$Pattern, [string]$OutFile)
    $release = Invoke-RestMethod "https://api.github.com/repos/$Repo/releases/latest" -Headers @{ 'User-Agent' = 'ps' }
    $asset = $release.assets | Where-Object { $_.name -match $Pattern } | Select-Object -First 1
    if (-not $asset) { throw "Could not find a download matching $Pattern in the latest $Repo release" }
    Write-Host "  version $($release.tag_name)"
    Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $OutFile -UseBasicParsing
    return $asset.name
}

try {
    Write-Host ''
    Write-Host '====================================' -ForegroundColor Green
    Write-Host ' FlyCart installer' -ForegroundColor Green
    Write-Host '====================================' -ForegroundColor Green

    if (Get-Process -Name 'SonsOfTheForest' -ErrorAction SilentlyContinue) {
        throw 'Sons of the Forest is running. Close the game and run the installer again.'
    }

    Write-Step 'Looking for Sons of the Forest'
    if (-not $GameDir) { $GameDir = Find-GameDir }
    if (-not $GameDir -or -not (Test-Path (Join-Path $GameDir 'SonsOfTheForest.exe'))) {
        Write-Host '  Could not find the game automatically.' -ForegroundColor Yellow
        Write-Host '  In Steam, right-click Sons Of The Forest, then Manage, then Browse local files.'
        Write-Host '  Copy the folder path from the address bar and paste it below.'
        $GameDir = (Read-Host '  Game folder').Trim('"')
        if (-not (Test-Path (Join-Path $GameDir 'SonsOfTheForest.exe'))) {
            throw "SonsOfTheForest.exe was not found in $GameDir"
        }
    }
    Write-Host "  found: $GameDir" -ForegroundColor Green

    if ($Remove) {
        Write-Step 'Removing FlyCart'
        $modsDir = Join-Path $GameDir 'Mods'
        $dll = Join-Path $modsDir 'FlyCart.dll'
        $dataDir = Join-Path $modsDir 'FlyCart'
        $found = (Test-Path $dll) -or (Test-Path $dataDir)
        Remove-Item $dll -Force -ErrorAction SilentlyContinue
        Remove-Item $dataDir -Recurse -Force -ErrorAction SilentlyContinue
        if ($found) {
            Write-Host '  removed' -ForegroundColor Green
        }
        else {
            Write-Host '  FlyCart was not installed' -ForegroundColor Yellow
        }
        Write-Host ''
        Write-Host 'RedLoader and your other mods were left alone.'
        Write-Host ''
        Read-Host 'Press Enter to close' | Out-Null
        return
    }

    $needsFirstLaunch = $false

    Write-Step 'Checking for RedLoader'
    if (Test-Path (Join-Path $GameDir '_RedLoader\net6\SonsSdk.dll')) {
        Write-Host '  already installed' -ForegroundColor Green
    }
    else {
        Write-Host '  not installed, downloading it now'
        $rlZip = Join-Path $env:TEMP 'RedLoader.zip'
        Get-ReleaseZip -Repo 'ToniMacaroni/RedLoader' -Pattern '^RedLoader.*\.zip$' -OutFile $rlZip | Out-Null

        $rlStage = Join-Path $env:TEMP 'redloader-stage'
        if (Test-Path $rlStage) { Remove-Item $rlStage -Recurse -Force }
        Expand-Archive -Path $rlZip -DestinationPath $rlStage -Force
        Copy-Item -Path (Join-Path $rlStage '*') -Destination $GameDir -Recurse -Force
        Remove-Item $rlZip -Force -ErrorAction SilentlyContinue
        Remove-Item $rlStage -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host '  installed' -ForegroundColor Green
        $needsFirstLaunch = $true
    }

    Write-Step 'Downloading FlyCart'
    $modZip = Join-Path $env:TEMP 'FlyCart.zip'
    Get-ReleaseZip -Repo 'JustinOros/sotf-flycart' -Pattern '^FlyCart\.zip$' -OutFile $modZip | Out-Null

    Write-Step 'Installing FlyCart'
    $modsDir = Join-Path $GameDir 'Mods'
    New-Item -ItemType Directory -Force -Path $modsDir | Out-Null
    Remove-Item (Join-Path $modsDir 'FlyCart.dll') -Force -ErrorAction SilentlyContinue
    Remove-Item (Join-Path $modsDir 'FlyCart') -Recurse -Force -ErrorAction SilentlyContinue
    Expand-Archive -Path $modZip -DestinationPath $modsDir -Force
    Remove-Item $modZip -Force -ErrorAction SilentlyContinue

    if (-not (Test-Path (Join-Path $modsDir 'FlyCart.dll'))) {
        throw 'Something went wrong, FlyCart.dll is not in the Mods folder'
    }
    if (-not (Test-Path (Join-Path $modsDir 'FlyCart\manifest.json'))) {
        throw 'Something went wrong, manifest.json is not in the Mods\FlyCart folder'
    }
    Write-Host '  installed' -ForegroundColor Green

    Write-Host ''
    Write-Host '====================================' -ForegroundColor Green
    Write-Host ' Done' -ForegroundColor Green
    Write-Host '====================================' -ForegroundColor Green
    Write-Host ''

    if ($needsFirstLaunch) {
        Write-Host 'RedLoader was installed for the first time, so the next time you start'
        Write-Host 'the game it will take a few extra minutes to get ready. That is normal.'
        Write-Host ''
    }

    Write-Host 'Start Sons of the Forest, then:'
    Write-Host '  1. Check that MODS appears on the main menu and lists FlyCart'
    Write-Host '  2. Load into a game and get in a golf cart'
    Write-Host '  3. Open the console and run: flycart on'
    Write-Host ''
    Write-Host 'To uninstall, run this script again with -Remove'
    Write-Host ''
}
catch {
    Write-Host ''
    Write-Host "Install failed: $($_.Exception.Message)" -ForegroundColor Red
    if ($_.Exception.Message -match 'denied') {
        Write-Host 'Try again from PowerShell opened with Run as administrator.' -ForegroundColor Yellow
    }
    Write-Host ''
}

Read-Host 'Press Enter to close' | Out-Null
