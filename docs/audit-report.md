# Windows 10 China Government Edition 镜像审计报告

## 审计范围

本文按时间顺序描述 `Windows10_v2022-L.1345_19044.1415.iso` 从启动安装介质到首次登录后的行为。报告目标是说明 CMGE 镜像在安装、升级、重置路径中如何执行神州网信/CMIT 定制，并区分应保留的本地策略与应移除或中和的闭源联网组件。

| 属性 | 值 |
|------|-----|
| 文件名 | `Windows10_v2022-L.1345_19044.1415.iso` |
| SHA256 | `df5d880efb41e80612a565555509310e1515856c5fa937813253e45692e0fdd1` |
| MD5 | `372b43e8fbb20644c0dd52eda1b0b4f0` |
| SHA1 | `4cbaa594dfc5dfbf8c8f8ee9ba04f4283328524d` |
| 文件大小 | 4,936,847,360 bytes |
| 版本标签 | CMGE V2022-L.1345.000 |
| Windows 构建 | 19044.1415 x64 zh-CN EnterpriseG |
| `install.wim` | 1 个索引 |
| `boot.wim` | 2 个索引，WinPE x64 / Setup x64 |

## 1. 开机并从安装介质启动

用户从 ISO/U 盘启动后，固件加载安装介质中的标准 Windows Boot Manager 和 WinPE。当前审计未发现 `boot.wim` 中存在 CMIT 主部署链；主要定制集中在 `install.wim` 应用到目标磁盘后的离线系统目录中。

此阶段的关键点是：CMIT 定制不是在固件或 WinPE 启动瞬间完成，而是在后续应用 `install.wim`、进入 Windows Setup 各配置 pass 后由目标系统内置文件触发。

## 2. Windows PE / Setup 阶段

Windows Setup 在 WinPE 环境中读取安装介质，展示安装界面，并准备把 `sources\install.wim` 中的 EnterpriseG 镜像应用到用户选择的目标分区。

CMGE 镜像中预置了应答文件：

```text
Windows\Panther\unattend.xml
```

该应答文件是后续定制链的总入口。它指定在不同 Windows Setup pass 中执行脚本和命令，其中最重要的是：

```text
specialize  -> C:\Windows\Temp\InsPreConfigPS.ps1
first logon -> C:\Windows\Temp\InsPostConfigPS.ps1
```

因此，Setup 阶段本身只是把定制入口部署到目标系统；真正的 CMIT/CMGE 行为发生在目标系统首次启动后的配置阶段。

## 3. `install.wim` 应用到磁盘

当用户选择磁盘并开始安装后，Setup 将 `install.wim` 应用到目标分区。此时大量文件已经落到未来的 `C:\` 中，包括：

```text
Windows\Panther\unattend.xml
Windows\Temp\InsPreConfig.exe
Windows\Temp\InsPreConfigPS.ps1
Windows\Temp\InsPostConfig.exe
Windows\Temp\InsPostConfigPS.ps1
Windows\Setup\Scripts\SetupComplete.cmd
Windows\Temp\UpgradeConfig.exe
Windows\Temp\UpgradeSchdTask.exe
Windows\Temp\Recovery\OEM\CMGE\...
Program Files\CMITActivation\...
Program Files\CMITControlCenter\...
Program Files\CMITOfflineUpdateInstaller\...
Program Files\CmitUpdateAgent\...
ProgramData\Microsoft\Windows\ClipSVC\Install\KeyHolder\...
Windows\PolicyDefinitions\CMITCustomPolicy.admx
Windows\PolicyDefinitions\zh-CN\CMITCustomPolicy.adml
```

这些文件在磁盘上存在并不等同于全部已经注册为服务、任务或活动组件。注册服务、计划任务、导入策略、安装激活链等动作由后续配置程序完成。

## 4. `specialize` 阶段

Windows 首次从目标磁盘启动后进入 `specialize` pass。`unattend.xml` 在此阶段调用：

```text
C:\Windows\Temp\InsPreConfigPS.ps1
```

该 PowerShell 包装脚本的行为很简单：启动 `InsPreConfig.exe`，等待其结束，然后删除 `InsPreConfig.exe` 和自身。也就是说，`InsPreConfigPS.ps1` 不是主要逻辑，真正的第一阶段定制集中在闭源二进制：

```text
C:\Windows\Temp\InsPreConfig.exe
```

逆向确认 `InsPreConfig.exe` 不是复杂 native 程序，而是 PS2EXE 打包的 .NET/PowerShell 程序。Ghidra 可以识别 PE/CLR 包装层，但真实逻辑来自内嵌 Base64 PowerShell；通过 ILSpy 和程序自带 `-extract` 参数已提取出完整脚本。

该脚本首先启动日志：

```text
CMGE_Registry_InsPreConfig.log
```

随后执行系统级定制：

1. 设置 Netlogon 服务禁用：

```text
HKLM:\SYSTEM\ControlSet001\Services\Netlogon
  Start = 4
```

2. 把恢复目录复制到系统盘并隐藏：

```text
robocopy.exe %windir%\Temp\Recovery %SystemDrive%\Recovery /e
attrib.exe +r +a +h +s %SystemDrive%\Recovery /d
```

这说明 `InsPreConfig.exe` 不是简单删除临时恢复目录，而是先把恢复资产迁移到 `C:\Recovery`，再在末尾删除 `Windows\Temp\Recovery`。

3. 创建 CMIT 更新客户端开始菜单入口：

```text
%ProgramData%\Microsoft\Windows\Start Menu\Programs\更新客户端\更新客户端.lnk
  -> %SystemDrive%\Program Files\CmitUpdateAgent\CMOS-UA_ConfigurationTool.exe
```

4. 安装 CMIT 更新代理服务：

```text
%SystemDrive%\Program Files\CmitUpdateAgent\CmitUpdateAgent.exe -install
```

5. 创建 CMIT 控制中心开始菜单和桌面快捷方式：

```text
%ProgramData%\Microsoft\Windows\Start Menu\Programs\CMGE控制中心\控制中心.lnk
%Public%\Desktop\控制中心.lnk
  -> %SystemDrive%\Program Files\CMITControlCenter\ControlCenter.exe
```

6. 导入 CMGE 本地组策略：

```text
%windir%\Temp\Recovery\OEM\CMGE\ResetSources\LGPO\LGPO.exe
  /g %windir%\Temp\Recovery\OEM\CMGE\ResetSources\LGPO
```

这是必须保留的关键行为。它应用 CMGE 本地策略，包括禁用微软遥测、在线体验、部分更新/商店扫描和安全策略。早期外置 unattend 方案之所以方向错误，核心原因就是绕过了这条原生策略导入链。

7. 注册国密 SMx/CSP/KSP 组件：

```text
CMITSMx\win32\WstSM2ECESConfig.exe -register
CMITSMx\win32\WstSM2ECDSAConfig.exe -register
CMITSMx\win32\WstKSPConfig.exe -register
CMITSMx\win32\WstSM3Config.exe -register
CMITSMx\win32\WstSM4Config.exe -register
CMITSMx\win32\WstRngConfig.exe -register
CMITSMx\win32\WstKSPConfig.exe -enum
```

该部分属于 Verify：如果目标是只移除联网管理链，可暂时保留；如果目标是移除所有 CMIT/CETC 闭源密码提供程序，则应禁用。

8. 导入证书，包括政府/行业 CA、DigiCert 以及 CMIT 专用证书。明确应禁用的是：

```text
CMIT Root Authority.cer -> LocalMachine\Root
CMIT SubP.cer           -> LocalMachine\CA
CMIT signature.cer      -> LocalMachine\TrustedPublisher
```

9. 清理安装临时入口：

```text
删除 %windir%\Setup\Scripts
删除 %windir%\Temp\Recovery
删除 %windir%\Temp\UpgradeConfig.exe
删除 %windir%\Temp\UpgradeSchdTask.exe
```

其中 `Windows\Temp\Recovery` 已经在前面复制为 `C:\Recovery`，因此删除临时目录并不等于移除恢复重注入能力。

因此，`InsPreConfig.exe` 中应保留 LGPO 导入和可能的本地安全策略；应移除或中和 CMIT 更新代理、控制中心快捷方式、CMIT 专用证书、恢复重注入闭源组件和相关联网管理链。

## 5. OOBE、auditSystem 与硬编码凭据

原始 `unattend.xml` 中存在 Administrator 自动登录配置和硬编码密码。审计确认的明文含义包括：

```text
P@ssw0rd!AdministratorPassword
P@ssw0rd!Password
```

这不是原版 Windows 面向普通用户的标准交互式账户创建流程，而是 CMGE 镜像为了自动完成后续定制而启用的无人值守/审计式登录机制。其作用是让系统在 OOBE 或首次登录相关阶段自动进入桌面，从而触发后续命令。

风险在于：

- 镜像内存在可还原的硬编码本地管理员凭据。
- 自动登录次数被设置得很高。
- 用户尚未真正完成自己的账户选择前，系统已经可执行供应商预置逻辑。

修改镜像时应中和硬编码凭据和自动登录风险，但不能因此丢失本地策略定制。

## 6. 首次登录与 `InsPostConfig.exe`

在首次登录相关阶段，`unattend.xml` 调用：

```text
C:\Windows\Temp\InsPostConfigPS.ps1
```

该包装脚本同样负责启动闭源二进制并在结束后删除自身和目标程序：

```text
C:\Windows\Temp\InsPostConfig.exe
```

逆向确认 `InsPostConfig.exe` 同样是 PS2EXE 打包的 .NET/PowerShell 程序，真实逻辑为内嵌 PowerShell 脚本。

该脚本启动日志：

```text
CMGE_Registry_InsPostConfig.log
```

随后执行登录后收尾配置：

1. 安装 CMIT 激活服务：

```text
%windir%\Microsoft.NET\Framework64\v4.0.30319\InstallUtil.exe
  "%SystemDrive%\Program Files\CMITActivation\CmitClientSVC.exe"
```

2. 设置激活服务延迟自动启动：

```text
HKLM:\SYSTEM\CurrentControlSet\services\CmitClientSVC
  DelayedAutostart = 1
```

这是 CMIT 激活链的服务注册行为，应禁用。

3. 创建 CMIT 更新代理计划任务：

```text
TaskPath: \CMIT\CmitUpdateAgent
TaskName: CmitUpdateAgent Daily Runner
Action: %SystemDrive%\Program Files\CmitUpdateAgent\CmitServiceMonitor.exe
RunAs: NT AUTHORITY\SYSTEM
RunLevel: Highest
```

触发时间为每天六次：

```text
03:00
07:00
11:00
15:00
19:00
23:00
```

也就是每 4 小时运行一次 CMIT 更新代理监控程序。该任务是 CMIT 更新链的主动持久化入口，应禁用。

4. 禁用 Microsoft InstallService 更新扫描任务：

```text
\Microsoft\Windows\InstallService\ScanForUpdates
\Microsoft\Windows\InstallService\ScanForUpdatesAsUser
```

这符合“不连接 Microsoft 官方服务”的目标，应保留。

5. Code Integrity 策略更新只存在于注释中，未实际执行：

```text
# Invoke-CimMethod root\Microsoft\Windows\CI PS_UpdateAndCompareCIPolicy ...
```

因此，`InsPostConfig.exe` 中应移除或中和 CMIT 激活服务安装、CMIT 更新计划任务；应保留禁用 Microsoft InstallService 更新扫描任务的行为。

## 7. 升级路径：`SetupComplete.cmd` 与 `UpgradeConfig.exe`

镜像中还存在升级完成后脚本：

```text
Windows\Setup\Scripts\SetupComplete.cmd
```

该脚本不是全新安装主路径。已确认它只在存在 `C:\Windows.old` 等升级场景特征时执行 `UpgradeConfig.exe`：

```text
Windows\Temp\UpgradeConfig.exe
```

并且会删除：

```text
Windows\SoftwareDistribution\CUACache
```

逆向确认 `UpgradeConfig.exe` 与 `UpgradeSchdTask.exe` 也都是 PS2EXE 打包的 .NET/PowerShell 程序，真实逻辑已通过 `-extract` 提取。

`UpgradeConfig.exe` 是升级后重配置主脚本，启动日志：

```text
CMGE_Registry_Upgrade.log
CMGE_Registry_Upgrade_CMD.log
```

它执行以下关键动作：

1. 清理或设置 CMIT 激活相关注册表。多数激活服务器写入语句已被注释，但仍实际设置：

```text
HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ClipSVC
  AltActivationClient = %ProgramFiles%\CMITActivation\CmitClient.exe
```

该项会把 ClipSVC 激活客户端重定向到 CMIT 激活程序，应禁用。

2. 恢复 CMGE 隐私/本地策略项，包括：

```text
AdvertisingInfo\Enabled = 0
Device Metadata\PreventDeviceMetadataFromNetwork = 1
NlaSvc\Parameters\Internet\EnableActiveProbing = 0
InstallService\Configuration\AutoUpdateTasksEnabled = 0
wlidsvc Start = 4
Netlogon Start = 4
```

这些大多符合“不连接 Microsoft”的目标，应保留或验证后保留。

3. 将 F1/帮助入口改到 CMIT 支持站：

```text
HelpAndSupport\OverrideUrl = http://support.cmgos.com/category/cmgehelp
```

这是 CMIT 外部支持入口，应禁用或置空。

4. 重写 CMGE 品牌显示：

```text
EditionSubManufacturer = 神州网信技术有限公司
EditionSubstring = 神州网信政府版
EditionSubVersion = V2022-L.1345.000
```

品牌信息本身不联网，属于 Verify。

5. 处理国密 SMx/CSP/KSP：先注销旧 `SMxCNG`，后注册 `CMITSMx`。该部分属于 Verify。

6. 重建升级后的恢复目录：

```text
C:\Recovery\OEM\CMGE
```

它会删除旧 CMGE 恢复目录，再从 `Windows\Temp\Recovery\OEM\CMGE` 复制新的恢复资产。这是升级路径下的恢复重注入重建逻辑。应保留必要 reset/LGPO 资产，但移除闭源 CMIT payload。

7. 导入 LGPO：

```text
LGPO.exe /g %windir%\Temp\Recovery\OEM\CMGE\ResetSources\LGPO
```

应保留。

8. 先删除再重新导入证书。明确应禁用的是：

```text
CMIT Root Authority.cer
CMIT SubP.cer
CMIT signature.cer
```

9. 迁移、卸载、删除并重新部署升级前后的 CMIT 组件，涉及：

```text
CMIT3.0
CMITActivation
CmitUpdateAgent
CMITOfflineUpdateInstaller
CMITControlCenter
```

其中还会调用：

```text
EPrivilege.exe -U:S CMGEInstaller.exe 00000200
```

这是升级路径的 CMGE/CMIT 安装器调用，应禁用或拆解为只保留本地策略。

10. 创建一次性登录后任务：

```text
TaskName: UpgradeSchdTask
Trigger: AtLogon
Action: %windir%\Temp\UpgradeSchdTask.exe
```

11. 安装并启动 CMIT 更新代理，然后重新创建每天六次运行的更新监控任务：

```text
CmitUpdateAgent.exe -install
sc.exe start CmitUpdateAgent
\CMIT\CmitUpdateAgent\CmitUpdateAgent Daily Runner
03:00 07:00 11:00 15:00 19:00 23:00
```

应禁用。

12. 禁用 Microsoft InstallService 更新扫描任务：

```text
\Microsoft\Windows\InstallService\ScanForUpdates
\Microsoft\Windows\InstallService\ScanForUpdatesAsUser
```

应保留。

13. 创建 CMIT 控制中心快捷方式，应禁用。

14. 停止并禁用 `wlidsvc` 与 `netlogon`，属于“不连接 Microsoft/域登录相关服务”的本地策略，属于 Preserve/Verify。

15. 清理安装临时文件，包括 `InsPreConfig.exe`、`InsPostConfig.exe` 及其包装脚本。

`UpgradeSchdTask.exe` 是 `UpgradeConfig.exe` 创建的登录后收尾任务。它启动日志：

```text
CMGE_Registry_UpgradeSchdTask.log
```

主要行为：

1. 从 `C:\Recovery\OEM\CMGE\ResetSources\CMITSMx` 复制 VC runtime 到 `System32` / `SysWOW64`，属于 Verify。
2. 再次调用：

```text
EPrivilege.exe -U:S C:\Recovery\OEM\CMGE\ResetSources\CMGEInstaller\CMGEInstaller.exe 00000400
```

这是登录后的 CMGE/CMIT 安装器调用，应禁用或拆解。

3. 用 `InstallUtil.exe` 安装 `CMITActivation\CmitClientSVC.exe`，并设置 `DelayedAutostart=1`，应禁用。
4. 删除自身计划任务 `UpgradeSchdTask`，并删除 `Windows\Temp\UpgradeSchdTask.exe`。

因此，干净安装路径的主要入口是 `InsPreConfig.exe` / `InsPostConfig.exe`；升级路径的主要入口是 `SetupComplete.cmd` -> `UpgradeConfig.exe` -> `UpgradeSchdTask.exe`。项目必须同时中和这两条链。

## 8. 重置/恢复路径

镜像中预置了恢复资产：

```text
Windows\Temp\Recovery\OEM\CMGE\
  BasicAfterImageApply.cmd
  FactoryAfterImageApply.cmd
  ResetSources\
    ResetPreConfig.exe
    ResetPreConfigPS.ps1
    ResetPostConfig.exe
    ResetPostConfigPS.ps1
    LGPO\LGPO.exe
    LGPO\{E36A9ECE-5C14-4BB4-9549-4C5784966E0D}\...
    CMITActivation\...
    CMITControlCenter\...
    CMITOfflineUpdateInstaller\...
    CmitUpdateAgent\...
```

该目录用于 Reset this PC / 恢复场景。风险是：即使首次安装时中和了 CMIT 组件，恢复脚本仍可能从 `ResetSources` 重新复制或执行闭源组件。

但该目录中也包含有益的本地策略资产，例如 LGPO 工具和 GPO backup。正确处理方式不是简单删除整个 `Recovery\OEM\CMGE`，而是拆分：

- 保留策略资产。
- 禁用重注入入口。
- 移除或中和闭源激活、更新、控制中心和相关 EXE。

## 9. 首次登录后的稳态

原始镜像完成安装和首次登录后，系统可能存在以下稳态结果。

### 活动组件

CMIT 组件可能被注册为服务、计划任务、文件关联、COM/本地管理组件。重点对象包括：

```text
CMITActivation
CMITControlCenter
CMITOfflineUpdateInstaller
CmitUpdateAgent
CmitClientSVC
```

这些组件会带来不透明的激活、更新、管理和联网行为，应作为移除或中和对象。

### 激活与 KeyHolder

镜像预置 ClipSVC KeyHolder：

```text
ProgramData\Microsoft\Windows\ClipSVC\Install\KeyHolder\...
```

它用于 CMIT 激活链。项目目标是不让系统连接 CMIT，也不让系统恢复到 Microsoft 在线激活/更新路径。因此应移除或中和 CMIT KeyHolder/激活客户端，同时保持系统离线可控状态。

### 网络端点

已发现的 CMIT/CMGE 相关端点包括：

```text
oag.cmgos.com:7892
download.cmgos.com
support.cmgos.com
uc.cmgos.com:80
wu.cmgos.com:80
vdi.cmge.local
```

正确目标不是把这些域名写入 hosts 黑名单，而是移除产生这些请求的客户端、服务、任务、激活链和更新链。

### Windows Update

CMGE 镜像中存在将 Windows Update 从 Microsoft 官方更新路径上移开的配置。用户目标是不连接 CMIT，也不连接 Microsoft，因此修改时不得“修复”为 Microsoft 官方 Windows Update。可控更新方式应是手动安装离线更新包。

### 本地策略

应保留禁用微软遥测和在线体验的本地策略。相关资产包括：

```text
Windows\PolicyDefinitions\CMITCustomPolicy.admx
Windows\PolicyDefinitions\zh-CN\CMITCustomPolicy.adml
Windows\Temp\Recovery\OEM\CMGE\ResetSources\LGPO\...
```

这些策略资产本身不是联网客户端。删除它们会降低系统的隐私/可控性。

## 10. 结论

CMGE 镜像的关键不是“文件是否存在”，而是安装阶段哪些入口会执行、哪些服务/任务/注册表/激活链会被注册。

正确的 `uncmit-cmge` 方向是：

1. 修改原镜像内置部署链，而不是依赖外置应答文件。
2. 保留有益的 CMGE 本地策略和遥测禁用状态。
3. 从 `InsPreConfig.exe` 行为中保留 LGPO 导入，去掉 CMIT 更新代理、控制中心、CMIT 专用证书和恢复重注入闭源组件。
4. 从 `InsPostConfig.exe` 行为中保留禁用 Microsoft InstallService 更新扫描任务，去掉 CMIT 激活服务和 CMIT 更新计划任务。
5. 禁用升级和恢复路径中的 CMIT 重注入入口。
6. 移除 CMIT 激活、更新、控制中心、服务、计划任务和 KeyHolder。
7. 不恢复 Windows Update 到 Microsoft 官方端点。
8. 不依赖 hosts 黑名单。

由于两个 EXE 本质是 PS2EXE 打包的 PowerShell，最可靠的实现不是 native 指令级 patch，而是替换镜像内原有执行入口或 EXE 内容，使其只执行 Preserve 项，跳过 Disable 项。