[CmdletBinding()]
param(
    [string]$GameDir,
    [switch]$Install,
    [switch]$Package
)

$ErrorActionPreference = 'Stop'

function Test-Dotnet {
    $cmd = Get-Command dotnet -ErrorAction SilentlyContinue
    if (-not $cmd) { return $false }
    $sdks = & dotnet --list-sdks 2>$null
    return ($LASTEXITCODE -eq 0 -and $sdks)
}

function Update-Path {
    $env:Path = [System.Environment]::GetEnvironmentVariable('Path','Machine') + ';' +
                [System.Environment]::GetEnvironmentVariable('Path','User')
    $dotnetRoot = Join-Path $env:ProgramFiles 'dotnet'
    if ((Test-Path $dotnetRoot) -and ($env:Path -notlike "*$dotnetRoot*")) {
        $env:Path += ";$dotnetRoot"
    }
}

function Install-Dotnet {
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        Write-Host 'Installing the .NET 8 SDK with winget' -ForegroundColor Cyan
        winget install --id Microsoft.DotNet.SDK.8 --accept-source-agreements --accept-package-agreements --silent
        Update-Path
        if (Test-Dotnet) { return }
        Write-Host '  winget install did not make dotnet available, falling back' -ForegroundColor Yellow
    }

    Write-Host 'Downloading the official dotnet-install script' -ForegroundColor Cyan
    $script = Join-Path $env:TEMP 'dotnet-install.ps1'
    Invoke-WebRequest -Uri 'https://dot.net/v1/dotnet-install.ps1' -OutFile $script -UseBasicParsing

    Write-Host 'Installing the .NET 8 SDK to your user profile' -ForegroundColor Cyan
    & $script -Channel 8.0 -InstallDir "$env:LOCALAPPDATA\Microsoft\dotnet"
    $userDotnet = "$env:LOCALAPPDATA\Microsoft\dotnet"
    $env:Path = "$userDotnet;$env:Path"
    [Environment]::SetEnvironmentVariable(
        'Path',
        "$userDotnet;" + [Environment]::GetEnvironmentVariable('Path','User'),
        'User')
    Remove-Item $script -Force -ErrorAction SilentlyContinue
}

function Install-RedLoader {
    param([string]$Target)

    Write-Host 'Looking up the latest RedLoader release' -ForegroundColor Cyan
    $release = Invoke-RestMethod 'https://api.github.com/repos/ToniMacaroni/RedLoader/releases/latest' -Headers @{ 'User-Agent' = 'ps' }
    $asset = $release.assets | Where-Object { $_.name -match '^RedLoader.*\.zip$' } | Select-Object -First 1
    if (-not $asset) { throw 'Could not find RedLoader.zip in the latest release' }
    Write-Host "  $($release.tag_name) / $($asset.name)"

    $zip = Join-Path $env:TEMP $asset.name
    Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $zip -UseBasicParsing

    $stage = Join-Path $env:TEMP 'redloader-extract'
    if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
    Expand-Archive -Path $zip -DestinationPath $stage -Force
    Copy-Item -Path (Join-Path $stage '*') -Destination $Target -Recurse -Force
    Remove-Item $zip -Force -ErrorAction SilentlyContinue
    Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue

    Write-Host '  RedLoader installed' -ForegroundColor Green
}

function Find-GameDir {
    if ($env:SOTF_PATH) { return $env:SOTF_PATH }
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

if (-not (Test-Dotnet)) {
    Write-Host ''
    Write-Host 'The .NET 8 SDK is required to build this mod and was not found.' -ForegroundColor Yellow
    $answer = Read-Host 'Download and install it now? (y/N)'
    if ($answer -ne 'y') {
        throw 'Cannot build without the .NET SDK. Get it at https://dotnet.microsoft.com/download'
    }
    Install-Dotnet
    if (-not (Test-Dotnet)) {
        throw 'The SDK was installed but dotnet is still not on PATH. Reopen PowerShell and rerun this script.'
    }
}
Write-Host ("dotnet SDK: " + (dotnet --version)) -ForegroundColor Green

if (-not $GameDir) { $GameDir = Find-GameDir }
if (-not $GameDir) {
    throw 'Could not find Sons Of The Forest. Pass -GameDir "path" or set SOTF_PATH.'
}
Write-Host "Game directory: $GameDir" -ForegroundColor Cyan

if (-not (Test-Path (Join-Path $GameDir '_RedLoader\net6\SonsSdk.dll'))) {
    Write-Host ''
    Write-Host 'RedLoader is not installed in your game folder.' -ForegroundColor Yellow
    $answer = Read-Host 'Download and install the latest RedLoader release now? (y/N)'
    if ($answer -ne 'y') {
        throw 'RedLoader is required. Get it at https://github.com/ToniMacaroni/RedLoader/releases'
    }
    Install-RedLoader -Target $GameDir
}

if (-not (Test-Path (Join-Path $GameDir '_RedLoader\Game\Sons.dll'))) {
    Write-Host ''
    Write-Host 'RedLoader is installed but has not generated its game assemblies yet.' -ForegroundColor Yellow
    Write-Host 'Launch Sons of the Forest once and wait for the main menu. The first'
    Write-Host 'launch takes a few minutes while it processes the game files.'
    Write-Host ''
    Write-Host 'Then quit the game and run this script again.'
    return
}
Write-Host 'RedLoader ready' -ForegroundColor Green

dotnet build -c Release --nologo -p:GameDir="$GameDir"
if ($LASTEXITCODE -ne 0) { throw 'Build failed' }

$dll = Join-Path $PSScriptRoot 'bin\Release\net6\FlyCart.dll'

if ($Install) {
    $modsDir = Join-Path $GameDir 'Mods'
    $modDataDir = Join-Path $modsDir 'FlyCart'
    New-Item -ItemType Directory -Force -Path $modDataDir | Out-Null
    Copy-Item $dll -Destination $modsDir -Force
    Copy-Item (Join-Path $PSScriptRoot 'manifest.json') -Destination $modDataDir -Force
    Write-Host "Installed to $modsDir" -ForegroundColor Green
}

if ($Package) {
    $stage = Join-Path $PSScriptRoot 'dist'
    $zip = Join-Path $PSScriptRoot 'FlyCart.zip'

    if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
    New-Item -ItemType Directory -Force -Path (Join-Path $stage 'FlyCart') | Out-Null
    Copy-Item $dll -Destination $stage -Force
    Copy-Item (Join-Path $PSScriptRoot 'manifest.json') -Destination (Join-Path $stage 'FlyCart') -Force

    if (Test-Path $zip) { Remove-Item $zip -Force }
    Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $zip
    Remove-Item $stage -Recurse -Force

    Write-Host "Packaged $zip" -ForegroundColor Green
}

