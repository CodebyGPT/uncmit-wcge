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

#### 4.1 禁用 Netlogon 域认证服务

```text
HKLM:\SYSTEM\ControlSet001\Services\Netlogon
  Start = 4  (禁用)
```

CMGE 政府版通常不加入 Active Directory 域，使用本地账户管理。安装阶段禁用 Netlogon 可避免域认证干扰部署流程。该操作在 `UpgradeConfig` 中也会重复执行以确保升级后状态一致。

#### 4.2 部署恢复分区

```text
robocopy.exe %windir%\Temp\Recovery %SystemDrive%\Recovery /e
attrib.exe +r +a +h +s %SystemDrive%\Recovery /d
```

从临时目录复制 Recovery 文件夹到系统盘根目录，添加只读(`+r`)、存档(`+a`)、隐藏(`+h`)、系统文件(`+s`)属性，使用户在文件资源管理器中不可见。这是 OEM 恢复分区的标准做法，用于系统重置/恢复功能。

`InsPreConfig.exe` 不是简单删除临时恢复目录，而是先把恢复资产迁移到 `C:\Recovery`，再在末尾删除 `Windows\Temp\Recovery`。

#### 4.3 安装 CMIT 更新代理

创建开始菜单入口：

```text
%ProgramData%\Microsoft\Windows\Start Menu\Programs\更新客户端\更新客户端.lnk
  -> %SystemDrive%\Program Files\CmitUpdateAgent\CMOS-UA_ConfigurationTool.exe
```

安装 Windows 服务：

```text
%SystemDrive%\Program Files\CmitUpdateAgent\CmitUpdateAgent.exe -install
```

注释掉的代码曾试图创建"系统激活"桌面快捷方式，但在本版本中未执行。

#### 4.4 创建 CMIT 控制中心入口

```text
%ProgramData%\Microsoft\Windows\Start Menu\Programs\CMGE控制中心\控制中心.lnk
%Public%\Desktop\控制中心.lnk
  -> %SystemDrive%\Program Files\CMITControlCenter\ControlCenter.exe
```

创建两个快捷方式指向同一个控制中心可执行文件，分别放在开始菜单和桌面。

#### 4.5 导入 CMGE 本地组策略

```text
%windir%\Temp\Recovery\OEM\CMGE\ResetSources\LGPO\LGPO.exe
  /g %windir%\Temp\Recovery\OEM\CMGE\ResetSources\LGPO
```

这是**必须保留的关键行为**。它应用 CMGE 本地策略，包括禁用微软遥测、在线体验、部分更新/商店扫描和安全策略。早期外置 unattend 方案之所以方向错误，核心原因就是绕过了这条原生策略导入链。

> 技术细节：`LGPO.exe` 是 Microsoft 官方本地组策略对象工具，`/g` 参数表示从目录导入完整 GPO 备份。CMGE 的安全策略、更新策略、用户权限等通过组策略统一强制固化。

#### 4.6 注册国密算法模块（SM2/SM3/SM4/RNG）

注册 6 个国密相关的 CSP/KSP 模块：

| 模块 | 注册命令 | 功能 |
|------|---------|------|
| SM2 ECES | `WstSM2ECESConfig.exe -register` | 椭圆曲线公钥加密（SM2 加密） |
| SM2 ECDSA | `WstSM2ECDSAConfig.exe -register` | 椭圆曲线数字签名（SM2 签名） |
| KSP | `WstKSPConfig.exe -register` | 密钥存储提供程序（对接 Windows CNG） |
| SM3 | `WstSM3Config.exe -register` | 国密哈希算法（类似 SHA-256） |
| SM4 | `WstSM4Config.exe -register` | 国密分组加密（类似 AES） |
| RNG | `WstRngConfig.exe -register` | 国密随机数生成器 |
| KSP 验证 | `WstKSPConfig.exe -enum` | 枚举已注册 KSP 提供程序，验证注册成功 |

这是 CMGE 区别于标准 Windows 的关键特征——使系统原生支持国密算法，任何调用 Windows CryptoAPI / CNG 的应用均可无感使用 SM2/SM3/SM4。

该部分属于 **Verify**：如果目标是只移除联网管理链，可暂时保留；如果目标是移除所有 CMIT/CETC 闭源密码提供程序，则应禁用。

#### 4.7 植入证书体系

脚本批量安装 **19 个证书**，分为四类：

| 类别 | 证书 | 存储位置 | 数量 |
|------|------|---------|------|
| **CMIT 自有** | `CMIT Root Authority`、`CMIT SubP`、`CMIT signature` | 受信任根 / 中级 CA / 受信任发布者 | 3 |
| **北京 CA 体系** | `Beijing ROOT CA`、`Beijing GCA`、`BJCA` 及 `New` 版本 | 受信任根 / 中级 CA | 6 |
| **其他中国 CA** | `GDCA_ROOT_CA`(广东 CA)、`UCA Root`(CFCA)、`CEGN_RCA/OCA`(中金国盛)、`ROOTCA` | 受信任根 / 中级 CA | 5 |
| **DigiCert** | `Assured ID Root CA`、`Global Root CA`、`High Assurance EV Root CA` | 受信任根 | 3 |
| **注释跳过** | `PK.cer` | — | (0) |

**战略意义：** 
- 将中国 CA 体系（北京 CA、广东 CA、CFCA 等）预置为系统级受信任根，确保基于国产证书的 HTTPS、代码签名、文档签名可在系统上无感运行
- 保留 DigiCert 全球根保证国际 HTTPS 兼容性
- `CMIT signature.cer` 装入 `TrustedPublisher`——使 CMIT 签名的软件可不受限制安装

明确应禁用的是：

```text
CMIT Root Authority.cer -> LocalMachine\Root
CMIT SubP.cer           -> LocalMachine\CA
CMIT signature.cer      -> LocalMachine\TrustedPublisher
```

#### 4.8 清理安装临时入口

```text
删除 %windir%\Setup\Scripts
删除 %windir%\Temp\Recovery
删除 %windir%\Temp\UpgradeConfig.exe
删除 %windir%\Temp\UpgradeSchdTask.exe
```

其中 `Windows\Temp\Recovery` 已经在前面复制为 `C:\Recovery`，因此删除临时目录并不等于移除恢复重注入能力。注释掉了证书目录和自删除逻辑，使部署痕迹在硬盘上部分残留。

#### 4.9 InsPreConfig 决策汇总

`InsPreConfig.exe` 中应保留 LGPO 导入和可能的本地安全策略；应移除或中和 CMIT 更新代理、控制中心快捷方式、CMIT 专用证书、恢复重注入闭源组件和相关联网管理链。

## 5. OOBE、auditSystem 与硬编码凭据

原始 `unattend.xml` 中存在 Administrator 自动登录配置和硬编码密码。审计确认的明文含义包括（UTF-16LE → Base64 解码结果）：

| 字段 | Base64 编码值 | 解码明文 |
|------|---------------|---------|
| `oobeSystem\AdministratorPassword` | `UABAAHMAcwB3ADAAcgBkACEAQQBkAG0AaQBuAGkAcwB0AHIAYQB0AG8AcgBQAGEAcwBzAHcAbwByAGQA` | **`P@ssw0rd!AdministratorPassword`** |
| `auditSystem\AutoLogon\Password` | `UABAAHMAcwB3ADAAcgBkACEAUABhAHMAcwB3AG8AcgBkAA==` | **`P@ssw0rd!Password`** |

两个密码不同：
- **AdministratorPassword** = `P@ssw0rd!AdministratorPassword`
- **AutoLogon 密码** = `P@ssw0rd!Password`

原始 `unattend.xml` 的 OOBE 配置还包含以下行为控制：

| 设置项 | 值 | 含义 |
|--------|------|------|
| `HideEULAPage` | `true` | 跳过 EULA 许可协议页面 |
| `HideOnlineAccountScreens` | `true` | 跳过微软账户登录，使用本地账户 |
| `HideWirelessSetupInOOBE` | `true` | 跳过无线网络设置向导 |
| `NetworkLocation` | `Work` | 网络位置设为"工作网络" |
| `ProtectYourPC` | `3` | 安全中心推荐级别 |

这不是原版 Windows 面向普通用户的标准交互式账户创建流程，而是 CMGE 镜像为了自动完成后续定制而启用的无人值守/审计式登录机制。其作用是让系统在 OOBE 或首次登录相关阶段自动进入桌面，从而触发后续命令。

风险在于：

- 镜像内存在可还原的硬编码本地管理员凭据。
- `PlainText=false` 仅使用了 Base64 可逆编码，并非加密，任何获取到此文件的人均可轻松解码。
- 自动登录次数被设置为 100 次。
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

#### 6.1 安装 CMIT 激活服务

```text
%windir%\Microsoft.NET\Framework64\v4.0.30319\InstallUtil.exe
  "%SystemDrive%\Program Files\CMITActivation\CmitClientSVC.exe"
```

使用 .NET Framework `InstallUtil.exe` 工具注册 `CmitClientSVC.exe` 为 Windows 服务。执行方式：隐藏窗口、管理员提权（`-Verb runas`）、同步等待（`-Wait`）。

安装完成后设置：

```text
HKLM:\SYSTEM\CurrentControlSet\services\CmitClientSVC
  DelayedAutostart = 1
```

设为延迟自动启动——系统启动后延后启动此服务，确保在用户登录后而非登录前运行。这是 CMIT 激活链的服务注册行为，**应禁用**。

#### 6.2 创建 CMIT 更新代理计划任务

```text
TaskPath: \CMIT\CmitUpdateAgent
TaskName: CmitUpdateAgent Daily Runner
Action: %SystemDrive%\Program Files\CmitUpdateAgent\CmitServiceMonitor.exe
Action Id: 10086
RunAs: NT AUTHORITY\SYSTEM
RunLevel: Highest
ExecutionTimeLimit: 120 秒
```

触发时间为每天六次：

```text
03:00  07:00  11:00  15:00  19:00  23:00
```

每 4 小时运行一次 CMIT 更新代理监控程序。该任务以 SYSTEM 最高权限运行，允许使用电池电源。Action ID `10086`（中国移动客服热线）可能是开发者标识或内部代号。

该任务是 **CMIT 更新链的主动持久化入口**，**应禁用**。

#### 6.3 禁用 Windows 更新扫描任务

```text
\Microsoft\Windows\InstallService\ScanForUpdates
\Microsoft\Windows\InstallService\ScanForUpdatesAsUser
```

将 Windows 原生的更新扫描任务禁用，更新流程完全由 CMIT 更新代理接管。这符合"不连接 Microsoft 官方服务"的目标，**应保留**。

#### 6.4 Code Integrity 策略未执行

```text
# Invoke-CimMethod root\Microsoft\Windows\CI PS_UpdateAndCompareCIPolicy ...
```

仅存在于注释中，未实际执行。WDAC 策略部署被跳过。

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

它执行以下关键动作。为便于分析，划分为子模块：

#### 7.1 注册表隐私策略加固

`UpgradeConfig.exe` 是四个脚本中注册表修改最密集的。它使用 `Set-RegistryValue` 和受限键专用函数 `Set-RestrictedRegKeyValue`（内含 `SeTakeOwnershipPrivilege` ACL 夺取）完成以下配置：

```text
# 禁用广告 ID
HKLM:\...\AdvertisingInfo\Enabled = 0

# 阻止从网络获取设备元数据
HKLM:\...\Device Metadata\PreventDeviceMetadataFromNetwork = 1

# 禁用 NCSI 网络连接状态探测（阻止向 dns.msftncsi.com 发请求）
HKLM:\...\NlaSvc\Parameters\Internet\EnableActiveProbing = 0

# 禁用自动更新任务（阻止向 displaycatalog.mp.microsoft.com 发送数据）
HKLM:\...\InstallService\Configuration\AutoUpdateTasksEnabled = 0

# 允许系统重置
HKLM:\...\PolicyManager\current\device\System\AllowUserToResetPhone = 1
HKLM:\...\PolicyManager\default\System\AllowUserToResetPhone\value = 1

# 删除 Windows Defender 安全中心开机启动
删除 HKLM:\...\Run\SecurityHealth
```

这些大多符合"不连接 Microsoft"的目标，**应保留或验证后保留**。

#### 7.2 隐藏 30+ 个系统设置页面

```text
HKLM:\...\Policies\Explorer\SettingsPageVisibility = "hide:project;clipboard;remotedesktop;
autoplay;mobile-devices;network-mobilehotspot;network-cellular;network-directaccess;
nfctransactions;fonts;emailandaccounts;workplace;gaming-gamebar;gaming-gamedvr;
gaming-gamemode;gaming-xboxnetworking;gaming-broadcasting;easeofaccess-speechrecognition;
cortana-language;cortana-permissions;cortana-notifications;cortana-moredetails;
privacy-phonecalls;privacy-speech;privacy-speechtyping;privacy-feedback;
privacy-activityhistory;privacy-location;privacy-automaticfiledownloads;
delivery-optimization;troubleshoot;findmydevice;windowsinsider;windowsanywhere;"
```

一次性隐藏 30+ 个设置页面，包括隐私子页（电话、语音、反馈、活动历史、位置）、游戏相关全部 5 项、Cortana 相关 3 项、远程桌面等。用户无法通过图形界面修改这些配置。这是政府版设备管理做法，**应保留或按需调整**。

#### 7.3 系统品牌信息改写

```text
HKLM:\...\Windows NT\CurrentVersion\EditionSubManufacturer = 神州网信技术有限公司
HKLM:\...\Windows NT\CurrentVersion\EditionSubstring       = 神州网信政府版
HKLM:\...\Windows NT\CurrentVersion\EditionSubVersion      = V2022-L.1345.000
```

同时写入 HKLM 和 WOW6432Node 两处。品牌信息本身不联网，属于 Verify。

#### 7.4 F1 帮助重定向

```text
HKLM:\...\HelpAndSupport\OverrideUrl = http://support.cmgos.com/category/cmgehelp
```

按下 F1 不再显示微软帮助，而是跳转到神州网信技术支持网站。这是 CMIT 外部支持入口，**应禁用或置空**。

#### 7.5 激活系统重定向

```text
HKLM:\...\ClipSVC\AltActivationClient = %ProgramFiles%\CMITActivation\CmitClient.exe
```

Windows 许可证激活（ClipSVC）被重定向到 CMIT 激活客户端，替代标准微软激活流程。该项**应禁用**。

#### 7.6 国密算法模块升级

先卸载旧版 `SMxCNG`，再注册新版 `CMITSMx`：

```text
# 卸载旧版（路径从 Recovery\OEM\CMGE\ResetSources\SMxCNG）
WstSM2ECESConfig.exe -unregister
WstSM2ECDSAConfig.exe -unregister
WstKSPConfig.exe -unregister
WstSM3Config.exe -unregister
WstSM4Config.exe -unregister
WstRngConfig.exe -unregister

# 注册新版（路径从 %windir%\Temp\Recovery\...\CMITSMx）
WstSM2ECESConfig.exe -register
WstSM2ECDSAConfig.exe -register
WstKSPConfig.exe -register
WstSM3Config.exe -register
WstSM4Config.exe -register
WstRngConfig.exe -register
```

路径从 `SMxCNG` → `CMITSMx`，表明国密模块的产品名和版本都有更新。该部分属于 **Verify**。

#### 7.7 证书轮换（Remove → Re-import）

脚本执行了先全部删除、再重新导入的证书轮换操作：

**第一阶段 — 删除旧证书（16 个，纠正位置错误）：**

旧版本错误地将中级 CA 证书装在 `Root`（受信任根）存储区，违反了 PKI 层级规范。升级脚本修正此问题：

```text
# 从 Root 存储删除->将在 CA 存储重新安装
Beijing GCA.cer          从 Root 删除
BJCA.cer                 从 Root 删除
CEGN_OCA.cer             从 Root 删除
CMIT SubP.cer            从 Root 删除
GDCA_Guangdong_CA.cer    从 Root 删除

# 新增删除的证书
SHECA.cer                从 Root 删除
```

**第二阶段 — 导入新证书（18 个，含 3 个新增）：**

```text
# 受信任根（Root）
Beijing ROOT CA.cer
CEGN_RCA.cer
CMIT Root Authority.cer
DigiCert Assured ID Root CA.cer
DigiCert Global Root CA.cer
DigiCert High Assurance EV Root CA.cer
GDCA_ROOT_CA.cer
ROOTCA.cer
UCA Root.cer
BeiJing ROOT CA New.cer         ← 新增

# 中级 CA（CA）
Beijing GCA.cer                 ← 修复位置 ✓
BJCA.cer                        ← 修复位置 ✓
CEGN_OCA.cer                    ← 修复位置 ✓
CMIT SubP.cer                   ← 修复位置 ✓
GDCA_Guangdong_CA.cer           ← 修复位置 ✓
Beijing GCA New.cer             ← 新增
BJCA New.cer                    ← 新增

# 受信任发布者
CMIT signature.cer
```

明确应禁用的是：

```text
CMIT Root Authority.cer
CMIT SubP.cer
CMIT signature.cer
```

#### 7.8 组件升级与迁移

`UpgradeConfig.exe` 管理多个 CMIT 组件的完整升级生命周期：

**① 激活工具升级** — 遍历检查 4 个旧版 GUID（`{61F90E65...}`、`{7D68C596...}`、`{17A2CCB1...}`、`{6E2FB2CF...}`）并静默卸载 MSI 包，停止并删除旧版 `CmitClientSVC` 服务，删除残留文件。

**② 更新代理升级** — 查找注册表卸载信息中 `DisplayName = "神州网信在线系统-更新客户端"`，静默卸载旧 MSI 包，停止并删除旧版 `CmitUpdateAgent` 服务，重新安装新版本服务并启动，重新创建 `CmitUpdateAgent Daily Runner` 计划任务。

**③ 离线更新安装工具升级** — 查找 `DisplayName = "CMGE 离线更新安装工具"` 并卸载，删除 `Program Files\CMITOfflineUpdateInstaller`。

**④ CMGEInstaller 第一阶段调用：**

```text
EPrivilege.exe -U:S CMGEInstaller.exe 00000200
```

`EPrivilege.exe` 是外部提权工具，参数 `00000200` 为第一阶段标识。这是升级路径的 CMGE/CMIT 安装器调用，**应禁用或拆解为只保留本地策略**。

#### 7.9 创建 UpgradeSchdTask（一次性登录后任务）

```text
TaskName: UpgradeSchdTask
Trigger: AtLogon
Action: %windir%\Temp\UpgradeSchdTask.exe
RunAs: Builtin\Users
RunLevel: Highest
ExecutionTimeLimit: 60 秒
Compatibility: Win8
```

此任务触发 `UpgradeSchdTask.exe`——升级链条的最后一个环节。

#### 7.10 恢复分区 OEM 文件更新

复杂的分区管理逻辑：

1. 检查 `Recovery\OEM\unattend.xml` 头部是否包含 `CMGE` 标记——没有则覆盖
2. 同样检查 `ResetConfig.xml` 头部；确保 `BasicPost.cmd` 等恢复脚本存在
3. 删除旧版 `ResetSources` 文件夹，复制新版
4. 复制 `unattend.xml` 到 `%windir%\Panther` 记录本次安装

这是**升级路径下的恢复重注入重建逻辑**。应保留必要 reset/LGPO 资产，但移除闭源 CMIT payload。

#### 7.11 服务禁用

```text
# 禁用 wlidsvc（微软账户登录）
sc.exe stop wlidsvc
sc.exe config wlidsvc start= disabled

# 禁用 Netlogon（域认证）
sc.exe stop netlogon
sc.exe config netlogon start= disabled
```

属于"不连接 Microsoft/域登录相关服务"的本地策略，**应保留**。

#### 7.12 禁用 Windows 更新扫描任务

```text
\Microsoft\Windows\InstallService\ScanForUpdates
\Microsoft\Windows\InstallService\ScanForUpdatesAsUser
```

**应保留**。

#### 7.13 部署清理

```text
del %windir%\Temp\Recovery -recurse -Force
del %windir%\Temp\InsPreConfig.exe
del %windir%\Temp\InsPreConfigPS.ps1
del %windir%\Temp\InsPostConfig.exe
del %windir%\Temp\InsPostConfigPS.ps1
del "Windows Defender Firewall with Advanced Security.lnk"
```

### 7.14 `UpgradeSchdTask.exe` — 升级收尾脚本

`UpgradeSchdTask.exe` 是 `UpgradeConfig.exe` 创建的一次性登录后收尾任务，日志：

```text
CMGE_Registry_UpgradeSchdTask.log
```

主要行为分为三步：

**① 复制国密 VC 运行时库**

```text
Recovery\OEM\CMGE\ResetSources\CMITSMx\win64\msvcr110.dll  → %windir%\System32\
Recovery\OEM\CMGE\ResetSources\CMITSMx\win64\msvcr110d.dll → %windir%\System32\
Recovery\OEM\CMGE\ResetSources\CMITSMx\win32\msvcr110.dll   → %windir%\SysWOW64\
Recovery\OEM\CMGE\ResetSources\CMITSMx\win32\msvcr110d.dll  → %windir%\SysWOW64\
```

复制 Visual C++ 2012 运行时库到系统目录。在 `UpgradeConfig` 中这部分代码被注释掉，因为国密 DLL 在升级阶段可能被进程占用无法覆盖，推迟到登录后完成。

**② CMGEInstaller 第二阶段调用**

```text
EPrivilege.exe -U:S CMGEInstaller.exe 00000400
```

与 `UpgradeConfig` 中的 `00000200` 不同，这里是 `00000400`，表明 CMGEInstaller 分两阶段执行（安装阶段 + 登录后阶段）。**应禁用或拆解**。

**③ 安装激活服务 + 自删除**

```text
InstallUtil.exe CmitClientSVC.exe  → 注册服务
Set DelayedAutostart = 1           → 延迟自动启动
```

与 `InsPostConfig` 相同的激活服务注册操作，升级场景中需要在此重新注册。

最后：

```text
Unregister-ScheduledTask -TaskName "UpgradeSchdTask"
Start-Process powershell.exe "-Command del UpgradeSchdTask.exe"
```

取消注册自身计划任务，再启动 PowerShell 子进程删除自己的 exe 文件（父进程无法自删），确保只运行一次。

#### 7.15 升级路径决策汇总

干净安装路径的主要入口是 `InsPreConfig.exe` / `InsPostConfig.exe`；升级路径的主要入口是 `SetupComplete.cmd` → `UpgradeConfig.exe` → `UpgradeSchdTask.exe`。项目必须同时中和这两条链。

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

CMGE 镜像的关键不是"文件是否存在"，而是安装阶段哪些入口会执行、哪些服务/任务/注册表/激活链会被注册。

### 完整四脚本执行链条

分析确认了 CMGE V2022-L 部署的 **四条执行链**：

```
Phase 1: 全新安装 — 安装阶段 (SYSTEM 权限)
┌─────────────────────────────────────────────────────────────┐
│ unattend.xml → specialize → RunSynchronousCommand            │
│   → InsPreConfig.exe (PS2EXE 打包)                           │
│     ├─ 禁用 Netlogon                                          │
│     ├─ 复制 Recovery 分区 + 隐藏                              │
│     ├─ 安装 CMIT 更新代理 + 控制中心                          │
│     ├─ 植入组策略 (LGPO) [保留]                               │
│     ├─ 注册国密算法 (SM2/SM3/SM4/RNG) ×6                     │
│     ├─ 安装 19 个证书 (含 CMIT 自有)                          │
│     └─ 清理部署临时文件                                       │
└─────────────────────────────────────────────────────────────┘

Phase 2: 全新安装 — 首次登录 (Administrator)
┌─────────────────────────────────────────────────────────────┐
│ unattend.xml → oobeSystem → FirstLogonCommands               │
│   → InsPostConfig.exe (PS2EXE 打包)                          │
│     ├─ 注册激活服务 CmitClientSVC + 延迟自动启动              │
│     ├─ 创建 CmitUpdateAgent Daily Runner 计划任务 ×6/天      │
│     └─ 禁用 Windows Update 扫描任务 [保留]                   │
└─────────────────────────────────────────────────────────────┘

Phase 3: 升级安装 — 升级主流程 (SYSTEM)
┌─────────────────────────────────────────────────────────────┐
│ SetupComplete.cmd → UpgradeConfig.exe (PS2EXE, ~53KB)        │
│   ├─ 注册表 ACL 夺取 (SeTakeOwnershipPrivilege P/Invoke)     │
│   ├─ 隐私加固 + 隐藏 30+ 设置页                             │
│   ├─ 改写系统品牌→"神州网信政府版 V2022-L"                   │
│   ├─ 证书轮换 (删16旧 + 装18新, 修正中级CA位置)              │
│   ├─ 国密升级 (卸载旧SMxCNG + 注册新CMITSMx)                 │
│   ├─ 卸载旧版激活工具/更新代理/离线安装工具                   │
│   ├─ 重新安装新版服务 + 计划任务                              │
│   ├─ 禁用 wlidsvc + Netlogon [保留]                          │
│   ├─ 复制 Recovery\OEM 文件                                  │
│   ├─ 组策略重植入 [保留]                                     │
│   ├─ 运行 CMGEInstaller 第一阶段 (00000200)                  │
│   └─ 注册 UpgradeSchdTask (登录触发)                         │
└─────────────────────────────────────────────────────────────┘

Phase 4: 升级安装 — 登录收尾 (Builtin\Users)
┌─────────────────────────────────────────────────────────────┐
│ UpgradeSchdTask.exe (PS2EXE) — 登录触发, 仅运行一次          │
│   ├─ 复制国密 VC 运行时库到 System32/SysWOW64                │
│   ├─ 运行 CMGEInstaller 第二阶段 (00000400)                  │
│   ├─ 安装激活服务 + 设延迟自动启动                            │
│   └─ 自删除 (取消计划任务 + 删除自身 exe)                    │
└─────────────────────────────────────────────────────────────┘
```

### 关键发现汇总

| 维度 | 发现 |
|------|------|
| **国密算法** | 注册 SM2/SM3/SM4/RNG 到 Windows CNG，任何应用可无感调用 |
| **证书体系** | 预装中国 CA（北京CA、广东CA、CFCA等）18 个证书到系统信任存储 |
| **隐私策略** | 禁用广告ID、设备元数据、NCSI 探测、隐藏 30+ 设置页 |
| **激活控制** | ClipSVC 重定向到 CMIT 激活客户端，替代微软激活 |
| **更新控制** | 禁用 Windows Update，由 CmitUpdateAgent 每 4h 运行接管 |
| **微软账户** | 禁用 wlidsvc，阻止微软账户登录 |
| **凭据泄露** | Base64 编码的管理员密码 `P@ssw0rd!...` 可轻易解码 |
| **PS2EXE** | 所有定制二进制均为 PS2EXE 打包的 PowerShell，可通过 `-extract` 还原 |

### 正确的 `uncmit-cmge` 方向

1. 修改原镜像内置部署链，而不是依赖外置应答文件。
2. 保留有益的 CMGE 本地策略和遥测禁用状态。
3. 从 `InsPreConfig.exe` 行为中保留 LGPO 导入，去掉 CMIT 更新代理、控制中心、CMIT 专用证书和恢复重注入闭源组件。
4. 从 `InsPostConfig.exe` 行为中保留禁用 Microsoft InstallService 更新扫描任务，去掉 CMIT 激活服务和 CMIT 更新计划任务。
5. 禁用升级和恢复路径中的 CMIT 重注入入口。
6. 移除 CMIT 激活、更新、控制中心、服务、计划任务和 KeyHolder。
7. 不恢复 Windows Update 到 Microsoft 官方端点。
8. 不依赖 hosts 黑名单。

### 实现建议

由于四个 EXE 本质都是 PS2EXE 打包的 PowerShell，最可靠的实现不是 native 指令级 patch，而是替换镜像内原有执行入口或 EXE 内容，使其只执行 Preserve 项，跳过 Disable 项。具体来说：

- **对于全新安装**：修改 `install.wim` 中的 `InsPreConfig.exe` 和 `InsPostConfig.exe`，提取内嵌脚本 → 移除 Disable 项 → 重新打包或替换为纯 PowerShell 脚本
- **对于升级路径**：删除或替换 `SetupComplete.cmd` 指向的 `UpgradeConfig.exe`，阻断 `UpgradeSchdTask.exe` 的注册
- **对于恢复路径**：清理 `Recovery\OEM\CMGE\ResetSources\` 中的闭源 payload，保留 LGPO 策略目录