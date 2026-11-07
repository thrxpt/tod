# Operation Neptune — Windows setup

Run setup while signed in to the Windows account used for the workshop. Each PC needs an initialized **Ubuntu or Debian distribution on WSL 2** and internet access. Setup selects the first installed distribution named `Ubuntu`, `Ubuntu-<version>`, or `Debian`. Check the distributions and their WSL versions with `wsl --list --verbose`.

## Install and open

Open **PowerShell** and paste this command.

```powershell
irm https://raw.githubusercontent.com/thrxpt/tod/main/setup.ps1 | iex
```

Setup installs Docker Engine and its CLI inside the selected distribution using its `docker.io` package. It starts the Docker service, downloads and builds the workshop, then opens **http://localhost:7681**. The script uses WSL's root account for Linux package installation. Windows administrator elevation is unnecessary for an existing working WSL 2 installation.

The workshop opens in a full-screen Microsoft Edge window, or Google Chrome if Edge is unavailable. If neither browser is installed, it opens in the default browser; press F11 to enter full screen.

The workshop Terminal displays `engineer@despina-control`. New containers use `despina-control` as their hostname. Setup updates the visible prompt in existing workshop containers while preserving their mission progress.

If the selected distribution uses WSL 1, setup stops with the conversion command. If Ubuntu or Debian is missing, setup provides the installation command. Complete that preparation and run setup again.

You can also copy `setup.ps1` to a PC and run it locally. It downloads the companion `setup-wsl.sh` from this repository.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\setup.ps1
```

## Reopen and preserve progress

Setup creates **Start Despina Workshop.cmd** on the current Windows user's Desktop, including a redirected OneDrive Desktop. Double-click it to start Docker in WSL, reopen the existing workshop, and launch the browser after restarting Windows. The desktop script uses local startup files in `%LOCALAPPDATA%\DespinaWorkshop` and the WSL distribution chosen during setup. Reopening an installed container works offline.

Run the online setup command again to refresh these local startup files. It downloads current workshop source only when creating a new container.

Setup keeps a background WSL session running so the workshop stays available after the PowerShell window closes. Signing out, restarting Windows, or running `wsl --shutdown` ends that session. Run setup again to reopen the workshop.

Each PC and WSL distribution has separate workshop storage. Removing the workshop container, unregistering its WSL distribution, or deleting Docker's data removes its progress.

If a previous workshop was created using Docker Desktop, that container remains in Docker Desktop's separate engine. This installer creates its own container inside WSL and does not migrate that earlier progress. Disable Docker Desktop's WSL integration for the selected distribution before installing a local engine. Close the old workshop if it occupies port 7681.

## Update to the latest GitHub version

Push the updated files to this repository's `main` branch first. On the workshop PC, open **Start Despina Workshop.cmd** to start Docker, then run the commands below in **PowerShell**. Replace `Ubuntu` with the WSL distribution used during setup (`wsl --list --verbose` lists the installed distributions).

**This deletes the existing workshop container and all mission progress, including learner files and checkpoints. Save anything you need before continuing.** Setup then downloads the latest source from GitHub and builds a new container.

```powershell
wsl -d Ubuntu -u root -- docker --host unix:///var/run/docker.sock rm -f despina-workshop
if ($LASTEXITCODE -eq 0) {
    irm https://raw.githubusercontent.com/thrxpt/tod/main/setup.ps1 | iex
}
```

## Before the workshop

Test one Windows PC first, then run setup on the remaining PCs. Check that the Terminal accepts commands, `mission-status` works, and the Dream Capsule API accepts a test submission. Setup checks that Windows can open the workshop page. WSL's localhost forwarding must be enabled for this to work.

## References

- [Microsoft WSL distribution and version commands](https://learn.microsoft.com/en-us/windows/wsl/basic-commands)
- [Accessing WSL applications from Windows with localhost](https://learn.microsoft.com/en-us/windows/wsl/networking#accessing-linux-networking-apps-from-windows-localhost)
