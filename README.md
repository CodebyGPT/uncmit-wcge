# uncmit-wcge

从原版 **Windows 10 神州网信政府版 (wcge)** 的 `install.wim` 中移除 CMIT 闭源组件，
同时保留所有非 CMIT 的系统定制（区域设置、LGPO 本地策略、OOBE 隐藏、开始菜单布局、品牌图、遥测隐私策略）。

## 它做了什么

原版 wcge 镜像通过内置 `unattend.xml` 在系统部署阶段（specialize / oobeSystem）、
升级阶段（SetupComplete.cmd）、以及重置阶段（Reset This PC）调用 6 个 CMIT 闭源部署 exe，
这些 exe 会安装 CMIT 激活/更新/控制中心软件、注册系统服务、创建计划任务、导入 CMIT 专用证书、
注入国密 SMx 算法模块、并通过 `EPrivilege.exe` 提权运行 `CMGEInstaller.exe`。

本项目提供 **6 个去 CMIT 版本的 exe**（仅保留 Preserve 项，注释掉 Disable 项），以及一个交互式
GUI 脚本，把它们替换进你手中的原版 `install.wim`。替换后镜像安装出的系统：

- ❌ 不安装 CMITActivation / CMITControlCenter / CmitUpdateAgent 等闭源软件
- ❌ 不注册 CmitClientSVC 服务、不创建 Daily Runner 等计划任务
- ❌ 不导入 CMIT Root/SubP/signature 证书（消除代码签名信任后门）
- ❌ 不注入国密 SMx 模块、不通过 EPrivilege 提权安装
- ❌ 不重定向 ClipSVC → CmitClient.exe
- ✅ 保留 Netlogon/wlidsvc 禁用、LGPO 本地策略导入、InstallService 扫描任务禁用、遥测隐私注册表
- ✅ 保留 DigiCert 等国际公开 CA（隐私优先策略下，政府/行业 CA 一并清除）

## 交付物

| 路径 | 说明 |
|------|------|
| `dist/InsPreConfig.exe` 等 6 个 | 去 CMIT 的部署 exe（PS2EXE 重打包，源见 `build/`） |
| `src/uncmit.ps1` | 交互式 GUI 替换脚本（PowerShell 7 only，全英文 UI） |
| `build/*.clean.ps1` | 去 CMIT 的 PowerShell 源（可审计，含 `# UNCMIT-DISABLED` 标记） |
| `reverse/*.extracted.ps1` | 从原版 exe 逆向提取的 PowerShell（分析用） |
| `scripts/uncmit-cleanup.ps1` | 后期清理脚本（可选）：首次登录后以管理员身份运行，清除惰性 CMIT 载荷 |
| `docs/exe-locations.md` | 6 个 exe 在 WIM 中的路径与 Disable/Preserve 分类 |
| `docs/audit-report.md` | 原版 ISO 完整审计报告 |

## 使用流程

> 前提：Windows 10/11 主机，已装 **PowerShell 7**，以**管理员**运行。
> 无需手动下载任何文件——脚本会自动从本仓库获取去 CMIT 的 exe。

1. 从原版 wcge ISO 中取出 `sources\install.wim`（或挂载 ISO 后指向该文件）。
2. 以管理员身份打开 PowerShell 7，执行以下**一行命令**：
   ```powershell
   irm https://raw.githubusercontent.com/CodebyGPT/uncmit-wcge/master/src/uncmit.ps1 -OutFile $env:TEMP\uncmit.ps1; & $env:TEMP\uncmit.ps1
   ```
   （该命令把 `uncmit.ps1` 下载到临时目录并运行；脚本会自动下载 `dist/` 下
   的 6 个去 CMIT exe 到临时目录，无需你手动获取二进制。）
3. 在弹出的窗口中点击 **Browse...**，选择你的 `install.wim`。
4. 点击 **Run**。脚本会：
   - 将 WIM 挂载到临时目录（`dism /Mount-Image`）
   - 替换 6 个 CMIT 部署 exe 为去 CMIT 版本（自动下载或本地 `dist/`）
   - 提交并卸载（`dism /Unmount-Wim /Commit`），写回原 `install.wim`
5. 用 Rufus 等工具将修改后的 ISO/USB 正常烧录安装即可。

脚本失败时自动 `Discard` 卸载，不会破坏原 `install.wim`。

> 离线/开发用途：若本地已有仓库，也可直接 `pwsh -File path\to\uncmit.ps1`，
> 脚本会优先使用同目录或上级的 `dist\`，不触发下载。

## 安全说明

- **只禁调用，不删除二进制**：被调用的闭源二进制（EPrivilege.exe、CMGEInstaller.exe、
  CmitClient.exe 等）仍保留在镜像中作为死文件，仅移除其触发逻辑。这符合"最小改动"原则。
- **证书隐私优先**：原版导入的政府/行业 CA（Beijing ROOT CA、BJCA、CEGN、GDCA、SHECA、UCA、
  以及已过期的 OSCCA ROOTCA）全部清除，仅保留 DigiCert 等国际公开 CA，降低中间人信任面。
- **不恢复微软官方更新端点**：按审计结论，不改动 Windows Update 指向，不依赖 hosts 黑名单。

## 后期清理（可选）

安装镜像并首次登录桌面后，建议运行后期清理脚本以清除硬盘上的 CMIT 闭源惰性文件。
由于去 CMIT 的部署 exe 在 specialize/oobeSystem 阶段跳过了所有 CMIT 安装操作，这些文件从未
被注册为服务或计划任务——它们只是躺在磁盘上的死文件，删除对系统无任何影响。

**该脚本是独立可选的**，不会修改你已部署的系统行为。它执行以下手术式清理：

- 删除 `C:\Recovery\` 中的 CMIT 闭源载荷（CMITActivation、CMITControlCenter、CmitUpdateAgent、
  CMITOfflineUpdateInstaller、CMITSMx/SMxCNG、CMGEInstaller、EPrivilege.exe）
- 删除 `C:\Program Files\` 下的 CMIT 遗留文件夹（若有）
- 删除 CMIT 自签证书（CMIT Root Authority、CMIT SubP、CMIT signature）及政府/行业 CA 证书
- 删除 ClipSVC KeyHolder 和注册表残余
- 删除开始菜单/桌面 CMIT 快捷方式
- **保留** LGPO 组策略资产、品牌图、布局配置、重置 exe

```powershell
# 以管理员身份运行（PowerShell 5.1+ 即可，无需 PS7）
irm https://raw.githubusercontent.com/CodebyGPT/uncmit-wcge/master/scripts/uncmit-cleanup.ps1 | iex
```

> ⚠️ 政府 CA 证书（Beijing ROOT CA、BJCA、GDCA、CEGN、SHECA、UCA 等）一并从系统受信任根存储区
> 移除，以降低中间人攻击面（与安全说明中的隐私优先策略一致）。如果需要访问仅信任这些 CA 的
> 国内政府 HTTPS 站点，请手动从 `C:\Recovery\OEM\CMGE\ResetSources\Certificates\` 目录（在
> 运行本脚本前）导入对应证书。

## 风险与免责

- 本项目为实验性逆向工程产物，未经神州网信授权。
- 操作前请备份原版 ISO/WIM。
- 替换后的镜像仅去除 CMIT 闭源组件，系统其余行为与原版 wcge 一致。
- 在虚拟机中验证后再用于物理机。
