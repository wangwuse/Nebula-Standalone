Nebula on the Ship - Among Us MOD
====================================

Mod version : Nebula Snapshot 26.10.17a (Nebula.dll v110.1653)
Game        : Among Us (32-bit IL2CPP, Unity 2022.3.44f1)

How to inject on the target PC (same network / same PC):

1. Share folder : C:\NebulaShare\Nebula   (contains Nebula_Snapshot_26.10.17a.zip + NebulaInject.bat + NebulaDist.bat)
2. Copy NebulaInject.bat to the target machine, or just run the inject command manually:

   powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\NebulaInjector\NebulaInjector.ps1 -Action Install -GamePath C:\Among_92595

3. First launch: 1-3 min for IL2CPP interop generation (no response is normal).

Uninstall (to remove mod):
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\NebulaInjector\NebulaInjector.ps1 -Action Uninstall -GamePath C:\Among_92595

Check status:
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\NebulaInjector\NebulaInjector.ps1 -Action Status -GamePath C:\Among_92595
