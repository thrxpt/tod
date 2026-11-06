# Run in Windows PowerShell as administrator, using the workshop's Windows account.
function Start-DespinaSetup {
    $ErrorActionPreference = 'Stop'
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    if ($env:OS -ne 'Windows_NT' -or -not [Environment]::Is64BitProcess) {
        throw 'Use 64-bit Windows PowerShell on Windows 10 or Windows 11.'
    }
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Open Windows PowerShell with Run as administrator, then run this command again.'
    }
    if ($env:PROCESSOR_ARCHITECTURE -ne 'AMD64') {
        throw 'This installer supports Windows PCs with Intel or AMD 64-bit processors.'
    }
    $computer = Get-CimInstance Win32_ComputerSystem
    $processor = Get-CimInstance Win32_Processor | Select-Object -First 1
    if (-not $computer.HypervisorPresent -and $processor.VirtualizationFirmwareEnabled -eq $false) {
        throw 'Enable hardware virtualization in BIOS/UEFI, then run setup again.'
    }

    $feature = Get-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform
    if ($feature.State -ne 'Enabled') {
        Write-Host 'Enabling the Windows virtualization platform...'
        Enable-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -All -NoRestart | Out-Null
        Write-Host 'Restart Windows, then run the same setup command again.' -ForegroundColor Yellow
        return
    }

    $ErrorActionPreference = 'Continue'
    $wslVersion = & wsl.exe --version 2>&1 | Out-String
    $wslExitCode = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'
    $versionMatch = [regex]::Match(($wslVersion -replace "`0", ''), '\d+\.\d+\.\d+')
    if ($wslExitCode -ne 0 -or -not $versionMatch.Success) {
        Write-Host 'Installing WSL 2...'
        & wsl.exe --install --no-distribution --web-download
        if ($LASTEXITCODE -notin @(0, 3010)) { throw 'WSL installation failed. Review the message above.' }
        Write-Host 'Restart Windows, then run the same setup command again.' -ForegroundColor Yellow
        return
    }
    if ([version]$versionMatch.Value -lt [version]'2.1.5') {
        & wsl.exe --update --web-download
        if ($LASTEXITCODE -notin @(0, 3010)) { throw 'WSL update failed.' }
        Write-Host 'Restart Windows, then run the same setup command again.' -ForegroundColor Yellow
        return
    }

    $desktopPaths = @(
        "$env:ProgramFiles\Docker\Docker\Docker Desktop.exe",
        "$env:LOCALAPPDATA\Programs\DockerDesktop\Docker Desktop.exe"
    )
    $desktop = $desktopPaths | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $desktop) {
        if (-not (Get-Command winget.exe -ErrorAction SilentlyContinue)) {
            throw 'Install or update App Installer from Microsoft Store to enable winget, then run setup again.'
        }
        Write-Host 'Installing Docker Desktop with winget. Complete any installer prompts.'
        & winget.exe install --id Docker.DockerDesktop --exact --source winget --interactive
        if ($LASTEXITCODE -notin @(0, 3010)) { throw 'Docker Desktop installation failed or was cancelled.' }
        if ($LASTEXITCODE -eq 3010) {
            Write-Host 'Restart Windows, then run the same setup command again.' -ForegroundColor Yellow
            return
        }
        $desktop = $desktopPaths | Where-Object { Test-Path $_ } | Select-Object -First 1
    }
    if (-not $desktop) { throw 'Docker Desktop was not found after installation.' }

    $docker = Join-Path (Split-Path $desktop) 'resources\bin\docker.exe'
    if (-not (Test-Path $docker)) { throw 'Docker CLI was not found. Repair the Docker Desktop installation.' }
    Start-Process -FilePath $desktop
    Write-Host 'Waiting for Docker Desktop. Complete any first-run prompts in its window.'
    $deadline = (Get-Date).AddMinutes(3)
    $engine = ''
    do {
        # Failed readiness probes are expected while Docker Desktop starts.
        $ErrorActionPreference = 'Continue'
        $engine = & $docker --context desktop-linux info --format '{{.OSType}}' 2>$null
        $dockerExitCode = $LASTEXITCODE
        $ErrorActionPreference = 'Stop'
        if ($dockerExitCode -eq 0 -and $engine -eq 'linux') { break }
        Start-Sleep -Seconds 3
    } while ((Get-Date) -lt $deadline)
    if ($dockerExitCode -ne 0 -or $engine -ne 'linux') {
        throw 'Docker is not ready. Open Docker Desktop, complete its setup, then run this command again.'
    }

    $containerName = 'despina-workshop'
    $containerId = & $docker --context desktop-linux ps -aq --filter "name=^/$containerName$"
    if ($LASTEXITCODE -ne 0) { throw 'Could not check existing workshop containers.' }
    if ($containerId) {
        $labelsJson = & $docker --context desktop-linux inspect --format '{{json .Config.Labels}}' $containerName
        if ($LASTEXITCODE -ne 0) { throw 'Could not inspect the existing workshop container.' }
        $labels = $labelsJson | ConvertFrom-Json
        if ($labels.'com.despina.workshop' -ne 'true') {
            throw 'A container named despina-workshop already exists and was not created by this installer.'
        }
        & $docker --context desktop-linux start $containerName
        if ($LASTEXITCODE -ne 0) { throw 'Could not start the existing workshop container.' }
    }
    else {
        $sourceDirectory = Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path $sourceDirectory | Out-Null
        try {
            $archive = Join-Path $sourceDirectory 'workshop.zip'
            Write-Host 'Downloading and building the workshop...'
            Invoke-WebRequest -UseBasicParsing -Uri 'https://github.com/thrxpt/tod/archive/refs/heads/main.zip' -OutFile $archive
            Expand-Archive -Path $archive -DestinationPath $sourceDirectory
            & $docker --context desktop-linux build --tag despina-workshop:local (Join-Path $sourceDirectory 'tod-main')
            if ($LASTEXITCODE -ne 0) { throw 'Workshop image build failed.' }
            & $docker --context desktop-linux run -d --name $containerName --label com.despina.workshop=true --restart unless-stopped -p 127.0.0.1:7681:7681 despina-workshop:local
            if ($LASTEXITCODE -ne 0) { throw 'Could not start the workshop. Check whether port 7681 is already in use.' }
        }
        finally {
            Remove-Item -Recurse -Force $sourceDirectory
        }
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
    if (-not $ready) { throw 'The workshop page did not start. Check docker logs despina-workshop in Docker Desktop.' }
    Write-Host "Workshop ready at $url" -ForegroundColor Green
    Start-Process $url
}

Start-DespinaSetup
