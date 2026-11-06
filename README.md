# Operation Neptune — Windows setup

Run setup on each workshop PC while signed in to the Windows account that will be used during the workshop. Supported machines are Intel/AMD 64-bit Windows PCs that meet [Docker Desktop requirements](https://docs.docker.com/desktop/setup/install/windows-install/). Enable hardware virtualization in BIOS/UEFI first.

## Install

After `setup.ps1` is published to the `main` branch of this repository, open **Windows PowerShell → Run as administrator** and paste this command.

```powershell
irm https://raw.githubusercontent.com/thrxpt/tod/main/setup.ps1 | iex
```

Setup enables Windows virtualization, installs or updates WSL 2, installs Docker Desktop through `winget` when needed, then downloads, builds, and starts the workshop. Complete the installer and any first-run prompts. If setup requests a restart, restart Windows and run the same command again. WSL installation may require more than one pass on a new PC.

The script uses `winget install --id Docker.DockerDesktop --exact --source winget --interactive`. If `winget` is unavailable, install or update **App Installer** from Microsoft Store first.

When ready, setup opens **http://localhost:7681**. Each PC has its own mission files and checkpoints.

You can also copy `setup.ps1` to each PC and run it locally from an administrator PowerShell window.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\setup.ps1
```

## Reopen the workshop

Start Docker Desktop, then open **http://localhost:7681**. Rerunning setup starts the existing workshop container and preserves its mission progress. The installer downloads current source only when creating a new workshop container.

Mission files and checkpoints remain in that container across restarts. Removing the container or resetting Docker Desktop storage removes that progress.

## Before the workshop

Check each PC can type commands in the Terminal, run `mission-status`, and reach the Dream Capsule API. Build and page startup are checked by setup. API submission requires a separate live test.

## References

- [Docker Desktop installation and first-run requirements](https://docs.docker.com/desktop/setup/install/windows-install/)
- [WSL installation options](https://learn.microsoft.com/en-us/windows/wsl/basic-commands#install)
