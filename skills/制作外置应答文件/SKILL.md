---
name: 制作外置应答文件（Unattend.xml）
description: 指导如何创建外置 Windows 应答文件（Unattend.xml / Autounattend.xml），利用隐式搜索优先级在 Specialize 阶段调用 EXE/PS1，而无需修改 install.wim。适用于 Windows 10/11 无人值守安装定制。
---

# 制作外置应答文件（Unattend.xml）

## 概述

无需修改 ISO 或 `install.wim`，将应答文件置于外置介质（U 盘）或使用 `/unattend` 显式指定，即可让 Windows Setup 在 installation 的各个 configuration pass 中使用外置设置。外置文件优先级高于 `%WINDIR%\Panther` 中的缓存文件：在每个 pass 开始时，Setup 搜索最高优先级的应答文件并将其缓存；若外置文件包含某 pass 的设置，则该 pass 使用外置设置，未包含的 pass 则可能继续使用已有缓存（按 pass 合并，而非整体抹除）。

## 适用场景

- 需要在 Windows 安装过程中自动执行自定义脚本或程序
- 无法或不希望修改原始 install.wim
- 需要为不同机器使用不同的无人值守配置，而同用一份 ISO
- 在 Specialize 阶段（系统首次启动前，OOBE 之前）执行定制操作

## 前置条件

- **Windows ADK**（含 Windows System Image Manager - WSIM）— 用于创建和验证应答文件
- **目标 Windows 10/11 ISO**（install.wim 无需修改）
- **U 盘**（仅存放应答文件和小脚本时推荐 FAT32；若需存放超过 4GB 的文件如 install.wim，请使用 NTFS 或 exFAT）
- **可选：** 需要执行的 PowerShell 脚本（`.ps1`）或 EXE 文件

## 流程

### 步骤 1：创建外置应答文件

1. 打开 **WSIM**（Windows System Image Manager）。
2. 创建新应答文件：**File → New Answer File**。
3. 加载 `install.wim`（通常 Index 1 为客户端版）。
4. 添加以下组件到对应 pass（重点是 **specialize**）。

#### Specialize Pass 关键配置

以下 XML 片段展示如何在 `specialize` pass 中通过 `Microsoft-Windows-Deployment` 组件添加同步命令：

```xml
<settings pass="specialize">
  <component name="Microsoft-Windows-Deployment"
      processorArchitecture="amd64"
      publicKeyToken="31bf3856ad364e35"
      language="neutral"
      versionScope="nonSxS"
      xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State"
      xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
    <RunSynchronous>
      <!-- 执行 PowerShell 脚本 -->
      <RunSynchronousCommand wcm:action="add">
        <Order>1</Order>
        <Path>powershell.exe -NoProfile -ExecutionPolicy Bypass -File "D:\Scripts\SetupScript.ps1"</Path>
        <Description>运行自定义 PS1 脚本</Description>
      </RunSynchronousCommand>

      <!-- 执行 EXE -->
      <RunSynchronousCommand wcm:action="add">
        <Order>2</Order>
        <Path>D:\Tools\MySetup.exe /quiet /norestart</Path>
        <Description>运行自定义 EXE</Description>
      </RunSynchronousCommand>
    </RunSynchronous>
  </component>
</settings>
```

> **注意**：
> - `Order` 必须是**唯一的正整数**，不可重复。
> - `RunSynchronous` 命令在 `specialize` pass 中以 **System 账户**运行。
> - **不要在命令中直接调用重启或关机**。若命令（如某些驱动/运行库安装程序）需要触发重启，应添加 `<WillReboot>OnRequest</WillReboot>` 子元素（可选值：`Always`、`OnRequest`、`Never`），让 Setup 代为重启并继续。
> - `publicKeyToken="31bf3856ad364e35"` 为 Microsoft 组件公钥令牌，WSIM 创建应答文件时会自动填充此值，无需手动输入。

**完整文件推荐结构：**

- 包含 `windowsPE`、`specialize`、`oobeSystem` 等必要 pass
- 根节点需声明 `wcm` / `xsi` 命名空间前缀（片段中已用到这两个前缀）：

  ```xml
  <unattend xmlns="urn:schemas-microsoft-com:unattend"
            xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State"
            xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
  ```

- 保存文件名取决于使用方式：自动发现时必须保存为 `Autounattend.xml`；显式指定（`/unattend`）时可任意命名（如 `unattend.xml`）。

### 步骤 2：准备部署介质

1. 若使用**自动发现（方式 A）**：将文件命名为 `Autounattend.xml`，复制到 **U 盘根目录**。
   若使用**显式指定（方式 B）**：文件名可任意（如 `unattend.xml`），路径在步骤 3 中指定。
2. 将需要执行的 `SetupScript.ps1`、`MySetup.exe` 等文件复制到 U 盘对应路径（例如 `D:\Scripts\`、`D:\Tools\`）。
3. 将 U 盘与 Windows 安装介质一起插入目标机器。

### 步骤 3：启动安装

**方式 A（自动发现，推荐用于标准部署）：**

引导进入 Windows Setup（从 ISO/U 盘启动）。Setup 在隐式搜索顺序中会自动发现 U 盘根目录的 `Autounattend.xml`（Search Order 第 4/5 位，优先级高于 Panther 缓存）。
> **关键限制**：自动发现仅识别根目录下的 `Autounattend.xml`；命名为 `unattend.xml` 将**不会**被自动发现。

**方式 B（显式指定，最高优先级）：**

从 Windows PE 启动安装（例如从 ISO 引导后在 WinPE 阶段），打开命令提示符运行：
```
setup.exe /unattend:D:\unattend.xml
```
（`D:` 为 U 盘盘符，请根据实际情况调整。注意：`/unattend` 仅在 `setup.exe` 从 WinPE 启动时可用，在已运行的 Windows 中启动 setup.exe 时不支持该选项。）

## 工作原理

基于 Microsoft 官方文档（Windows Setup Automation Overview）：

- Windows Setup 在每个 configuration pass（包括 specialize）开始时按隐式搜索顺序搜索应答文件，命中最高优先级的文件后将其验证并**缓存**到计算机。
- 外置文件（U 盘自动发现或 `/unattend` 显式指定）优先级高于 `%WINDIR%\Panther\unattend.xml` 缓存。
- 缓存位置：windowsPE / offlineServicing 阶段缓存到 `$Windows.~BT\Sources\Panther`；系统展开后缓存到 `%WINDIR%\Panther`。
- Specialize pass 在系统首次启动（OOBE 前）执行 `RunSynchronous` 命令，此时 U 盘通常仍可访问。

## 验证方法

1. 安装过程中按 **Shift+F10** 打开 CMD：
   - WinPE 阶段：查看 `X:\Windows\Panther\setupact.log` 或 `$Windows.~BT\Sources\Panther\setupact.log`
   - 系统展开后：查看 `C:\Windows\Panther\setupact.log`
   - 搜索 "unattend" 可确认加载的外置文件路径。
2. 检查执行结果（脚本日志、注册表变化等）。
3. Specialize 完成后，外置应答文件的内容会被缓存到 `%WINDIR%\Panther\unattend.xml`，供后续 pass 使用。

## 注意事项

- PowerShell 脚本需要 `-ExecutionPolicy Bypass` 参数，或在外置文件中配置执行策略。
- **U 盘盘符在部署时可能变化**：
  - 若使用批处理脚本（`.cmd`/`.bat`），可用 `%~dp0` 获取脚本所在目录。
  - 若使用 PowerShell（`.ps1`），可用 `$PSScriptRoot` 获取脚本所在目录（`%~dp0` 在 PowerShell 中无效）。
  - 更稳妥的做法：在 `windowsPE` pass 中先将脚本/EXE 复制到硬盘固定路径（如 `%SYSTEMDRIVE%\Scripts\`），然后在 `specialize` 中从硬盘执行。
- Setup 会在每个 configuration pass 结束时清除**缓存应答文件**中的敏感数据（如密码），但**不会**在日志或内存中清除。交付设备前，应手动删除 `%WINDIR%\Panther\unattend.xml` 缓存文件。
- 测试时建议先在虚拟机中验证。
- 此方法适用于 Windows 10/11（与 Microsoft 官方文档一致）。

## 参考

- [Windows Setup Automation Overview](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/windows-setup-automation-overview)（含 Implicit Answer File Search Order、Sensitive Data in Answer Files）
- [Unattended Setup Reference](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/unattend/)
- [RunSynchronous](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/unattend/microsoft-windows-deployment-runsynchronous)
- [RunSynchronousCommand](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/unattend/microsoft-windows-deployment-runsynchronous-runsynchronouscommand)
- [Microsoft-Windows-Deployment](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/unattend/microsoft-windows-deployment)
- [Windows Setup Command-Line Options（/Unattend）](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/windows-setup-command-line-options)
