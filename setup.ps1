# Run in PowerShell while signed in to the workshop's Windows account.
function Start-DespinaSetup {
    $ErrorActionPreference = 'Stop'
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    if ($env:OS -ne 'Windows_NT' -or -not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
        throw 'Run this command in Windows PowerShell on a PC with WSL 2 installed.'
    }

    $installed = & wsl.exe --list --quiet
    if ($LASTEXITCODE -ne 0) { throw 'Could not list WSL distributions. Run wsl --list --verbose to check WSL.' }
    $distribution = $installed | ForEach-Object { ($_ -replace "`0", '').Trim() } |
        Where-Object { $_ -match '^(Ubuntu(?:-\d+\.\d+)?|Debian)$' } | Select-Object -First 1
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
    $scriptPath = [IO.Path]::GetTempFileName()
    try {
        Invoke-WebRequest -UseBasicParsing -Uri 'https://raw.githubusercontent.com/thrxpt/tod/main/setup-wsl.sh' -OutFile $scriptPath
        $linuxPath = & wsl.exe --distribution $distribution --user root --exec wslpath -a -u $scriptPath
        if ($LASTEXITCODE -ne 0) { throw 'Could not access the setup script from WSL.' }
        & wsl.exe --distribution $distribution --user root --exec bash $linuxPath.Trim()
        if ($LASTEXITCODE -ne 0) { throw 'WSL workshop setup failed. Review the message above, then run setup again.' }
    }
    finally {
        Remove-Item -Force $scriptPath
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
    Start-Process $url
}

Start-DespinaSetup
