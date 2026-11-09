param([switch]$UseCachedScript, [string]$DistributionName)

# Run in PowerShell while signed in to the workshop's Windows account.
function Start-DespinaUnsetup {
    param([switch]$UseCachedScript, [string]$DistributionName)

    $ErrorActionPreference = 'Stop'
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    if ($env:OS -ne 'Windows_NT' -or -not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
        throw 'Run this command in Windows PowerShell on a PC with WSL 2 installed.'
    }

    $installed = & wsl.exe --list --quiet
    if ($LASTEXITCODE -ne 0) { throw 'Could not list WSL distributions. Run wsl --list --verbose to check WSL.' }
    $installed = @($installed | ForEach-Object { ($_ -replace "`0", '').Trim() })
    $installDirectory = Join-Path $env:LOCALAPPDATA 'DespinaWorkshop'
    if ($DistributionName) {
        if ($installed -notcontains $DistributionName) { throw "WSL distribution $DistributionName was not found." }
        $distribution = $DistributionName
    }
    else {
        $distributionFile = Join-Path $installDirectory 'distribution.txt'
        if (Test-Path -LiteralPath $distributionFile) {
            $savedDistribution = [IO.File]::ReadAllText($distributionFile).Trim()
            if ($installed -notcontains $savedDistribution) {
                throw "The setup distribution $savedDistribution was not found. Check wsl --list --verbose or pass -DistributionName."
            }
            $distribution = $savedDistribution
        }
        else {
            # Older setup versions kept the selected distribution in their desktop launcher.
            $launcherPath = Join-Path $installDirectory 'start.ps1'
            if (Test-Path -LiteralPath $launcherPath) {
                $launcher = [IO.File]::ReadAllText($launcherPath)
                $launcherPattern = "(?m)^Start-DespinaSetup -UseCachedScript -DistributionName '((?:[^']|'')*)'\s*$"
                if ($launcher -match $launcherPattern) {
                    $savedDistribution = $Matches[1].Replace("''", "'")
                    if ($installed -notcontains $savedDistribution) {
                        throw "The setup distribution $savedDistribution was not found. Check wsl --list --verbose or pass -DistributionName."
                    }
                    $distribution = $savedDistribution
                }
            }
            if (-not $distribution) {
                $distribution = $installed | Where-Object { $_ -match '^(Ubuntu(?:-\d+\.\d+)?|Debian)$' } | Select-Object -First 1
            }
        }
    }
    if (-not $distribution) {
        throw 'No Ubuntu or Debian WSL distribution was found. Pass -DistributionName if setup used another distribution name.'
    }

    $details = (& wsl.exe --list --verbose | Out-String) -replace "`0", ''
    if ($LASTEXITCODE -ne 0) { throw 'Could not check the WSL version.' }
    $versionPattern = '(?m)^\s*\*?\s*' + [regex]::Escape($distribution) + '\s+.+\s+2\s*$'
    if ($details -notmatch $versionPattern) {
        throw "The distribution must use WSL 2. Check wsl --list --verbose, then convert it with wsl --set-version $distribution 2."
    }

    Write-Host 'Removing the workshop container and all mission progress.' -ForegroundColor Yellow
    Write-Host 'This removes this account''s workshop launcher and local setup scripts. Docker Engine and other Docker data remain installed.'

    $scriptPath = Join-Path $installDirectory 'unsetup-wsl.sh'
    if (-not $UseCachedScript) {
        New-Item -ItemType Directory -Path $installDirectory -Force | Out-Null
        $downloadPath = Join-Path $installDirectory ([guid]::NewGuid().ToString())
        try {
            Invoke-WebRequest -UseBasicParsing -Uri 'https://raw.githubusercontent.com/thrxpt/tod/main/unsetup-wsl.sh' -OutFile $downloadPath
            Move-Item -Path $downloadPath -Destination $scriptPath -Force
        }
        finally {
            if (Test-Path -LiteralPath $downloadPath) { Remove-Item -Force $downloadPath }
        }
    }
    elseif (-not (Test-Path -LiteralPath $scriptPath)) {
        throw 'The local un-setup script is missing. Run the online un-setup command again.'
    }

    $linuxPath = & wsl.exe --distribution $distribution --user root --exec wslpath -a -u $scriptPath
    if ($LASTEXITCODE -ne 0) { throw 'Could not access the un-setup script from WSL.' }
    $linuxPath = (($linuxPath | Out-String) -replace "`0", '').Trim()
    & wsl.exe --distribution $distribution --user root --exec bash $linuxPath
    if ($LASTEXITCODE -ne 0) { throw 'WSL workshop un-setup failed. Review the message above, then resolve it and run un-setup again.' }

    $sessionId = (Get-Process -Id $PID).SessionId
    $keepAlivePattern = '--distribution\s+' + [regex]::Escape($distribution) + '\s+--user\s+root\s+--exec\s+sleep\s+infinity\s*$'
    Get-CimInstance Win32_Process -Filter "Name='wsl.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.SessionId -eq $sessionId -and $_.CommandLine -match $keepAlivePattern } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

    $desktop = [Environment]::GetFolderPath('DesktopDirectory')
    if ($desktop) {
        $desktopScript = Join-Path $desktop 'Start Despina Workshop.cmd'
        if (Test-Path -LiteralPath $desktopScript) {
            $desktopCommands = [IO.File]::ReadAllText($desktopScript)
            if ($desktopCommands.Contains('powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%LOCALAPPDATA%\DespinaWorkshop\start.ps1"')) {
                Remove-Item -LiteralPath $desktopScript -Force
            }
            else {
                Write-Warning "The desktop file was left in place because its contents do not match the workshop launcher: $desktopScript"
            }
        }
    }

    foreach ($fileName in @('setup-wsl.sh', 'unsetup-wsl.sh', 'start.ps1', 'distribution.txt')) {
        $path = Join-Path $installDirectory $fileName
        if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force }
    }
    if ((Test-Path -LiteralPath $installDirectory -PathType Container) -and
        -not (Get-ChildItem -LiteralPath $installDirectory -Force | Select-Object -First 1)) {
        Remove-Item -LiteralPath $installDirectory -Force
    }

    Write-Host 'Workshop un-setup complete. Docker Engine and unrelated Docker data were left in place.' -ForegroundColor Green
}

Start-DespinaUnsetup -UseCachedScript:$UseCachedScript -DistributionName $DistributionName
