# Run in PowerShell while signed in to the workshop's Windows account.
function Start-DespinaSetup {
    param([switch]$UseCachedScript, [string]$DistributionName)

    $ErrorActionPreference = 'Stop'
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    if ($env:OS -ne 'Windows_NT' -or -not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
        throw 'Run this command in Windows PowerShell on a PC with WSL 2 installed.'
    }

    $installed = & wsl.exe --list --quiet
    if ($LASTEXITCODE -ne 0) { throw 'Could not list WSL distributions. Run wsl --list --verbose to check WSL.' }
    $installed = @($installed | ForEach-Object { ($_ -replace "`0", '').Trim() })
    if ($DistributionName) {
        if ($installed -notcontains $DistributionName) { throw "WSL distribution $DistributionName was not found." }
        $distribution = $DistributionName
    }
    else {
        $distribution = $installed | Where-Object { $_ -match '^(Ubuntu(?:-\d+\.\d+)?|Debian)$' } | Select-Object -First 1
    }
    if (-not $distribution) {
        throw 'Install Ubuntu in WSL with wsl --install -d Ubuntu, open it once to complete setup, then run this command again.'
    }
    $details = (& wsl.exe --list --verbose | Out-String) -replace "`0", ''
    if ($LASTEXITCODE -ne 0) { throw 'Could not check the WSL version.' }
    $versionPattern = '(?m)^\s*\*?\s*' + [regex]::Escape($distribution) + '\s+.+\s+2\s*$'
    if ($details -notmatch $versionPattern) {
        throw "The distribution must use WSL 2. Check wsl --list --verbose, then convert it with wsl --set-version $distribution 2."
    }

    Write-Host "Setting up Docker Engine and the workshop in $distribution..."
    $installDirectory = Join-Path $env:LOCALAPPDATA 'DespinaWorkshop'
    $scriptPath = Join-Path $installDirectory 'setup-wsl.sh'
    if (-not $UseCachedScript) {
        New-Item -ItemType Directory -Path $installDirectory -Force | Out-Null
        $downloadPath = Join-Path $installDirectory ([guid]::NewGuid().ToString())
        try {
            Invoke-WebRequest -UseBasicParsing -Uri 'https://raw.githubusercontent.com/thrxpt/tod/main/setup-wsl.sh' -OutFile $downloadPath
            Move-Item -Path $downloadPath -Destination $scriptPath -Force
        }
        finally {
            if (Test-Path $downloadPath) { Remove-Item -Force $downloadPath }
        }
    }
    elseif (-not (Test-Path $scriptPath)) {
        throw 'The local startup script is missing. Run the online setup command again.'
    }
    $linuxPath = & wsl.exe --distribution $distribution --user root --exec wslpath -a -u $scriptPath
    if ($LASTEXITCODE -ne 0) { throw 'Could not access the setup script from WSL.' }
    & wsl.exe --distribution $distribution --user root --exec bash $linuxPath.Trim()
    if ($LASTEXITCODE -ne 0) { throw 'WSL workshop setup failed. Review the message above, then run setup again.' }

    [IO.File]::WriteAllText((Join-Path $installDirectory 'distribution.txt'), $distribution, (New-Object Text.UTF8Encoding($false)))

    if (-not $UseCachedScript) {
        $launcherPath = Join-Path $installDirectory 'start.ps1'
        $quotedDistribution = $distribution.Replace("'", "''")
        $launcher = "function Start-DespinaSetup {`n" + ${function:Start-DespinaSetup}.ToString() + "`n}`nStart-DespinaSetup -UseCachedScript -DistributionName '$quotedDistribution'`n"
        [IO.File]::WriteAllText($launcherPath, $launcher, (New-Object Text.UTF8Encoding($false)))
        $desktop = [Environment]::GetFolderPath('DesktopDirectory')
        if (-not $desktop) { throw 'The Windows Desktop folder could not be found.' }
        $desktopScript = Join-Path $desktop 'Start Despina Workshop.cmd'
        $commands = @(
            '@echo off',
            'powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%LOCALAPPDATA%\DespinaWorkshop\start.ps1"',
            'if errorlevel 1 pause'
        ) -join "`r`n"
        [IO.File]::WriteAllText($desktopScript, ($commands + "`r`n"), [Text.Encoding]::ASCII)
        Write-Host "Desktop startup script created at $desktopScript"
    }

    # Keep WSL active after this setup window closes.
    $sessionId = (Get-Process -Id $PID).SessionId
    $keepAlivePattern = '--distribution\s+' + [regex]::Escape($distribution) + '\s+--user\s+root\s+--exec\s+sleep\s+infinity\s*$'
    $keepAlive = Get-CimInstance Win32_Process -Filter "Name='wsl.exe'" |
        Where-Object { $_.SessionId -eq $sessionId -and $_.CommandLine -match $keepAlivePattern }
    if (-not $keepAlive) {
        Start-Process wsl.exe -WindowStyle Hidden -ArgumentList @('--distribution', $distribution, '--user', 'root', '--exec', 'sleep', 'infinity')
    }

    $url = 'http://localhost:7681'
    $ready = $false
    for ($attempt = 0; $attempt -lt 20; $attempt++) {
        try {
            $response = Invoke-WebRequest -UseBasicParsing -Uri $url -TimeoutSec 3
            $ready = $response.StatusCode -eq 200
        }
        catch { $ready = $false }
        if ($ready) { break }
        Start-Sleep -Seconds 2
    }
    if (-not $ready) {
        throw "The workshop is running in WSL but Windows cannot reach $url. Check WSL localhost forwarding and wsl -d $distribution -u root -- docker logs despina-workshop."
    }
    Write-Host "Workshop ready at $url" -ForegroundColor Green
    $browser = $null
    foreach ($exe in @('msedge.exe', 'chrome.exe')) {
        foreach ($root in @('HKCU:\Software\Microsoft\Windows\CurrentVersion\App Paths', 'HKLM:\Software\Microsoft\Windows\CurrentVersion\App Paths')) {
            $candidate = (Get-ItemProperty -LiteralPath "$root\$exe" -ErrorAction SilentlyContinue).'(default)'
            if ($candidate -and (Test-Path -LiteralPath $candidate)) {
                $browser = $candidate
                break
            }
        }
        if ($browser) { break }
    }
    if ($browser) {
        Start-Process -FilePath $browser -ArgumentList @('--new-window', '--start-fullscreen', $url)
    }
    else {
        Write-Warning 'Microsoft Edge or Google Chrome was not found. Opening the default browser; press F11 for full screen.'
        Start-Process $url
    }
}

Start-DespinaSetup
