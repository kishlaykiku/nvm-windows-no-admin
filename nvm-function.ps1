if (-not $global:NVM_ROOT) { $global:NVM_ROOT = "C:\nvm" }

# Ask a Yes/No question, returns boolean
function Ask-YesNo($msg, $defaultYes = $true) {
    $yn = if ($defaultYes) { "[Y/n]" } else { "[y/N]" }
    while ($true) {
        $r = Read-Host "$msg $yn"
        if ([string]::IsNullOrWhiteSpace($r)) { return $defaultYes }
        switch ($r.ToLower()) {
            { $_ -in @('y','yes') } { return $true }
            { $_ -in @('n','no') }  { return $false }
            default { Write-Host "Please answer y or n." }
        }
    }
}

# Spinner while a job (or jobs) are running
function Show-JobSpinner {
    param(
        [Parameter(Mandatory=$true)][object]$Jobs,
        [string]$Message = "Cleaning up, please wait..."
    )

    $jobIds = @()
    if ($Jobs -is [System.Array]) {
        foreach ($j in $Jobs) {
            if ($j -is [int]) { $jobIds += $j } elseif ($j -is [System.Management.Automation.Job]) { $jobIds += $j.Id }
        }
    } else {
        if ($Jobs -is [int]) { $jobIds += $Jobs } elseif ($Jobs -is [System.Management.Automation.Job]) { $jobIds += $Jobs.Id }
    }
    if ($jobIds.Count -eq 0) { return }

    $anyRunning = $false
    foreach ($id in $jobIds) {
        $j = Get-Job -Id $id -ErrorAction SilentlyContinue
        if ($j -and $j.State -eq 'Running') { $anyRunning = $true; break }
    }
    if (-not $anyRunning) { return }

    $spinner = @('\','|','/','-')
    $i = 0
    while ($true) {
        $running = $false
        foreach ($id in $jobIds) {
            $j = Get-Job -Id $id -ErrorAction SilentlyContinue
            if ($j -and $j.State -eq 'Running') { $running = $true; break }
        }
        if (-not $running) { break }
        $ch = $spinner[$i % $spinner.Length]
        Write-Host -NoNewline "`r$Message [$ch]"
        Start-Sleep -Milliseconds 150
        $i++
    }
    Write-Host "`r$Message [OK]   "
}

# Short spinner
function Show-ShortSpinner {
    param([string]$Message = "Processing...", [int]$DurationSeconds = 2)
    $spinner = @('\','|','/','-')
    $end = (Get-Date).AddSeconds($DurationSeconds)
    $i = 0
    while ((Get-Date) -lt $end) {
        $ch = $spinner[$i % $spinner.Length]
        Write-Host -NoNewline "`r$Message [$ch]"
        Start-Sleep -Milliseconds 150
        $i++
    }
    Write-Host "`r$Message [OK]   "
}

# Print activated message and update PATH
function Show-ActivatedNode($folder) {
    $nodePath = $folder.FullName
    $ver = $folder.Name -replace '^v',''

    # Remove old Node versions from current PATH
    $currentPath = $env:Path -split ';' | Where-Object { ($_ -ne "") -and ($_ -notlike "*\versions\*") }
    $env:Path = ($nodePath + ";" + ($currentPath -join ';'))

    # Update User PATH for future sessions
    $userPath = [Environment]::GetEnvironmentVariable("Path","User")
    $userParts = $userPath -split ';' | Where-Object { ($_ -ne "") -and ($_ -notlike "*\versions\*") }
    $newUserPath = $nodePath + ";" + ($userParts -join ';')
    [Environment]::SetEnvironmentVariable("Path", $newUserPath, "User")

    Write-Host "Activated Node version $ver [$nodePath]"
}

# nvm core: full version or major -> choose patch
function nvm-core {
    param([Parameter(ValueFromRemainingArguments=$true)]$Args)
    if (-not $Args) { & "$global:NVM_ROOT\nvm.exe"; return }

    $command = $Args[0].ToLower()
    if ($command -ne "use") { & "$global:NVM_ROOT\nvm.exe" @Args; return }
    if ($Args.Count -lt 2) { Write-Error "Usage: nvm use <version>"; return }

    $raw = $Args[1]
    $input = ($raw -replace "^v","").Trim()
    $isFull = ($input -match "\.")
    $root = Join-Path $global:NVM_ROOT "versions"

    if ($isFull) {
        $candidate = Join-Path $root "v$input"
        if (Test-Path $candidate) {
            Show-ShortSpinner "Activating Node version"
            Show-ActivatedNode (Get-Item -LiteralPath $candidate)
            return
        }
        Write-Host "Version v$input not installed."
        return
    }

    try { $major = [int]($input -split '\.')[0] } catch { Write-Error "Invalid version: $Args[1]"; return }
    $installed = Get-ChildItem -Path $root -Directory -ErrorAction SilentlyContinue |
                 Where-Object { $_.Name -match "^v$major\." } | Sort-Object Name -Descending

    if ($installed.Count -gt 1) {
        Write-Host "Multiple installed versions found for major ${major}:"
        for ($i = 0; $i -lt $installed.Count; $i++) {
            Write-Host "  [$($i+1)] $($installed[$i].Name -replace '^v','')"
        }
        while ($true) {
            $sel = Read-Host "Select a version by number (or 'c' to cancel)"
            if ($sel -match '^[cC]') { Write-Host "Cancelled."; return }
            if ($sel -match '^\d+$') {
                $num = [int]$sel
                if ($num -ge 1 -and $num -le $installed.Count) {
                    Show-ShortSpinner "Switching Node version"
                    Show-ActivatedNode $installed[$num-1]
                    return
                }
            }
            Write-Host "Invalid selection."
        }
    } elseif ($installed.Count -eq 1) { 
        Show-ShortSpinner "Activating Node version"
        Show-ActivatedNode $installed[0]
        return
    }
    else { Write-Host "No installed versions found for major $major." }
}

# nvm-install-old: install Node (v15 and below)
function nvm-install-old {
    param([Parameter(Mandatory=$true)][string]$VersionInput)
    $root = Join-Path $global:NVM_ROOT "versions"
    $verClean = ($VersionInput -replace "^v","").Trim()
    $isFull = $verClean -match "\."

    if (-not $isFull) {
        try {
            $index = Invoke-RestMethod -Uri "https://nodejs.org/dist/index.json" -UseBasicParsing -ErrorAction Stop
            $match = $index | Where-Object { $_.version -match "^v$verClean(\.|$)" } | Sort-Object -Property version -Descending | Select-Object -First 1
            if (-not $match) { Write-Error "No releases found for major ${verClean}"; return $false }
            $targetVer = $match.version
        } catch { Write-Error "Failed to query nodejs.org: $($_.Exception.Message)"; return $false }
    } else { $targetVer = "v$verClean" }

    New-Item -ItemType Directory -Force -Path $root | Out-Null
    $targetFolder = Join-Path $root $targetVer
    $zipName = "node-$targetVer-win-x64.zip"
    $url = "https://nodejs.org/dist/$targetVer/$zipName"
    $tempZip = Join-Path $env:TEMP $zipName

    if (Test-Path $targetFolder) {
        Write-Host "Requirement already satisfied."
        Write-Host "`nTo check the list of installed Node versions, type:`n"
        Write-Host "`tnvm list`n"
        return $true
    }

    $existing = Get-ChildItem -Path $root -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match "^v$($verClean)\." } | Sort-Object Name -Descending
    if ($existing.Count -gt 0) {
        Write-Host "Detected installed patch versions for major ${verClean}:"
        $existing | ForEach-Object { Write-Host "  - $($_.Name -replace '^v','')" }
        if (-not (Ask-YesNo "Do you still want to install $targetVer?" $false)) { Write-Host "Installation cancelled."; return $false }
    }

    $downloadOk = $false
    $installOk = $false

    try {
        Write-Host "Installing $targetVer ..."
        Show-ShortSpinner "Downloading $targetVer"
        $tries = 0
        while (-not $downloadOk -and $tries -lt 3) {
            $tries++
            try {
                if (Test-Path $tempZip) { Remove-Item -Force $tempZip -ErrorAction SilentlyContinue }
                Invoke-WebRequest -Uri $url -OutFile $tempZip -UseBasicParsing -ErrorAction Stop
                $downloadOk = $true
            } catch {
                Write-Warning "Download attempt $tries failed: $($_.Exception.Message)"
                Start-Sleep -Seconds (2 * $tries)
            }
        }
        if (-not $downloadOk) { Write-Error "Download failed after $tries attempts"; return $false }

        if (Test-Path $targetFolder) { Remove-Item -Recurse -Force -ErrorAction SilentlyContinue $targetFolder }
        New-Item -ItemType Directory -Path $targetFolder -Force | Out-Null

        Expand-Archive -Path $tempZip -DestinationPath $targetFolder -Force

        $innerDirs = Get-ChildItem -Path $targetFolder -Force | Where-Object { $_.PSIsContainer }
        if ($innerDirs.Count -eq 1) {
            $inner = $innerDirs[0]
            if (Test-Path (Join-Path $inner.FullName "node.exe")) {
                Get-ChildItem -Path $inner.FullName -Force | ForEach-Object { Move-Item -LiteralPath $_.FullName -Destination $targetFolder -Force -ErrorAction SilentlyContinue }
                Remove-Item -Recurse -Force $inner.FullName -ErrorAction SilentlyContinue
            }
        }

        if (Test-Path $tempZip) { Remove-Item -Force $tempZip -ErrorAction SilentlyContinue }
        $installOk = $true

        Write-Host "Installed $targetVer successfully."
        Write-Host "`nTo check the list of installed Node versions, type:`n"
        Write-Host "`tnvm list`n"
        return $true
    } catch {
        Write-Warning "Install interrupted or failed: $($_.Exception.Message)"
        return $false
    } finally {
        if (-not $installOk) {
            $cleanupJobs = @()
            if (Test-Path $targetFolder) { $cleanupJobs += Start-Job { param($tf) Remove-Item -Recurse -Force -LiteralPath $tf } -ArgumentList $targetFolder }
            if (Test-Path $tempZip) { $cleanupJobs += Start-Job { param($tz) Remove-Item -Force -LiteralPath $tz } -ArgumentList $tempZip }
            if ($cleanupJobs.Count -gt 0) { Show-JobSpinner -Jobs $cleanupJobs -Message "Operation Interrupted. Cleaning up" }
        }
    }
}

# nvm install wrapper
function nvm-install-wrapper {
    param([Parameter(ValueFromRemainingArguments=$true)]$Args)
    if (-not $Args) { & "$global:NVM_ROOT\nvm.exe"; return }

    $verArg = ($Args[1] -replace "^v","").Trim()
    try { $major = [int]($verArg -split '\.')[0] } catch { $major = $null }

    if ($major -ne $null -and $major -le 15) {
        if (-not (nvm-install-old $Args[1])) { Write-Host "Installation cancelled."; return }
    } else {
        Show-ShortSpinner "Installing Node version"
        Start-Process -FilePath "$global:NVM_ROOT\nvm.exe" -ArgumentList $Args -NoNewWindow -Wait
    }
}

# nvm uninstall wrapper
function nvm-uninstall-wrapper {
    param([Parameter(ValueFromRemainingArguments=$true)]$Args)
    if (-not $Args) { & "$global:NVM_ROOT\nvm.exe"; return }

    $raw = $Args[1]
    if (-not $raw) { Write-Error "Usage: nvm uninstall <version>"; return }
    $verArg = ($raw -replace "^v","").Trim()
    $root = Join-Path $global:NVM_ROOT "versions"
    $displayVer = $null

    if ($verArg -match "\.") {
        $candidate = "v$verArg"
        $candidatePath = Join-Path $root $candidate
        if (-not (Test-Path $candidatePath)) { Write-Host "Version $candidate not installed."; return }
        $displayVer = $candidate
    } else {
        $installed = Get-ChildItem -Path $root -Directory -ErrorAction SilentlyContinue |
                     Where-Object { $_.Name -match "^v$verArg\." } | Sort-Object Name -Descending

        if ($installed.Count -eq 0) { Write-Host "No installed versions found for major ${verArg}."; return }

        if ($installed.Count -gt 1) {
            Write-Host "Installed patch versions for major ${verArg}:"
            for ($i=0; $i -lt $installed.Count; $i++) {
                Write-Host "  [$($i+1)] $($installed[$i].Name -replace '^v','')"
            }
            while ($true) {
                $sel = Read-Host "Select a version to uninstall by number (or 'c' to cancel)"
                if ($sel -match '^[cC]') { Write-Host "Cancelled."; return }
                if ($sel -match '^\d+$') {
                    $num = [int]$sel
                    if ($num -ge 1 -and $num -le $installed.Count) {
                        $displayVer = $installed[$num-1].Name
                        break
                    }
                }
                Write-Host "Invalid selection."
            }
        } else { $displayVer = $installed[0].Name }
    }

    if (-not $displayVer) { Write-Error "Could not determine version to uninstall."; return }

    $displayLabel = $displayVer -replace '^v',''

    if (-not (Ask-YesNo "Do you want to proceed with uninstalling the Node version ${displayLabel}?" $false)) { Write-Host "Uninstall cancelled."; return }

    $targetFolder = Join-Path $root $displayVer
    if (-not (Test-Path $targetFolder)) { Write-Host "Version ${displayVer} not installed."; return }

    $job = Start-Job -ScriptBlock {
        param($tf)
        try { Remove-Item -Recurse -Force -LiteralPath $tf -ErrorAction Stop; return @{ Path = $tf; Result = $true } } catch { return @{ Path = $tf; Result = $false; Error = $_.Exception.Message } }
    } -ArgumentList $targetFolder

    Show-JobSpinner -Jobs $job -Message "Uninstalling ${displayLabel}. Please wait"

    Wait-Job -Id $job.Id | Out-Null
    $out = Receive-Job -Id $job.Id -ErrorAction SilentlyContinue
    Remove-Job -Id $job.Id -ErrorAction SilentlyContinue

    if ($out -and $out.Result -eq $true) {
        $userPath = [Environment]::GetEnvironmentVariable("Path","User")
        if ($userPath) {
            $parts = $userPath -split ';'
            $cleaned = $parts | Where-Object { ($_ -ne "") -and ($_ -notlike "*\versions\$displayVer*") }
            [Environment]::SetEnvironmentVariable("Path", ($cleaned -join ';'), "User")
        }
        Write-Host "Uninstalled Node $displayLabel"
    } else {
        if ($out -and $out.Result -ne $true) {
            Write-Error "Failed to uninstall $($out.Path). It may be in use by a running process: $($out.Error)"
        } else {
            Write-Error "Failed to uninstall ${displayLabel}. It may be in use by a running process."
        }
    }
}

# master nvm: dispatch commands
function nvm {
    param([Parameter(ValueFromRemainingArguments=$true)]$Args)
    if (-not $Args) { & "$global:NVM_ROOT\nvm.exe"; return }
    $cmd = $Args[0].ToLower()
    switch ($cmd) {
        "install"   { nvm-install-wrapper @Args }
        "use"       { nvm-core @Args }
        "uninstall" { nvm-uninstall-wrapper @Args }
        default     { Start-Process -FilePath "$global:NVM_ROOT\nvm.exe" -ArgumentList $Args -NoNewWindow -Wait }
    }
}