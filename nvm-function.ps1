function nvm {
    param([Parameter(ValueFromRemainingArguments=$true)]$Args)

    $NVM_ROOT = "C:\nvm"

    if (-not $Args) { & "$NVM_ROOT\nvm.exe"; return }

    $command = $Args[0].ToLower()

    if ($command -eq "use") {
        if ($Args.Count -lt 2) { Write-Error "Usage: nvm use <version>"; return }

        # Remove leading 'v' if user typed it
        $Version = $Args[1] -replace "^v",""

        $root = Join-Path $NVM_ROOT "versions"

        # Match folder starting with requested major version, pick latest patch
        $folder = Get-ChildItem -Path $root -Directory |
                  Where-Object { $_.Name -match "^v$Version(\.|$)" } |
                  Sort-Object Name -Descending |
                  Select-Object -First 1

        if (-not $folder) { Write-Error "Node version $Version not found in $root"; return }

        $nodePath = Join-Path $root $folder.Name

        # ===== Persisted User PATH =====
        $userPathVar = [Environment]::GetEnvironmentVariable("Path","User")
        $pathParts = $userPathVar -split ';' | Where-Object { ($_ -notlike "$NVM_ROOT\versions\*") }
        $newUserPath = $nodePath + ';' + ($pathParts -join ';')
        [Environment]::SetEnvironmentVariable("Path",$newUserPath,"User")

        # ===== Current session PATH =====
        $envPathParts = $env:PATH -split ';'
        $cleanedPathParts = $envPathParts | Where-Object { ($_ -notlike "$NVM_ROOT\versions\*") -and ($_ -notlike "*\nodejs*") }
        $env:PATH = $nodePath + ';' + ($cleanedPathParts -join ';')

        Write-Host "Activated Node version $($folder.Name) [$nodePath]"
    }
    else {
        # Forward all other commands to original nvm.exe
        Start-Process -FilePath "$NVM_ROOT\nvm.exe" -ArgumentList $Args -NoNewWindow -Wait
    }
}