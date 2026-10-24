<#
.SYNOPSIS
    Nebula on the Ship 注入器 / 卸载器（Among Us + BepInEx 6 IL2CPP + Doorstop）

.DESCRIPTION
    给 32 位 Unity IL2CPP 的 Among Us 铺上 BepInEx 6 注入层并加载 Nebula。
    注入器做四件事：
      1. 识别游戏目录并校验 PE 位数（原生层必须与游戏同位）
      2. 备份并移走旧的注入层（BepInEx / dotnet / winhttp.dll / doorstop_config.ini）
      3. 铺设 Nebula 内容（Nebula.dll + NebulaLoader.dll）
      4. 用同位位的 Doorstop + CoreCLR 覆盖原生层，并清理错位文件

    之所以需要第 4 步：Nebula 官方发布包的原生层是 x64，而 Among Us 是 32 位，
    直接铺进去 winhttp.dll 会被 32 位进程拒绝加载，游戏静默不起。

.PARAMETER Action
    Status    只体检，不写盘
    DryRun    打印完整计划，不写盘
    Install   执行注入
    Uninstall 按清单回滚到注入前状态

.PARAMETER GamePath
    游戏根目录（含 Among Us.exe 与 GameAssembly.dll）

.PARAMETER NebulaZip
    Nebula 发布包，默认 .\packages\Nebula.zip

.PARAMETER BepInExZip
    官方 BepInEx 6 IL2CPP 包（取其中的原生层），默认 .\packages\BepInEx-Unity.IL2CPP-win-x86-*.zip

.EXAMPLE
    .\NebulaInjector.ps1 -Action Status -GamePath 'C:\Among_92595'
    .\NebulaInjector.ps1 -Action Install -GamePath 'C:\Among_92595'
    .\NebulaInjector.ps1 -Action Uninstall -GamePath 'C:\Among_92595'

.NOTES
    只改游戏目录，不写注册表、不碰存档。回滚依赖注入时生成的 manifest.json。
#>
[CmdletBinding()]
param(
    [ValidateSet('Status', 'DryRun', 'Install', 'Uninstall')]
    [string]$Action = 'Status',

    [string]$GamePath,

    [string]$NebulaZip,

    [string]$BepInExZip,

    [switch]$AllowRunning,

    [switch]$SkipBitnessFix
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# ---------------------------------------------------------------- 常量

$Script:InjectorVersion  = '1.0.0'
$Script:BackupFolderName = '_NebulaInjectorBackup'
$Script:ManifestName     = 'manifest.json'

$Script:LayerEntries = @(
    'winhttp.dll'
    'doorstop_config.ini'
    '.doorstop_version'
    'steam_appid.txt'
    'BepInEx'
    'dotnet'
)

$Script:NebulaEntries = @('Addons')

$Script:MustMatchBitness = @(
    'winhttp.dll'
    'dotnet/coreclr.dll'
    'dotnet/clrjit.dll'
    'dotnet/hostpolicy.dll'
    'dotnet/System.Private.CoreLib.dll'
    'dotnet/mscordaccore.dll'
    'dotnet/System.IO.Compression.Native.dll'
    'BepInEx/core/dobby.dll'
)

$Script:WrongArchPatterns = @(
    'dotnet\Microsoft.DiaSymReader.Native.amd64.dll'
    'dotnet\mscordaccore_amd64_*.dll'
)

# ---------------------------------------------------------------- 输出

function Write-Head([string]$Text)   { Write-Host ''; Write-Host "== $Text" -ForegroundColor Cyan }
function Write-Ok([string]$Text)     { Write-Host "   [ OK ] $Text" -ForegroundColor Green }
function Write-Info([string]$Text)   { Write-Host "   [ .. ] $Text" -ForegroundColor Gray }
function Write-Warn2([string]$Text)  { Write-Host "   [WARN] $Text" -ForegroundColor Yellow }
function Write-Err2([string]$Text)   { Write-Host "   [FAIL] $Text" -ForegroundColor Red }

# ---------------------------------------------------------------- PE 工具

function Get-PEMachine([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return 0 }
    $fs = $null
    try {
        $fs = [System.IO.File]::Open($Path, 'Open', 'Read', 'ReadWrite')
        if ($fs.Length -lt 0x40) { return 0 }
        $br = New-Object System.IO.BinaryReader($fs)
        $fs.Position = 0x3C
        $peOff = $br.ReadInt32()
        if ($peOff -le 0 -or ($peOff + 6) -ge $fs.Length) { return 0 }
        $fs.Position = $peOff
        if ($br.ReadUInt32() -ne 0x00004550) { return 0 }
        return [int]$br.ReadUInt16()
    }
    catch { return 0 }
    finally { if ($fs) { $fs.Dispose() } }
}

function Format-Machine([int]$Machine) {
    switch ($Machine) {
        0x014c  { 'x86' }
        0x8664  { 'x64' }
        0xaa64  { 'arm64' }
        default { if ($Machine -eq 0) { 'n/a' } else { '0x{0:x}' -f $Machine } }
    }
}

function Test-ManagedAssembly([string]$Path) {
    $fs = $null
    try {
        $fs = [System.IO.File]::Open($Path, 'Open', 'Read', 'ReadWrite')
        $br = New-Object System.IO.BinaryReader($fs)
        $fs.Position = 0x3C
        $peOff = $br.ReadInt32()
        $fs.Position = $peOff + 24
        $magic = $br.ReadUInt16()
        $ddOff = $peOff + 24 + $(if ($magic -eq 0x20b) { 0x70 } else { 0x60 })
        $fs.Position = $ddOff + (14 * 8)
        return ($br.ReadUInt32() -ne 0)
    }
    catch { return $false }
    finally { if ($fs) { $fs.Dispose() } }
}

# ---------------------------------------------------------------- 游戏探测

function Find-GamePath {
    Write-Info '自动探测 Among Us 安装目录…'
    $roots = @()
    foreach ($d in [System.IO.DriveInfo]::GetDrives()) {
        if ($d.IsReady -and $d.DriveType -eq 'Fixed') { $roots += $d.RootDirectory.FullName }
    }

    $hits = @()
    foreach ($r in $roots) {
        foreach ($p in @('Among Us', 'Among Us*', '*\Among Us', '*\Among Us*', '*\Among_*')) {
            $hits += Get-ChildItem -Path (Join-Path $r $p) -Directory -ErrorAction SilentlyContinue
        }
    }

    $candidates = $hits | Select-Object -ExpandProperty FullName -Unique | Where-Object {
        (Test-Path -LiteralPath (Join-Path $_ 'Among Us.exe')) -and
        (Test-Path -LiteralPath (Join-Path $_ 'GameAssembly.dll'))
    }

    if (-not $candidates) { throw '未找到 Among Us（需同时有 Among Us.exe 与 GameAssembly.dll）。请用 -GamePath 指定。' }

    $chosen = @($candidates | Sort-Object { if (Test-Path -LiteralPath (Join-Path $_ 'BepInEx')) { 0 } else { 1 } })[0]
    if (@($candidates).Count -gt 1) {
        Write-Warn2 "发现 $(@($candidates).Count) 个候选，选用：$chosen"
        foreach ($c in $candidates) { if ($c -ne $chosen) { Write-Info "  其他候选：$c" } }
    }
    return $chosen
}

function Test-GameRunning([string]$Path) {
    $exe = Join-Path $Path 'Among Us.exe'
    Get-Process -ErrorAction SilentlyContinue | Where-Object {
        try { $_.Path -eq $exe } catch { $false }
    }
}

# ---------------------------------------------------------------- 备份

function New-BackupSession([string]$Root, [string]$Kind) {
    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $dir = Join-Path $Root (Join-Path $Script:BackupFolderName ("{0}_{1}" -f $Kind, $stamp))
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    return $dir
}

function Move-IntoBackup([string]$Root, [string]$BackupDir, [string[]]$Entries, $Manifest) {
    foreach ($rel in $Entries) {
        $src = Join-Path $Root $rel
        if (-not (Test-Path -LiteralPath $src)) { continue }
        $isDir = Test-Path -LiteralPath $src -PathType Container
        $dst = Join-Path $BackupDir $rel
        $parent = Split-Path -Parent $dst
        if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
        if (Test-Path -LiteralPath $dst) { Remove-Item -LiteralPath $dst -Recurse -Force }
        Write-Info "备份 $rel"
        Move-Item -LiteralPath $src -Destination $dst -Force
        $Manifest.moved += [pscustomobject]@{ path = $rel; kind = $(if ($isDir) { 'dir' } else { 'file' }) }
    }
}

function Read-Manifest([string]$BackupRoot) {
    if (-not (Test-Path -LiteralPath $BackupRoot)) { return $null }
    $dirs = @(Get-ChildItem -LiteralPath $BackupRoot -Directory -ErrorAction SilentlyContinue |
              Where-Object { $_.Name -like 'install_*' } | Sort-Object Name -Descending)
    foreach ($d in $dirs) {
        $m = Join-Path $d.FullName $Script:ManifestName
        if (Test-Path -LiteralPath $m) {
            $json = Get-Content -LiteralPath $m -Raw -Encoding UTF8 | ConvertFrom-Json
            $json | Add-Member -NotePropertyName '_BackupDir' -NotePropertyValue $d.FullName -Force
            return $json
        }
    }
    return $null
}

# ---------------------------------------------------------------- 状态

function Invoke-Status([string]$Root) {
    Write-Head "Nebula 注入状态 · $Root"

    $exe = Join-Path $Root 'Among Us.exe'
    $gameMach = Get-PEMachine $exe
    $gameBits = Format-Machine $gameMach
    Write-Info "Among Us.exe     : $gameBits"
    Write-Info "GameAssembly.dll : $(Format-Machine (Get-PEMachine (Join-Path $Root 'GameAssembly.dll')))"
    foreach ($d in Get-ChildItem -LiteralPath $Root -Directory -Filter '*_Data' -ErrorAction SilentlyContinue) {
        $meta = Join-Path $d.FullName 'il2cpp_data\Metadata\global-metadata.dat'
        $mark = if (Test-Path -LiteralPath $meta) { 'IL2CPP' } else { '非 IL2CPP' }
        Write-Info ("Data 目录        : {0} ({1})" -f $d.Name, $mark)
    }

    Write-Head '注入层'
    $doorstop = Join-Path $Root 'doorstop_config.ini'
    if (Test-Path -LiteralPath $doorstop) {
        $enabled = (Select-String -LiteralPath $doorstop -Pattern '^\s*enabled\s*=\s*(\w+)' | Select-Object -First 1).Matches.Groups[1].Value
        $target  = (Select-String -LiteralPath $doorstop -Pattern '^\s*target_assembly\s*=\s*(.+)$' | Select-Object -First 1).Matches.Groups[1].Value
        Write-Ok "doorstop_config.ini (enabled=$enabled, target=$($target.Trim()))"
    } else { Write-Warn2 'doorstop_config.ini 缺失' }

    foreach ($rel in @('winhttp.dll', 'dotnet\coreclr.dll')) {
        $full = Join-Path $Root $rel
        if (-not (Test-Path -LiteralPath $full)) { Write-Warn2 "$rel 缺失"; continue }
        $m = Get-PEMachine $full
        if ($m -eq $gameMach) { Write-Ok "$rel $(Format-Machine $m)" }
        else { Write-Err2 "$rel $(Format-Machine $m) ≠ 游戏 $gameBits（启动即崩）" }
    }

    Write-Head '插件'
    foreach ($p in @('BepInEx\nebula\Nebula.dll', 'BepInEx\plugins\NebulaLoader.dll', 'BepInEx\core\BepInEx.Unity.IL2CPP.dll')) {
        $full = Join-Path $Root $p
        if (Test-Path -LiteralPath $full) {
            $i = Get-Item -LiteralPath $full
            Write-Ok ("{0}  {1:N0} 字节{2}" -f $p, $i.Length, $(if ($i.VersionInfo.FileVersion) { "  v$($i.VersionInfo.FileVersion)" } else { '' }))
        } else { Write-Warn2 "$p 缺失" }
    }

    $log = Join-Path $Root 'BepInEx\LogOutput.log'
    if (Test-Path -LiteralPath $log) {
        Write-Head '上次运行日志（末尾）'
        Get-Content -LiteralPath $log -Tail 12 -ErrorAction SilentlyContinue | ForEach-Object { Write-Host "   $_" -ForegroundColor DarkGray }
    }

    $backupRoot = Join-Path $Root $Script:BackupFolderName
    if (Test-Path -LiteralPath $backupRoot) {
        Write-Head '备份'
        Get-ChildItem -LiteralPath $backupRoot -Directory | ForEach-Object {
            Write-Info ("{0}  ({1} 项)" -f $_.Name, @(Get-ChildItem -LiteralPath $_.FullName -Force).Count)
        }
    }

    Write-Head '位数错配扫描（注入层原生 DLL）'
    $bad = @()
    $scanRoots = @('BepInEx', 'dotnet') | ForEach-Object { Join-Path $Root $_ } |
                 Where-Object { Test-Path -LiteralPath $_ }
    foreach ($sr in $scanRoots) {
        foreach ($n in Get-ChildItem -LiteralPath $sr -Recurse -File -Filter '*.dll' -ErrorAction SilentlyContinue) {
            if (Test-ManagedAssembly $n.FullName) { continue }
            $m = Get-PEMachine $n.FullName
            if ($m -ne 0 -and $m -ne $gameMach) {
                $bad += ("{0}  ({1})" -f $n.FullName.Substring($Root.Length).TrimStart('\'), (Format-Machine $m))
            }
        }
    }
    if ($bad) {
        $bad | ForEach-Object { Write-Err2 $_ }
        Write-Warn2 "共 $($bad.Count) 个注入层原生文件与游戏位数不符"
    } else { Write-Ok '注入层内未发现位数错配的原生 DLL' }
}

# ---------------------------------------------------------------- 注入

function Copy-ChildItems([string]$Source, [string]$Destination) {
    Get-ChildItem -LiteralPath $Source -Force | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $Destination $_.Name) -Recurse -Force
    }
}

function Repair-NativeLayer([string]$Root, [string]$StageBep, [int]$GameMachine) {
    $report = @()

    $shim = Join-Path $StageBep 'winhttp.dll'
    if (Test-Path -LiteralPath $shim) {
        $m = Get-PEMachine $shim
        if ($m -eq $GameMachine) {
            Copy-Item -LiteralPath $shim -Destination (Join-Path $Root 'winhttp.dll') -Force
            Write-Ok "winhttp.dll <- 官方 $(Format-Machine $m)"
            $report += 'winhttp.dll'
        } else {
            Write-Warn2 "BepInEx 包里的 winhttp.dll 是 $(Format-Machine $m)，与游戏不同位"
        }
    }

    $srcDotnet = Join-Path $StageBep 'dotnet'
    $dstDotnet = Join-Path $Root 'dotnet'
    if (Test-Path -LiteralPath $srcDotnet) {
        if (-not (Test-Path -LiteralPath $dstDotnet)) { New-Item -ItemType Directory -Force -Path $dstDotnet | Out-Null }
        $n = 0
        foreach ($f in Get-ChildItem -LiteralPath $srcDotnet -File) {
            Copy-Item -LiteralPath $f.FullName -Destination (Join-Path $dstDotnet $f.Name) -Force
            $n++
        }
        Write-Ok "dotnet\ <- 官方 $(Format-Machine $GameMachine) 运行时（$n 个文件）"
        $report += "dotnet/* ($n)"
    }

    $dobby = Join-Path $StageBep 'BepInEx\core\dobby.dll'
    $dstDobby = Join-Path $Root 'BepInEx\core\dobby.dll'
    if ((Test-Path -LiteralPath $dobby) -and (Test-Path -LiteralPath (Split-Path -Parent $dstDobby))) {
        Copy-Item -LiteralPath $dobby -Destination $dstDobby -Force
        Write-Ok "BepInEx\core\dobby.dll <- 官方 $(Format-Machine (Get-PEMachine $dobby))"
        $report += 'BepInEx/core/dobby.dll'
    }

    foreach ($pat in $Script:WrongArchPatterns) {
        $full = Join-Path $Root $pat
        foreach ($f in @(Get-Item -Path $full -ErrorAction SilentlyContinue)) {
            Remove-Item -LiteralPath $f.FullName -Force
            Write-Info "清理 $($f.Name)"
        }
    }

    return $report
}

function Invoke-Install([string]$Root, [string]$NebulaZipPath, [string]$BepInExZipPath, [bool]$DryRun) {
    Write-Head "Nebula 注入 · $Root"

    $exe = Join-Path $Root 'Among Us.exe'
    if (-not (Test-Path -LiteralPath $exe)) { throw "不是游戏根目录：缺少 Among Us.exe（$Root）" }
    $gameMach = Get-PEMachine $exe
    if ($gameMach -eq 0) { throw '无法读取 Among Us.exe 的 PE 头' }
    $gameBits = Format-Machine $gameMach
    Write-Info "目标游戏位数：$gameBits"

    $running = Test-GameRunning $Root
    if ($running -and -not $AllowRunning -and -not $DryRun) {
        throw "游戏正在运行（PID $(@($running.Id) -join ',')），请先完全退出 Among Us。"
    }

    foreach ($z in @($NebulaZipPath, $BepInExZipPath)) {
        if (-not (Test-Path -LiteralPath $z)) { throw "缺少包：$z" }
    }
    $nebulaItem = Get-Item -LiteralPath $NebulaZipPath
    $bepItem    = Get-Item -LiteralPath $BepInExZipPath
    Write-Info ("Nebula 包  {0}  ({1:N1} MB)" -f $nebulaItem.Name, ($nebulaItem.Length / 1MB))
    Write-Info ("BepInEx 包 {0}  ({1:N1} MB)" -f $bepItem.Name, ($bepItem.Length / 1MB))

    Write-Head '计划'
    $existing = @($Script:LayerEntries + $Script:NebulaEntries) | Where-Object { Test-Path -LiteralPath (Join-Path $Root $_) }
    if ($existing) {
        Write-Info '将备份并移走：'
        $existing | ForEach-Object { Write-Host "            $_" }
    } else {
        Write-Info '当前是干净目录，无需备份旧注入层'
    }
    Write-Info '将铺设：Nebula 包全部内容（Nebula.dll、NebulaLoader.dll、BepInEx 核心、配置）'
    Write-Info "将用 BepInEx 包的 $gameBits 原生层覆盖：winhttp.dll、dotnet\*、BepInEx\core\dobby.dll"
    Write-Info '将清理：dotnet 下 amd64 专属附属文件'

    if ($DryRun) { Write-Head 'DryRun —— 未写入任何文件'; return }

    Write-Head '解包'
    $stage = Join-Path $env:TEMP ("NebulaInjector_{0}" -f (Get-Random))
    try {
        $stageNebula = Join-Path $stage 'nebula'
        $stageBep    = Join-Path $stage 'bepinex'
        New-Item -ItemType Directory -Force -Path $stageNebula, $stageBep | Out-Null
        Write-Info '展开 Nebula…'
        Expand-Archive -LiteralPath $NebulaZipPath -DestinationPath $stageNebula -Force
        Write-Info '展开 BepInEx…'
        Expand-Archive -LiteralPath $BepInExZipPath -DestinationPath $stageBep -Force

        $backupDir = New-BackupSession $Root 'install'
        $manifest = [pscustomobject]@{
            injectorVersion = $Script:InjectorVersion
            createdAt       = (Get-Date).ToString('o')
            gamePath        = $Root
            gameMachine     = ('0x{0:x}' -f $gameMach)
            gameBits        = $gameBits
            nebulaZip       = $nebulaItem.Name
            bepinexZip      = $bepItem.Name
            moved           = @()
            createdEntries  = @($Script:LayerEntries + $Script:NebulaEntries)
        }
        if ($existing) {
            Write-Head '备份旧注入层'
            Move-IntoBackup -Root $Root -BackupDir $backupDir -Entries $existing -Manifest $manifest
        }

        Write-Head '铺设 Nebula'
        Copy-ChildItems -Source $stageNebula -Destination $Root
        Write-Ok 'Nebula.dll / NebulaLoader.dll / BepInEx 核心 已就位'

        if (-not $SkipBitnessFix) {
            Write-Head "修正原生层为 $gameBits"
            $fixes = Repair-NativeLayer -Root $Root -StageBep $stageBep -GameMachine $gameMach
            $manifest | Add-Member -NotePropertyName 'nativeFixes' -NotePropertyValue $fixes -Force
        }

        $manifestPath = Join-Path $backupDir $Script:ManifestName
        $manifest | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $manifestPath -Encoding UTF8

        Write-Head '校验'
        $fail = 0
        foreach ($rel in $Script:MustMatchBitness) {
            $full = Join-Path $Root $rel
            if (-not (Test-Path -LiteralPath $full)) { Write-Warn2 "$rel 缺失"; continue }
            $m = Get-PEMachine $full
            if ($m -eq $gameMach) { Write-Ok "$rel $(Format-Machine $m)" }
            else { Write-Err2 "$rel $(Format-Machine $m) != 游戏 $gameBits"; $fail++ }
        }
        foreach ($rel in @('BepInEx\nebula\Nebula.dll', 'BepInEx\plugins\NebulaLoader.dll', 'doorstop_config.ini')) {
            if (Test-Path -LiteralPath (Join-Path $Root $rel)) { Write-Ok "$rel 就位" }
            else { Write-Err2 "$rel 缺失"; $fail++ }
        }

        if ($fail -gt 0) {
            Write-Err2 "有 $fail 项校验失败。可执行 -Action Uninstall 回滚。"
            Write-Info "备份：$backupDir"
            return
        }

        Write-Head '完成'
        Write-Ok "注入成功：$Root"
        Write-Info "备份清单：$manifestPath"
        Write-Info '首次启动会生成 IL2CPP interop，1-3 分钟无响应属正常。'
        Write-Info '日志：BepInEx\LogOutput.log'
    }
    finally {
        if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

# ---------------------------------------------------------------- 卸载

function Invoke-Uninstall([string]$Root) {
    Write-Head "Nebula 卸载 · $Root"

    $running = Test-GameRunning $Root
    if ($running) { throw "游戏正在运行（PID $(@($running.Id) -join ',')），请先完全退出。" }

    $manifest = Read-Manifest (Join-Path $Root $Script:BackupFolderName)
    if (-not $manifest) { throw "未找到注入清单（$Script:BackupFolderName\install_*\manifest.json），无法安全回滚。" }

    Write-Info "清单：$($manifest._BackupDir)\$Script:ManifestName"
    Write-Info "注入时间：$($manifest.createdAt)"

    Write-Head '移除注入层'
    foreach ($rel in $manifest.createdEntries) {
        $full = Join-Path $Root $rel
        if (Test-Path -LiteralPath $full) {
            Remove-Item -LiteralPath $full -Recurse -Force
            Write-Info "删除 $rel"
        }
    }

    Write-Head '还原备份'
    foreach ($item in $manifest.moved) {
        $src = Join-Path $manifest._BackupDir $item.path
        $dst = Join-Path $Root $item.path
        if (-not (Test-Path -LiteralPath $src)) { Write-Warn2 "备份缺失：$($item.path)"; continue }
        $parent = Split-Path -Parent $dst
        if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
        Move-Item -LiteralPath $src -Destination $dst -Force
        Write-Ok "还原 $($item.path)"
    }

    Write-Head '完成'
    Write-Ok '已回滚到注入前状态'
    Write-Info "备份目录保留：$($manifest._BackupDir)"
}

# ---------------------------------------------------------------- 主流程

try {
    $packagesDir = Join-Path $PSScriptRoot 'packages'

    if (-not $NebulaZip) {
        $cand = Join-Path $packagesDir 'Nebula.zip'
        if (-not (Test-Path -LiteralPath $cand)) { throw "未指定 -NebulaZip，且默认包不存在：$cand" }
        $NebulaZip = $cand
    }
    if (-not $BepInExZip) {
        $cand = Get-ChildItem -LiteralPath $packagesDir -Filter 'BepInEx-Unity.IL2CPP-win-*.zip' -ErrorAction SilentlyContinue |
                Sort-Object Name -Descending | Select-Object -First 1
        if (-not $cand) { throw "未指定 -BepInExZip，且 $packagesDir 下没有 BepInEx 包" }
        $BepInExZip = $cand.FullName
    }

    if (-not $GamePath) { $GamePath = Find-GamePath }
    $GamePath = (Resolve-Path -LiteralPath $GamePath).Path

    switch ($Action) {
        'Status'    { Invoke-Status    -Root $GamePath }
        'DryRun'    { Invoke-Install   -Root $GamePath -NebulaZipPath $NebulaZip -BepInExZipPath $BepInExZip -DryRun $true }
        'Install'   { Invoke-Install   -Root $GamePath -NebulaZipPath $NebulaZip -BepInExZipPath $BepInExZip -DryRun $false }
        'Uninstall' { Invoke-Uninstall -Root $GamePath }
    }
}
catch {
    Write-Host ''
    Write-Err2 $_.Exception.Message
    if ($_.ScriptStackTrace) { Write-Host "   $($_.ScriptStackTrace)" -ForegroundColor DarkGray }
    exit 1
}
