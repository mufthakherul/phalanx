#!/usr/bin/env pwsh
# =============================================================================
# Siyarix Universal Uninstaller for Windows
#   Removes Siyarix AI Cybersecurity Orchestration Agent from Windows systems.
#   Supports both Regular and Deep Dive (forensic-grade trace purge) modes.
# =============================================================================

$ErrorActionPreference = 'Stop'
$SIYARIX_VERSION = "1.0.1"

function Write-Banner {
  Write-Host @"
   ███████╗██╗██╗   ██╗ █████╗ ██████╗ ██╗██╗  ██╗
   ██╔════╝██╚██╗ ██╔╝██╔══██╗██╔══██╗██║╚██╗██╔╝
   ███████╗██║╚████╔╝ ███████║██████╔╝██║ ╚███╔╝
   ╚════██║██║ ╚██╔╝  ██╔══██║██╔══██╗██║ ██╔██╗
   ███████║██║  ██║   ██║  ██║██║  ██║██║██╔╝ ██╗
   ╚══════╝╚═╝  ╚═╝   ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝╚═╝  ╚═╝
   AI Cybersecurity Orchestration Agent Windows Uninstaller
"@ -ForegroundColor Cyan
}

function Write-Info  { Write-Host "==>" -ForegroundColor Blue -NoNewline; Write-Host " $args" }
function Write-Ok    { Write-Host "  $([char]0x2713)" -ForegroundColor Green -NoNewline; Write-Host " $args" }
function Write-Warn  { Write-Host "  !" -ForegroundColor Yellow -NoNewline; Write-Host " $args" }
function Write-Err   { Write-Host "  $([char]0x2717)" -ForegroundColor Red -NoNewline; Write-Host " $args" }

function Test-Admin {
  try {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
  } catch { return $false }
}

function Remove-PathEntry {
  param([string]$TargetSubstring)
  try {
    $userPath = [Environment]::GetEnvironmentVariable("PATH", "User")
    $paths = $userPath -split ';' | Where-Object { $_ -ne "" -and $_ -notlike "*$TargetSubstring*" }
    $newUserPath = $paths -join ';'
    if ($userPath -ne $newUserPath) {
      if (-not $DryRun) {
        [Environment]::SetEnvironmentVariable("PATH", $newUserPath, "User")
      }
      Write-Ok "Removed Siyarix entry from User PATH."
    }

    if ($IsAdmin) {
      $machinePath = [Environment]::GetEnvironmentVariable("PATH", "Machine")
      $mPaths = $machinePath -split ';' | Where-Object { $_ -ne "" -and $_ -notlike "*$TargetSubstring*" }
      $newMachinePath = $mPaths -join ';'
      if ($machinePath -ne $newMachinePath) {
        if (-not $DryRun) {
          [Environment]::SetEnvironmentVariable("PATH", $newMachinePath, "Machine")
        }
        Write-Ok "Removed Siyarix entry from Machine PATH."
      }
    }
  } catch {
    Write-Warn "Failed to update PATH environment variable: $_"
  }
}

# --- Core uninstaller script ---
function Main {
  param(
    [switch]$DryRun,
    [string]$UninstallMode,
    [switch]$Yes
  )

  Write-Banner

  $IsAdmin = Test-Admin
  if (-not $IsAdmin) {
    Write-Warn "Not running as Administrator. Forensic system logs and Prefetch cleanup require elevation."
  }

  # --- Detection ---
  $pipxDetected = $false
  $pipDetected = $false
  $wingetDetected = $false
  $chocoDetected = $false
  $scoopDetected = $false
  $cloneDetected = $false

  # Check pipx
  try {
    $pipxList = pipx list 2>$null
    if ($pipxList -and ($pipxList | Select-String "siyarix")) {
      $pipxDetected = $true
    }
  } catch {}

  # Check pip
  try {
    $pipShow = python -m pip show siyarix 2>$null
    if ($pipShow) {
      $pipDetected = $true
    }
  } catch {}

  # Check winget
  try {
    $wingetList = winget list Mufthakherul.Siyarix 2>$null
    if ($LastExitCode -eq 0 -and $wingetList) {
      $wingetDetected = $true
    }
  } catch {}

  # Check choco
  try {
    $chocoList = choco list -lo siyarix 2>$null
    if ($chocoList -and ($chocoList | Select-String "siyarix")) {
      $chocoDetected = $true
    }
  } catch {}

  # Check scoop
  try {
    $scoopList = scoop list siyarix 2>$null
    if ($LastExitCode -eq 0 -and $scoopList -and ($scoopList | Select-String "siyarix")) {
      $scoopDetected = $true
    }
  } catch {}

  # Check clone
  if ((Test-Path "pyproject.toml") -and (Test-Path ".git")) {
    $tomlContent = Get-Content "pyproject.toml" -ErrorAction SilentlyContinue
    if ($tomlContent -and ($tomlContent | Select-String 'name = "siyarix"')) {
      $cloneDetected = $true
    }
  }

  # Show detected
  if (-not ($pipxDetected -or $pipDetected -or $wingetDetected -or $chocoDetected -or $scoopDetected -or $cloneDetected)) {
    Write-Warn "No installations of Siyarix were auto-detected on this system."
    Write-Warn "You can still proceed with Deep Dive to purge config files or traces."
  } else {
    Write-Info "Detected Siyarix installations:"
    if ($pipxDetected) { Write-Ok "  - Installed via pipx" }
    if ($pipDetected) { Write-Ok "  - Installed via pip" }
    if ($wingetDetected) { Write-Ok "  - Installed via winget" }
    if ($chocoDetected) { Write-Ok "  - Installed via Chocolatey" }
    if ($scoopDetected) { Write-Ok "  - Installed via Scoop" }
    if ($cloneDetected) { Write-Ok "  - Local Git clone directory" }
  }

  # Prompt mode if not specified
  $mode = $UninstallMode
  if (-not $mode) {
    if ($Yes) {
      $mode = "Regular"
    } else {
      Write-Host "`nSelect uninstallation method:"
      Write-Host "  1) Regular [Normal package uninstall]"
      Write-Host "  2) Deep Dive [Forensic cleanup: Purge configs, models, caches, logs, keyring, history]"
      $choice = Read-Host "Select option (1 or 2)"
      if ($choice -eq "2") {
        $mode = "Deep"
      } else {
        $mode = "Regular"
      }
    }
  }

  $uninstalled = $false

  # --- Package removals ---
  Write-Info "Executing Package Removal..."

  if ($pipxDetected) {
    Write-Info "Uninstalling from pipx..."
    if ($DryRun) { Write-Info "[DRY-RUN] Would run: pipx uninstall siyarix" }
    else {
      try {
        pipx uninstall siyarix 2>&1 | Out-Null
        $uninstalled = $true
      } catch { Write-Err "Failed to uninstall from pipx: $_" }
    }
  }

  if ($pipDetected) {
    Write-Info "Uninstalling from pip..."
    if ($DryRun) { Write-Info "[DRY-RUN] Would run: python -m pip uninstall siyarix -y" }
    else {
      try {
        python -m pip uninstall siyarix -y 2>&1 | Out-Null
        $uninstalled = $true
      } catch { Write-Err "Failed to uninstall from pip: $_" }
    }
  }

  if ($wingetDetected) {
    Write-Info "Uninstalling from winget..."
    if ($DryRun) { Write-Info "[DRY-RUN] Would run: winget uninstall Mufthakherul.Siyarix --silent" }
    else {
      try {
        winget uninstall Mufthakherul.Siyarix --silent 2>&1 | Out-Null
        $uninstalled = $true
      } catch { Write-Err "Failed to uninstall from winget: $_" }
    }
  }

  if ($chocoDetected) {
    Write-Info "Uninstalling from Chocolatey..."
    if ($DryRun) { Write-Info "[DRY-RUN] Would run: choco uninstall siyarix -y" }
    else {
      try {
        choco uninstall siyarix -y 2>&1 | Out-Null
        $uninstalled = $true
      } catch { Write-Err "Failed to uninstall from Chocolatey: $_" }
    }
  }

  if ($scoopDetected) {
    Write-Info "Uninstalling from Scoop..."
    if ($DryRun) { Write-Info "[DRY-RUN] Would run: scoop uninstall siyarix" }
    else {
      try {
        scoop uninstall siyarix 2>&1 | Out-Null
        $uninstalled = $true
      } catch { Write-Err "Failed to uninstall from Scoop: $_" }
    }
  }

  if ($cloneDetected) {
    Write-Info "Cleaning build caches in local clone..."
    if ($DryRun) { Write-Info "[DRY-RUN] Would delete local build caches" }
    else {
      try {
        $dirs = @(".venv", "venv", "dist", "build", "*.egg-info", ".pytest_cache", ".mypy_cache", ".ruff_cache")
        foreach ($d in $dirs) {
          if (Test-Path $d) { Remove-Item $d -Recurse -Force -ErrorAction SilentlyContinue }
        }
        Get-ChildItem -Filter "__pycache__" -Recurse | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        Write-Ok "Cleaned local repository build files."
      } catch {}
    }
  }

  if ($uninstalled) {
    Write-Ok "Siyarix package/binary removal completed."
  }

  # --- Deep Dive purges ---
  if ($mode -eq "Deep") {
    Write-Info "Initiating Deep Dive (Forensic trace purge)..."

    # 1. Delete config/data folders
    $userHome = [System.Environment]::GetFolderPath("UserProfile")
    $siyarixDirs = @(
      "$userHome\.siyarix",
      "$env:APPDATA\siyarix",
      "$env:LOCALAPPDATA\siyarix"
    )

    # Check for custom paths
    $customConfig = $env:SIYARIX_CONFIG_DIR
    if (-not $customConfig) { $customConfig = $env:SIYARIX_HOME }
    if (-not $customConfig) { $customConfig = $env:SIYARIX_CONFIG }
    if ($customConfig) { $siyarixDirs += $customConfig }

    foreach ($dir in $siyarixDirs) {
      if (Test-Path $dir) {
        Write-Info "Deleting config/data folder: $dir"
        if (-not $DryRun) {
          try {
            Remove-Item $dir -Recurse -Force -ErrorAction SilentlyContinue
            Write-Ok "Deleted: $dir"
          } catch { Write-Err "Failed to delete $($dir) - $_" }
        }
      }
    }

    # 2. Keyring entries
    Write-Info "Checking OS keyring passwords..."
    if ($DryRun) { Write-Info "[DRY-RUN] Would request python to purge credential keyring entries." }
    else {
      try {
        python -c "import keyring; keyring.delete_password('siyarix', 'cred_store_key')" 2>$null
        Write-Ok "Purged OS keyring entries."
      } catch {}
    }

    # 3. Clean up PATH environment variables
    Write-Info "Cleaning Siyarix entries from PATH environment variables..."
    Remove-PathEntry -TargetSubstring ".siyarix"

    # 4. PowerShell Command History (Forensic history purge)
    try {
      $historyPath = (Get-PSReadLineOption).HistorySavePath
      if ($historyPath -and (Test-Path $historyPath)) {
        Write-Info "Purging Siyarix commands from PowerShell history: $historyPath"
        if (-not $DryRun) {
          $historyContent = Get-Content $historyPath -ErrorAction SilentlyContinue
          if ($historyContent) {
            $cleanedHistory = $historyContent | Where-Object { $_ -notmatch 'siyarix' }
            Set-Content $historyPath $cleanedHistory -Force
            Write-Ok "PowerShell command history purged."
          }
        }
      }
    } catch {
      Write-Warn "Could not clean PowerShell history: $_"
    }

    # 5. Prefetch Traces (Forensic cleanup)
    if ($IsAdmin) {
      Write-Info "Checking Windows Prefetch for execution traces..."
      try {
        $prefetchFiles = Get-ChildItem -Path "$env:SystemRoot\Prefetch" -Filter "*siyarix*.pf" -ErrorAction SilentlyContinue
        foreach ($file in $prefetchFiles) {
          Write-Info "Deleting prefetch file: $($file.Name)"
          if (-not $DryRun) {
            Remove-Item $file.FullName -Force -ErrorAction SilentlyContinue
          }
        }
        Write-Ok "Prefetch traces cleaned."
      } catch {
        Write-Warn "Could not clean Prefetch files: $_"
      }
    }

    # 6. MUICache Registry entries (Forensic cleanup)
    Write-Info "Cleaning MUICache registry entries..."
    $muiPath = "HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\MuiCache"
    if (Test-Path $muiPath) {
      try {
        $muiKey = Get-Item $muiPath
        foreach ($valName in $muiKey.GetValueNames()) {
          if ($valName -like "*siyarix*" -or ($muiKey.GetValue($valName) -like "*siyarix*")) {
            Write-Info "Removing MUICache entry: $valName"
            if (-not $DryRun) {
              Remove-ItemProperty -Path $muiPath -Name $valName -ErrorAction SilentlyContinue
            }
          }
        }
        Write-Ok "MUICache registry entries cleaned."
      } catch {
        Write-Warn "Failed to clean MUICache keys: $_"
      }
    }

    # 7. Recent Items (Forensic cleanup)
    $recentPath = "$env:APPDATA\Microsoft\Windows\Recent"
    if (Test-Path $recentPath) {
      Write-Info "Cleaning Windows Recent Items..."
      try {
        $recentFiles = Get-ChildItem -Path $recentPath -Filter "*siyarix*" -ErrorAction SilentlyContinue
        foreach ($file in $recentFiles) {
          Write-Info "Removing Recent shortcut: $($file.Name)"
          if (-not $DryRun) {
            Remove-Item $file.FullName -Force -ErrorAction SilentlyContinue
          }
        }
        Write-Ok "Recent shortcuts cleaned."
      } catch {
        Write-Warn "Failed to clean Recent items: $_"
      }
    }

    # 8. Temporary Files
    Write-Info "Cleaning Siyarix files from temporary directories..."
    $tempDirs = @($env:TEMP, "$env:SystemRoot\Temp")
    foreach ($td in $tempDirs) {
      if (Test-Path $td) {
        try {
          $tFiles = Get-ChildItem -Path $td -Filter "*siyarix*" -Recurse -ErrorAction SilentlyContinue
          foreach ($file in $tFiles) {
            Write-Info "Deleting temp entry: $($file.FullName)"
            if (-not $DryRun) {
              Remove-Item $file.FullName -Recurse -Force -ErrorAction SilentlyContinue
            }
          }
        } catch {}
      }
    }
    Write-Ok "Temp files cleaned."

    # 9. Pip Cache
    Write-Info "Purging pip cache for Siyarix..."
    if (-not $DryRun) {
      try {
        python -m pip cache remove siyarix 2>$null | Out-Null
        Write-Ok "Pip cache cleaned."
      } catch {}
    }

    Write-Ok "Deep dive uninstallation complete. No traces left."
  }

  Write-Host "`nDone!`n" -ForegroundColor Green
  return 0
}

# --- Execution Arguments Parsing ---
$dryRunMode = $false
$uninstallModeSelected = ""
$autoConfirmMode = $false

for ($i = 0; $i -lt $args.Count; $i++) {
  switch ($args[$i]) {
    '--dry-run' { $dryRunMode = $true }
    '--regular' { $uninstallModeSelected = "Regular" }
    '--deep'    { $uninstallModeSelected = "Deep" }
    '--yes'     { $autoConfirmMode = $true }
    '-y'        { $autoConfirmMode = $true }
    '--help' {
      Write-Host "Usage: uninstall.ps1 [options]"
      Write-Host ""
      Write-Host "Options:"
      Write-Host "  --dry-run       Simulate uninstallation without making changes"
      Write-Host "  --regular       Perform normal package uninstallation"
      Write-Host "  --deep          Perform deep dive trace purging"
      Write-Host "  --yes, -y       Auto-confirm all interactive actions"
      Write-Host "  --help          Show this help"
      return 0
    }
  }
}

try {
  $exitCode = Main -DryRun:$dryRunMode -UninstallMode:$uninstallModeSelected -Yes:$autoConfirmMode
} catch {
  Write-Host "`n[!] An unexpected error occurred:" -ForegroundColor Red
  Write-Host $_ -ForegroundColor Red
  $exitCode = 1
}

if ([Environment]::UserInteractive -and -not $env:CI) {
  try {
    Write-Host "Press any key to exit..." -ForegroundColor Cyan
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
  } catch {}
}

exit $exitCode
