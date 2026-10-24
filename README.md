# AU NOS — 星云舰整合包

**Nebula on the Ship**（星云舰）Among Us 模组的解压即玩整合包，专治 32 位游戏装模组没反应的问题。

> 🙈 随缘维护：能启动就不动，有问题提 Issue 但我不一定修。

## ❓ 为什么需要这个

Nebula 官方发布包的原生层是 **x64**（winhttp.dll、CoreCLR、dobby.dll），而 Among Us 是 **32 位 IL2CPP** 游戏 —— 直接解压进去，游戏静默闪退/无响应。

本整合包已完成全部修正：

- ✅ Nebula 模组本体（Nebula.dll v110.1653 / Snapshot 26.10.17a）
- ✅ 官方 x86 BepInEx 6.0.0-be.783 原生层（winhttp.dll / dotnet\ / dobby.dll）
- ✅ 已清理 x64 残留文件
- ✅ 已修复启动时 SSL 联网检查报错

## 🚀 使用方法

1. 从 [Releases](https://github.com/wangwuse/Nebula-Standalone/releases) 下载 `AU_NOS_AllInOne.zip`（1.33 GB）
2. 解压到任意文件夹
3. 双击 `Among_Us_Nebula\Among Us.exe` 直接玩

> 首次启动会等 1-3 分钟（生成 IL2CPP interop），无响应属正常，耐心等待即可。

## 📋 版本信息

| 组件 | 版本 |
|------|------|
| Nebula | Snapshot 26.10.17a (v110.1653) |
| BepInEx | 6.0.0-be.783 (x86 IL2CPP) |
| Among Us | 2026/8/19 build (Unity 2022.3.44f1) |
| .NET Runtime | 6.0.7 x86（已内置，无需另装） |

## 🔧 技术原理

| 层 | 来源 | 位数 |
|----|------|------|
| 托管插件（Nebula.dll、NebulaLoader.dll、BepInEx.Core.dll、0Harmony.dll） | Nebula 官方包 | AnyCPU / x86 |
| winhttp.dll（Doorstop 垫片） | **BepInEx x86 包** | **x86** |
| dotnet\（CoreCLR、clrjit、hostpolicy 等） | **BepInEx x86 包** | **x86** |
| BepInEx\core\dobby.dll | **BepInEx x86 包** | **x86** |
| x64 残留（DiaSymReader.amd64、mscordaccore_amd64） | — | **已删除** |

游戏主程序（Among Us.exe）与 GameAssembly.dll **从不被修改**。

## ⚙️ 修改过的配置

`BepInEx\config\jp.dreamingpig.amongus.nebula.loader.cfg`：

```ini
SkipCheckingConsistency = true
AutoUpdate = false
AutoUpdateIfVersionMismatching = false
AllowHttpCommunication = false
```

关闭了联网更新检查（受限网络下 SSL 握手会失败导致启动报错）。想恢复自动更新改成 `true` 即可。

## ⚠️ 免责声明

- 模组会修改游戏目录文件，卸载游戏前请先备份存档
- Nebula 模组版权归 [Dolly1016](https://github.com/Dolly1016/Nebula) 所有，本仓库只做位数修正整合
- 与 Innersloth / BepInEx / Nebula 作者无关联
- 模组联机可能违反游戏服务条款，风险自担

## 📄 License

MIT License — see [LICENSE](LICENSE).

## 🙏 Credits

- **Nebula mod**: [Dolly1016](https://github.com/Dolly1016/Nebula) / Nebula team
- **BepInEx**: BepInEx contributors (x86 IL2CPP build 6.0.0-be.783)
- **Doorstop**: NeighTools / Doorstop team
