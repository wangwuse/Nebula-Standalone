# NebulaInjector

One-click injector for **Nebula on the Ship** (Among Us mod) on 32-bit IL2CPP builds.

## 🎮 What is this?

Nebula is a popular Among Us mod (BepInEx plugin). The official release bundles **x64 native layers** (winhttp.dll, CoreCLR, dobby.dll), but Among Us runs as **32-bit (x86)** IL2CPP. This causes silent launch failures.

**NebulaInjector** fixes this by:
1. Laying down the Nebula release (managed assemblies are AnyCPU/x86 — fine)
2. Overlaying **official x86 BepInEx 6 IL2CPP native layer** (winhttp.dll, dotnet/, dobby.dll)
3. Cleaning up stray x64 files
4. Generating a rollback manifest for clean uninstall

## ✨ Features

- ✅ **Bitness correction** — auto-replaces x64 native DLLs with x86 equivalents
- ✅ **Zero-config** — auto-detects Among Us install, or specify -GamePath
- ✅ **Safe rollback** — Uninstall restores pre-injection state from manifest
- ✅ **Dry-run** — preview changes without writing
- ✅ **Status check** — verifies arch match, plugin presence, doorstop config
- ✅ **Batch wrapper** — NebulaInject.bat for double-click UX

## 📦 Requirements

- Among Us (32-bit IL2CPP, Unity 2022.3.x) — tested on build 2026/8/19 (Steam 945360)
- Windows 10/11 (x64 OS, 32-bit game)
- PowerShell 5.1+ (built-in)
- **Official x86 BepInEx 6 IL2CPP package** — BepInEx-Unity.IL2CPP-win-x86-6.0.0-be.783.zip (from builds.bepinex.dev)
- **Nebula release zip** — Nebula.zip (from Dolly1016/Nebula releases)

## 🚀 Quick Start

### Option A: Double-click (easiest)

1. Place Nebula.zip and BepInEx-Unity.IL2CPP-win-x86-6.0.0-be.783.zip in .\packages\
2. Run NebulaInject.bat as **Administrator**
3. Wait for [OK] Install finished + status check
4. Launch Among Us.exe — first run takes 1–3 min (IL2CPP interop generation)

### Option B: PowerShell (explicit)

`powershell
# Status check (read-only)
powershell -NoProfile -ExecutionPolicy Bypass -File NebulaInjector.ps1 -Action Status -GamePath "C:\Among_92595"

# Install
powershell -NoProfile -ExecutionPolicy Bypass -File NebulaInjector.ps1 -Action Install -GamePath "C:\Among_92595"

# Uninstall (full rollback)
powershell -NoProfile -ExecutionPolicy Bypass -File NebulaInjector.ps1 -Action Uninstall -GamePath "C:\Among_92595"

# Dry run (preview)
powershell -NoProfile -ExecutionPolicy Bypass -File NebulaInjector.ps1 -Action DryRun -GamePath "C:\Among_92595"
`

## 📁 Repository Structure

`
NebulaInjector/
├── NebulaInjector.ps1          # Main injector script
├── NebulaInject.bat            # Double-click installer (install/status/uninstall)
├── NebulaDist.bat              # Creates distributable zip (mod + injector + readme)
├── packages/                   # Put your zips here (gitignored)
│   ├── Nebula.zip
│   └── BepInEx-Unity.IL2CPP-win-x86-*.zip
└── docs/
    └── USAGE.md                # Detailed usage guide
`

## ⚙️ Configuration

After install, Nebula's loader config at BepInEx/config/jp.dreamingpig.amongus.nebula.loader.cfg is set to:

`ini
SkipCheckingConsistency = true
AutoUpdate = false
AutoUpdateIfVersionMismatching = false
AllowHttpCommunication = false
`

This disables the SSL update check that fails on restricted networks. To re-enable auto-updates, set AutoUpdate = true.

## 🔧 How it works (technical)

| Layer | Source | Arch |
|-------|--------|------|
| Managed plugins (Nebula.dll, NebulaLoader.dll, BepInEx.Core.dll, 0Harmony.dll) | Nebula.zip | AnyCPU / x86 (CLR handles) |
| winhttp.dll (Doorstop shim) | **BepInEx x86 package** | **x86** |
| dotnet/ (CoreCLR, clrjit, hostpolicy, mscordaccore, etc.) | **BepInEx x86 package** | **x86** |
| BepInEx/core/dobby.dll | **BepInEx x86 package** | **x86** |
| Stray x64 files (DiaSymReader, mscordaccore_amd64) | — | **Deleted** |

The game executable (Among Us.exe) and GameAssembly.dll are **never modified**.

## 🗂️ Rollback Manifest

Each install creates a timestamped backup under:
`
<GamePath>\_NebulaInjectorBackup\install_YYYYMMDD_HHMMSS\manifest.json
`

Contains:
- Injector version & timestamp
- Game path & bitness
- Source zip filenames
- List of moved/created entries
- Native layer fixes applied

Uninstall reads this manifest to delete injected files and restore originals.

## 📄 License

MIT License — see [LICENSE](LICENSE).

## ⚠️ Disclaimer

- This tool modifies your game installation. **Backup your game folder first.**
- Nebula mod itself is by [Dolly1016](https://github.com/Dolly1016/Nebula). This injector only handles the bitness-correct deployment.
- Not affiliated with Innersloth, BepInEx, or Nebula authors.
- Use at your own risk. Online play with mods may violate Terms of Service.

## 🙏 Credits

- **Nebula mod**: Dolly1016 / Nebula team
- **BepInEx**: BepInEx contributors (x86 IL2CPP build 6.0.0-be.783)
- **Doorstop**: NeighTools / Doorstop team
