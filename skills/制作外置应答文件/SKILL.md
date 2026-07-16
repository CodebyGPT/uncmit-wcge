---
name: 制作外置应答文件（Unattend.xml）
description: 指导如何创建外置 Windows 应答文件（Unattend.xml / Autounattend.xml），实现覆盖内置 Panther 文件并在 Specialize 阶段调用 EXE/PS1。适用于 Windows 10/11 无人值守安装定制。
---

# 制作外置应答文件（Unattend.xml）

## 概述

无需修改 ISO 或 `install.wim` 中的 `Windows\Panther\unattend.xml`，使用**外置应答文件**完全覆盖内置设置，并在 specialize 配置阶段执行外部 EXE 或 PowerShell 脚本。该方法基于 Microsoft 官方自动安装文档，可靠且与系统版本无关。

## 适用场景

- 需要在 Windows 安装过程中自动执行自定义脚本或程序
- 无法或不希望修改原始 install.wim 中的 Panther 应答文件
- 需要为不同机器使用不同的无人值守配置，而使用同一份 ISO
- 在 Specialize 阶段（系统首次启动前）执行定制操作

## 前置条件

- **Windows ADK**（含 Windows System Image Manager - WSIM）— 用于创建和编辑应答文件
- **目标 Windows 10/11 ISO**（install.wim 无需修改）
- **U 盘**（推荐 FAT32 格式）
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
      publicKeyToken="31bf********4e35"
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
    
    <!-- 可选：覆盖内置设置 -->
    <EnableFirewall>false</EnableFirewall>
  </component>
</settings>
```

**完整文件推荐结构：**

- 包含 `windowsPE`、`specialize`、`oobeSystem` 等必要 pass
- 使用 `<unattend xmlns="urn:schemas-microsoft-com:unattend">` 根节点
- 保存为 `unattend.xml` 或 `autounattend.xml`

### 步骤 2：准备部署介质

1. 将应答文件（`unattend.xml` 或 `autounattend.xml`）复制到 U 盘根目录。
2. 将需要执行的 `SetupScript.ps1`、`MySetup.exe` 等文件复制到 U 盘对应路径（例如 `D:\Scripts\`、`D:\Tools\`）。
3. 将 U 盘与 Windows ISO 一起插入目标机器。

### 步骤 3：启动安装（实现覆盖）

**方式 A（推荐，自动发现）：**

引导进入 Windows Setup（从 ISO 启动）。Setup 会按隐式搜索顺序自动发现 U 盘根目录的 `autounattend.xml`（Search Order 第 4/5 位，高于 Panther 缓存）。

**方式 B（显式指定，最高优先级）：**

在 WinPE 命令提示符下运行：
```
setup.exe /unattend:D:\unattend.xml
```
（`D:` 为 U 盘盘符，请根据实际情况调整）

## 工作原理

基于 Microsoft 官方文档：

- Windows Setup 在每个 configuration pass（包括 specialize）开始时按优先级搜索应答文件。
- **外置文件（U 盘或 `/unattend` 指定）优先级高于 `%WINDIR%\Panther\unattend.xml` 内置缓存。**
- 找到有效文件后会缓存并覆盖之前的设置。
- Specialize pass 在系统首次启动（OOBE 前）执行 `RunSynchronous` 命令，此时 U 盘通常仍可访问。

## 验证方法

1. 安装过程中按 **Shift+F10** 打开 CMD，查看 `C:\Windows\Panther\setupact.log` 确认加载的外置文件。
2. 检查执行结果（脚本日志、注册表变化等）。
3. Specialize 完成后，内置 Panther 文件会被外置文件覆盖/更新。

## 注意事项

- PowerShell 脚本需要 `-ExecutionPolicy Bypass` 参数。
- U 盘盘符在部署时可能变化，可使用 `%~dp0` 相对路径技巧或先将文件复制到硬盘。
- 敏感信息在 pass 结束后会被系统清除。
- 测试时建议先在虚拟机中验证。
- 此方法适用于 Windows 10/11（Microsoft 文档一致）。

## 参考

- [Windows Setup Automation Overview](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/windows-setup-automation-overview)
- [Unattended Setup Reference](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/unattend/)
- [RunSynchronous Reference](https://cleanuri.com/DmPP9k)
