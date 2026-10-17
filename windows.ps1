# Reapply Natsumi Append (fx-autoconfig) after a Firefox update.
# Windows only. Natsumi Browser must already be installed in the profile.
[CmdletBinding()]
param(
    [string]$FirefoxDir,
    [Alias("Profile")]
    [string]$ProfileDir,
    [string]$FxAutoconfigRef = "master",
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Write-Step([string]$Message) {
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Fail([string]$Message) {
    Write-Host "ERROR: $Message" -ForegroundColor Red
    exit 1
}

$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)
if (-not $isAdmin -and -not $DryRun) {
    Fail "Run this script as Administrator (right-click PowerShell, then Run as administrator)."
}

if (-not $FirefoxDir) {
    $candidates = @()
    if ($env:ProgramFiles) {
        $candidates += (Join-Path $env:ProgramFiles "Mozilla Firefox")
    }
    if (${env:ProgramFiles(x86)}) {
        $candidates += (Join-Path ${env:ProgramFiles(x86)} "Mozilla Firefox")
    }
    if ($env:LOCALAPPDATA) {
        $candidates += (Join-Path $env:LOCALAPPDATA "Mozilla Firefox")
    }
    $FirefoxDir = $candidates |
        Where-Object { $_ -and (Test-Path (Join-Path $_ "firefox.exe")) } |
        Select-Object -First 1
}
if (-not $FirefoxDir -or -not (Test-Path (Join-Path $FirefoxDir "firefox.exe"))) {
    Fail "Firefox not found. Pass -FirefoxDir 'C:\Program Files\Mozilla Firefox'."
}

if (-not $DryRun -and (Get-Process -Name firefox -ErrorAction SilentlyContinue)) {
    Fail "Firefox is running. Quit Firefox, then run this script again."
}

$profileRoot = Join-Path $env:APPDATA "Mozilla\Firefox\Profiles"
if (-not (Test-Path $profileRoot)) {
    Fail "Firefox profiles folder not found: $profileRoot"
}

if ($ProfileDir -and -not (Test-Path $ProfileDir)) {
    $ProfileDir = Join-Path $profileRoot $ProfileDir
}
if (-not $ProfileDir) {
    $candidate = Get-ChildItem -Path $profileRoot -Directory -Filter "*.default-release" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if (-not $candidate) {
        $candidate = Get-ChildItem -Path $profileRoot -Directory -Filter "*.default*" -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1
    }
    if ($candidate) {
        $ProfileDir = $candidate.FullName
    }
}
if (-not $ProfileDir -or -not (Test-Path $ProfileDir)) {
    Fail "No Firefox profile found in $profileRoot."
}

$chrome = Join-Path $ProfileDir "chrome"
if (-not (Test-Path (Join-Path $chrome "natsumi\natsumi.css"))) {
    Fail "Natsumi Browser is not installed in this profile. Install Natsumi CSS-only first."
}

$temp = Join-Path $env:TEMP ("natsumi-append-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $temp -Force | Out-Null

try {
    Write-Step "Downloading fx-autoconfig ($FxAutoconfigRef)"
    $zip = Join-Path $temp "fx-autoconfig.zip"
    Invoke-WebRequest -UseBasicParsing `
        -Uri "https://github.com/greeeen-dev/fx-autoconfig/archive/refs/heads/$FxAutoconfigRef.zip" `
        -OutFile $zip
    Expand-Archive -Path $zip -DestinationPath $temp -Force

    $src = Get-ChildItem -Path $temp -Directory -Filter "fx-autoconfig-*" |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $src -or -not (Test-Path $src)) {
        Fail "Could not unpack fx-autoconfig."
    }

    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $backup = Join-Path $ProfileDir "natsumi-append-backups\$stamp"
    if (-not $DryRun) {
        New-Item -ItemType Directory -Path $backup -Force | Out-Null
    }

    function Backup-File([string]$Path, [string]$Name) {
        if (Test-Path $Path) {
            if ($DryRun) {
                Write-Host "would back up $Path"
            } else {
                Copy-Item $Path (Join-Path $backup $Name) -Force
            }
        }
    }

    function Backup-Dir([string]$Path, [string]$Name) {
        if (Test-Path $Path) {
            if ($DryRun) {
                Write-Host "would back up $Path"
            } else {
                Copy-Item $Path (Join-Path $backup $Name) -Recurse -Force
            }
        }
    }

    function Copy-FileStep([string]$Source, [string]$Destination) {
        if ($DryRun) {
            Write-Host "would copy $Source -> $Destination"
            return
        }
        $parent = Split-Path $Destination -Parent
        if (-not (Test-Path $parent)) {
            New-Item -ItemType Directory -Path $parent -Force | Out-Null
        }
        Copy-Item $Source $Destination -Force
    }

    function Copy-DirStep([string]$Source, [string]$Destination) {
        if ($DryRun) {
            Write-Host "would copy contents of $Source -> $Destination"
            return
        }
        if (-not (Test-Path $Destination)) {
            New-Item -ItemType Directory -Path $Destination -Force | Out-Null
        }
        Copy-Item -Path (Join-Path $Source "*") -Destination $Destination -Recurse -Force
    }

    Backup-File (Join-Path $FirefoxDir "config.js") "config.js"
    Backup-Dir (Join-Path $FirefoxDir "defaults") "defaults"
    Backup-Dir (Join-Path $chrome "utils") "chrome-utils"
    Backup-Dir (Join-Path $chrome "CSS") "chrome-CSS"
    Backup-Dir (Join-Path $chrome "resources") "chrome-resources"

    Write-Step "Installing Firefox program files"
    Copy-FileStep (Join-Path $src "program\config.js") (Join-Path $FirefoxDir "config.js")
    Copy-FileStep (Join-Path $src "program\defaults\pref\config-prefs.js") `
        (Join-Path $FirefoxDir "defaults\pref\config-prefs.js")

    Write-Step "Installing fx-autoconfig profile files"
    Copy-DirStep (Join-Path $src "profile\chrome\CSS") (Join-Path $chrome "CSS")
    Copy-DirStep (Join-Path $src "profile\chrome\utils") (Join-Path $chrome "utils")
    Copy-DirStep (Join-Path $src "profile\chrome\resources") (Join-Path $chrome "resources")

    $manifest = @"
content userchromejs ./
content userscripts ../natsumi/scripts/
skin userstyles classic/1.0 ../CSS/
content userchrome ../resources/
content natsumi ../natsumi/
content natsumi-icons ../natsumi/icons/
"@
    $manifestPath = Join-Path $chrome "utils\chrome.manifest"
    if ($DryRun) {
        Write-Host "would write $manifestPath"
    } else {
        Set-Content -Path $manifestPath -Value $manifest -Encoding ASCII
    }

    $userJs = Join-Path $ProfileDir "user.js"
    $pref = 'user_pref("userChromeJS.persistent_domcontent_callback", true);'
    if ($DryRun) {
        Write-Host "would ensure the persistent_domcontent_callback pref in $userJs"
    } elseif (Test-Path $userJs) {
        $content = Get-Content $userJs -Raw
        if ($content -notmatch 'userChromeJS\.persistent_domcontent_callback\s*,\s*true') {
            Add-Content -Path $userJs -Value "`r`n$pref" -Encoding ASCII
        }
    } else {
        Set-Content -Path $userJs -Value $pref -Encoding ASCII
    }

    $profileName = Split-Path $ProfileDir -Leaf
    $cache = Join-Path $env:LOCALAPPDATA "Mozilla\Firefox\Profiles\$profileName\startupCache"
    if ($DryRun) {
        Write-Host "would clear $cache"
    } else {
        Remove-Item $cache -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item (Join-Path $ProfileDir "startupCache") -Recurse -Force -ErrorAction SilentlyContinue
    }

    if (-not $DryRun) {
        $required = @(
            (Join-Path $FirefoxDir "config.js"),
            (Join-Path $FirefoxDir "defaults\pref\config-prefs.js"),
            (Join-Path $chrome "utils\boot.sys.mjs"),
            (Join-Path $chrome "utils\module_loader.mjs"),
            (Join-Path $chrome "utils\chrome.manifest")
        )
        foreach ($file in $required) {
            if (-not (Test-Path $file)) {
                Fail "Missing $file after install."
            }
        }
    }

    Write-Step "Done"
    Write-Host "Profile: $ProfileDir"
    Write-Host "Backup:  $backup"
    Write-Host "Start Firefox. If the Natsumi settings page is missing, clear the startup cache from about:support and restart."
}
finally {
    Remove-Item $temp -Recurse -Force -ErrorAction SilentlyContinue
}
