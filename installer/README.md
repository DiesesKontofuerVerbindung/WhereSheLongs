# Where She Longs — Windows Installer & QA

This directory turns the existing Godot Windows export into a conventional offline Windows installer.

## What the installer does

- produces one `WhereSheLongs-Setup-1.3.17.exe`
- lets the player choose the installation directory
- installs per-user by default (no administrator password/UAC required)
- creates a Start Menu shortcut
- optionally creates a desktop shortcut
- adds a normal Windows uninstall entry
- can launch the game immediately after installation
- does not download game content during installation

The installer wraps the existing self-contained Godot export at:

`releases/windows/Where She Longs.exe`

## Build

1. Make sure Git LFS has materialized the real game EXE. The real file is about 1.08 GiB; a ~135 byte file is only the LFS pointer.
2. Install Inno Setup 7.1+ (64-bit recommended), or let the build script install it via winget.
3. From PowerShell:

```powershell
./installer/build-installer.ps1 -InstallInnoSetup
```

Output:

`dist/windows/WhereSheLongs-Setup-1.3.17.exe`

For later builds, once Inno Setup is installed:

```powershell
./installer/build-installer.ps1
```

## Automated chapter verification

The repository already contains Godot 4.7.2 for Windows under `tools/godot/windows/`. Run:

```powershell
./installer/qa-verify.ps1
```

It starts these entry points headlessly and treats non-zero exit codes/timeouts as failures:

- Opening
- Wedding prologue
- Mystic Night
- Forest main story contract
- Chapter 3 ending A
- Chapter 3 ending B
- Chapter 3 ending C

Logs and `summary.csv` are written to `qa-results/`.

Important: Forest `--verify` deliberately simulates embedded minigame completion. This catches missing scenes/signals/story-contract failures, but it does not replace one manual Windows playthrough of parkour physics, LakeJump input, StarJar dragging, and the camera fallbacks.

## Offline distribution

The generated Setup EXE itself has no GitHub dependency. Copy it to USB, LAN/NAS, a school file server, an LMS, or any public download location that the testers can access without a GitHub account.

The current gesture/camera bridges are separate from installation: the core story has keyboard fallbacks, while full hand-camera recognition still depends on a Python environment with MediaPipe on the player's PC unless a portable runtime is bundled in a future release.
