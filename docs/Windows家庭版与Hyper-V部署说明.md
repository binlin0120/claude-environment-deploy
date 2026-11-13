# Windows 家庭版与 Hyper-V 部署说明

更新日期：2026-11-13。根据一次实际部署前检查及后续讨论整理。

## 先看结论

Windows 家庭版可以使用适用版本的 VMware Workstation、VirtualBox 等第三方软件创建虚拟机。当前项目的 Windows 创建脚本调用的是微软 Hyper-V，家庭版不满足这条脚本路线的官方系统版本条件。

**按本项目现有脚本和流程部署，升级 Windows 专业版是当前最优解，建议优先升级。** 现有 Windows 建机脚本及配套流程围绕 Hyper-V 编写，满足版本条件后可沿用本包路线，减少另行适配第三方建机、控制通道和网络配置的工作。这项建议针对本项目当前的适配范围，仍需检查硬件、空闲资源和权限。

不准备升级的用户可以考虑第三方虚拟机；目前仓库没有提供已经适配并实测通过的 Windows 第三方建机路线，不能把它写成已经支持的一键替代方案。使用者明确选定后，再按所选软件的官方资料制定和验证适配步骤。

## 这次遇到了什么

一台 Windows 11 家庭版设备执行本项目主机检查，观察到：

- 当前会话不是管理员，`New-VM` 命令不可用，也未找到 Hyper-V PowerShell 模块。
- Hyper-V 功能状态在当前权限下为 `Unknown`，不能把它写成已启用或已完整检查。
- 系统报告 `HypervisorPresent=true`；这不能证明已经具备创建 Hyper-V 虚拟机的管理组件，也不能仅凭部分固件字段为 false 就判定 BIOS 虚拟化关闭。
- 已准备部署资料和记录，但没有升级系统、创建虚拟机、安装来宾或修改网络；使用者选择暂不升级，准备文件保留。

此前“家庭版先升级再继续”的措辞容易让人理解成“家庭版完全不能创建虚拟机”。准确说法应明确所选引擎、脚本依赖和项目已验证的范围，避免把当前项目的适配条件泛化成所有虚拟机软件的条件。

## 为什么脚本不能直接换个平台运行

`New-ClaudeVM.ps1` 是 Hyper-V 的辅助创建脚本，并非独立的虚拟机引擎。它调用 `New-VM`、`Get-VMSwitch` 等 Hyper-V 命令，配置第二代虚拟机、安全启动及虚拟 TPM；默认只输出计划，明确传入 `-Apply` 才创建关机状态的虚拟机。它不安装来宾 Windows、Clash、AdsPower 或 Claude。

补齐 ISO 路径、交换机名称或管理员权限，不能让这些命令自动变成 VMware／VirtualBox 的接口。使用第三方平台时需要相应的管理工具、参数及实际存在的网络设备。

| 对比项 | 当前项目的 Hyper-V 路线 | Windows 第三方虚拟机路线 |
| --- | --- | --- |
| 主机版本 | 按微软官方 Hyper-V 支持范围选择；家庭版需先补齐版本条件 | 依据所选软件当前支持的主机系统判断，不统一要求专业版 |
| 来宾用途 | 安装 Windows、Clash、AdsPower 和所选 Claude 产品 | 同样可规划这些软件，逐项核对兼容性和许可 |
| 建机与管理 | 使用现有 PowerShell 创建入口和 Hyper-V 管理命令 | 使用所选软件界面或命令，需要重新适配 |
| 网络 | 真实 Hyper-V 交换机、虚拟网卡和所选 NAT 等链路 | 所选软件自己的 NAT、桥接等模式，网卡和路径另行核对 |
| 出站保护 | 配置实际来宾防火墙、代理与最小允许规则，再测试 | 同样需要配置与测试，不能直接套用另一平台的接口或认为默认 NAT 已保证保护 |
| 本项目状态 | 已有教程和辅助脚本；全新设备完整部署仍需实测 | 尚无本项目实测通过的创建与验收适配实现 |

更换平台不会自动消除来宾 Windows 和应用的资源需求；性能、共存性及资源分配按目标电脑验证。本项目也没有做两类平台的性能或安全排名测试。

## Agent 遇到家庭版应怎样处理

1. 先识别 Windows 版本、权限、虚拟化与可用资源，区分真实观察和权限不足造成的未知项。
2. 明确用户是否沿用本项目现成的 Hyper-V 路线。沿用时优先推荐专业版升级，说明理由；有效许可先复用，购买、密钥输入和实体电脑重启由本人决定和配合。
3. 用户暂不升级时，保留已完成的检查、部署文件和阶段记录，不自动改走普通浏览器、安装第三方虚拟机或重写创建脚本。
4. 用户明确选择第三方虚拟机时，先说明本包当前适配缺口，再按其官方资料与实际授权实施；不得把未完成的适配标为项目已支持。
5. 虚拟机可启动、来宾软件安装、浏览器检测、Claude 登录与连续对话分别验收，并实测代理停止、恢复和来宾重启后的行为。

## 本次整理的验证范围

本次只修订说明和执行指引，没有修改 PowerShell 部署脚本、启用系统组件、安装第三方虚拟机或执行系统升级。没有完成第三方平台的建机、网络保护或 Claude 全流程实测，不能把文档补充当作新增平台支持。

## 官方参考

- [微软：安装 Hyper-V 与家庭版限制](https://learn.microsoft.com/en-us/windows-server/virtualization/hyper-v/get-started/install-hyper-v)
- [微软：家庭版升级专业版](https://support.microsoft.com/en-us/windows/deployment/install-upgrade/upgrade-windows-home-to-windows-pro)
- [Oracle VirtualBox：支持的主机、来宾与基本功能](https://docs.oracle.com/en/virtualization/virtualbox/7.2/user/Introduction.html)
- [Oracle VirtualBox：NAT、桥接与其他网络模式](https://docs.oracle.com/en/virtualization/virtualbox/7.2/user/networkingdetails.html)
- [Broadcom：VMware Workstation 系统要求](https://knowledge.broadcom.com/external/article/315616)

选型和实际安装前重新核对版本、主机支持、许可和官方发行文件。
