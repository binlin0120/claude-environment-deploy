# Mac 兼容性、来源和未验证边界

编写日期：2026-10-27；官方资料核验日期：2026-10-26。

本文对应 [Mac部署流程](../skills/claude-environment-deploy/references/Mac部署流程.md)。官方资料访问时间为 **2026-10-26**；它们证明的是公开说明和下载项，不是本套方案已在 Mac 上运行通过。当前没有 Mac 实机安装、AdsPower Windows ARM 完整运行、客户出口检测、本人登录或连续聊天的验收记录。

## 1. 开源方案先查过，再决定复用什么

先查了 GitHub 虚拟机方案，选取与 Mac 直接相关的 [utmapp/UTM](https://github.com/utmapp/UTM) 作为成熟开源备选。UTM 基于 QEMU，提供 Mac 图形界面和脚本接口；采用它不需要另造虚拟机安装器。其前端采用 Apache 2.0 许可，也使用其他开源组件；若未来重新打包分发程序，须另核对各组件许可。本交付只提供流程和官方链接，不捆绑安装包。

开源并不自动解决 Windows ARM 的第三方应用兼容性。默认优先 Fusion，是因为它当前免费、具备 Windows ARM 支持，并与本次参考视频路线接近；已有 Parallels 可继续复用，避免为了换工具重建环境。

## 2. 兼容性结论

| 项目 | 2026-10-26 已核对的公开事实 | 本流程的使用边界 |
| --- | --- | --- |
| Apple 芯片与 Windows | Fusion 官方说明 Apple Silicon 来宾需 ARM64；Parallels 官方 Apple 芯片安装指南同样要求 ARM 镜像 | 默认 Windows 11 ARM64；不把整套 x64 Windows 模拟作为常规方案 |
| Intel Mac | UTM 官方 Windows 指南区分 Intel 的 amd64 与 Apple Silicon 的 arm64；amd64 在此就是 x64 架构名称 | 使用 Windows 11 x64，另核对当前虚拟机软件和 macOS 支持 |
| VMware Fusion | 当前产品页列出 Windows 11 ARM、Get Windows、虚拟 TPM、安全启动、快照、命令行和 REST API；2026 年官方公告再次确认商用、教育和个人均免费 | 免费的是虚拟机软件，Windows 许可独立；接口存在不代表来宾部署已全自动完成 |
| Parallels | 官方提供 14 天 Pro 试用，明确是付费软件；已有正式许可可复用 | 不写成永久免费；命令行等能力按当前版本和所购版本核对 |
| UTM | 开源；Apple Silicon 上 ARM64 可硬件加速，整套 x86/x64 模拟较慢；当前官网已列 Windows 11 的 DirectX 11/12 支持 | 不沿用“UTM 完全没有 3D 支持”的旧判断，也不承诺具体浏览器内核和图形功能通过 |
| AdsPower | 官方下载页分别列 macOS Apple Silicon 和 Intel；Windows 列 32/64 位，本轮未找到正式 Windows ARM 支持声明 | “Windows 64 位包”不等于“ARM64 包”；能经系统模拟启动也不等于厂商正式支持，须试装后逐项验收 |
| Claude Desktop | 当前官方页明确提供 Windows ARM64 下载项 | 可以优先用原生 ARM64 包；不能据此推断所有桌面功能、扩展及虚拟机内行为都已支持 |
| Windows 11 许可 | 微软对 Mac 方案的说明要求每个 Windows 11 Pro 实例有适用许可，并说明 Pro 产品密钥不因 x64/ARM 架构而区分 | 先核对已有权益，不强迫重复购买；镜像下载、操作授权、激活和许可不能混为一谈 |

微软介绍 Mac 方案的页面明确列举 Parallels 18/19/20 与 M1/M2/M3，其范围早于部分新机型和新版软件；不能将它改写成对所有芯片、所有版本的无条件背书。实际选版本时仍查看当期兼容性说明。

原 Windows 教程若使用 x64 企业评估镜像，不能直接放到 Apple 芯片分支。评估用途与正式长期许可也不同；本分支提供微软正式 ARM64 下载入口，不默认要求所有人使用评估版或先购买新许可。

## 3. 网络、控制和自动化的边界

NAT 是经主机转发网络地址，Shared 是共享网络模式。它们解决“如何联网”，不自动实现断线防直连、对主机隔离或防止访问局域网。UTM 官方明确说明，共享网络下主客机服务可互相可见；Host Only 阻止外网，但不能单独满足正常外网使用。Fusion、Parallels 的实际网卡、网段和网关也要现场核对，不能照抄 Hyper-V 参数。

PowerShell Direct 是微软 Hyper-V 从 Windows 主机管理本地 Windows 来宾的专用通道，可不依赖来宾网络。Mac 的虚拟机软件没有这个 Hyper-V 通道，因此本地虚拟机控制台必须作为恢复入口。SSH、WinRM 等网络管理只有实际配置和限制后才可使用，不能用“开放整个主机网段”代替设计。

Fusion 当前产品页列出 `vmrun`、`vctl` 和 REST API。脚本可以使用实际安装且可用的接口，但主机侧管理虚拟机与在来宾内执行程序是两类能力，后者还涉及当前来宾工具及版本支持。本交付不新增脚本或远程管理服务，也不把 Get Windows 描述成自动解决 Windows 初始设置、许可、AdsPower 登录和网络保护。

Broadcom KB 315602 中仍有早期 ARM 来宾“不提供 3D、完整来宾工具、vmrun 功能”的描述，与当前产品页的部分能力不一致。此旧页用于核对 ARM 架构限制，不单独用它给当前所有功能下结论。实际来宾命令执行及恢复能力必须在部署版本现场验证。

Mac 原生 AdsPower 是本人可选的另一条路线。Windows 来宾防火墙不能保护宿主机上的原生程序，因此它不等价于来宾隔离方案；更换路线后要重新确认网络保护和验收范围，不能直接继承原结论。

## 4. 指定检测页的作用

本流程要求在实际准备使用的同一 AdsPower 窗口，先打开 https://ip.net.coffee/claude/，完成当次检查，确认当前出口等可见结果符合本人预期且无待处理异常，再打开 Claude。先检查当前已选网络，不自行换国家地区；用途是确认合法使用路径和诊断异常。

这是第三方检测，评分不能替代账号资格、本人登录、连续两轮对话、桌面独立检查或断线测试。远端网页抓取只反映抓取服务的出口，不是客户 Mac 的本机 IP 检测；查看公开页面不能写成“客户已通过”。

此页会接收网络请求及出口信息，具体已核对的数据发送行为与限制见 [使用前检测与可选防护](../skills/claude-environment-deploy/references/使用前检测与可选防护.md)。交付和报告不保存真实 IP、凭据、授权链接或敏感截图。检测打不开、关键结果缺失或有待处理异常时暂停依赖的 Claude 使用，不静默换检测方式；工具做不到时由本人在指定窗口核对，反馈须标注为本人报告。

## 5. 视频参考核对范围

用户提供的参考视频已由主对话在内置浏览器打开，页面信息如下：

- 标题：《小白必看最新版|保姆级Mac安装Windows详细技巧攻略》
- 作者：薛定谔的叨叨
- 页面发布日期：2026-10-14；时长：11 分 50 秒
- 视频编号：7696511723762633984
- 用户提供的短链接：[打开参考视频](https://v.douyin.com/jTZQ-LRf8hM/)

页面章节涉及 VMware Fusion、Windows 11 ARM、TPM、资源配置和安装。已抽查视频约 02:07 的 Broadcom／Fusion 下载页及约 04:43 的 Windows 11 64-bit Arm 虚拟机设置画面，与章节中的基础路线一致，可作为界面操作参考。章节摘要由抖音 AI 生成；尚未逐句观看全片，不能把章节文字或抽查画面当作逐步实测，更不能照搬其中可能出现的激活、绕过硬件检查或跳过联网操作。版本、许可、下载来源和安全设置以官方资料及本人现场实际情况为准。

## 6. 官方来源清单

除明确标注只提供部署入口的项目外，下列官方资料于 2026-10-26 访问。网页内容会更新；官方陈述与本地实测要分别记录。

| 来源 | 用途和可支持的结论 |
| --- | --- |
| [微软 Windows 11 ARM64 下载](https://www.microsoft.com/zh-cn/software-download/windows11arm64) | 正式 ARM64 ISO、多版本镜像及虚拟机用途说明；不代表赠送永久许可 |
| [微软 Windows 11 x64 下载](https://www.microsoft.com/zh-cn/software-download/windows11) | Intel 分支的微软中国官网 ISO 入口，按页面校验值核对下载文件 |
| [微软：在 Apple 芯片 Mac 使用 Windows 11](https://support.microsoft.com/en-us/windows/options-for-using-windows-11-with-mac-computers-with-apple-m1-m2-and-m3-chips-cd15fd62-9b34-4b78-b0bc-121baa3c568c) | 已列举 Mac/Parallels 版本的 ARM 方案、应用限制及每实例许可要求 |
| [Broadcom Fusion 官方下载](https://support.broadcom.com/group/ecx/productdownloads?subfamily=VMware+Fusion) | 登录后按 macOS 版本选正式版 DMG（Mac 安装镜像） |
| [Parallels 中国官网](https://www.parallels.cn/products/desktop/download/) | 厂商的中国下载入口，已有授权可按版本使用 |
| [Fusion 当前产品页](https://www.vmware.com/products/desktop-hypervisor/workstation-and-fusion) | ARM Windows、Get Windows、图形、TPM、命令行和 REST API |
| [VMware Fusion/Workstation 26H1 官方公告](https://blogs.vmware.com/cloud-foundation/2026/05/14/announcing-vmware-workstation-and-fusion-26h1/) | 2026 年再次确认对商业、教育和个人使用免费 |
| [VMware 官方 FAQ](https://www.vmware.com/docs/desktop-hypervisor-faqs) | 免费许可、平台范围、功能和免费用户支持边界 |
| [Broadcom：Apple Silicon 来宾兼容性](https://knowledge.broadcom.com/external/article/315602/windows-11-support-on-apple-silicon.html) | Fusion 需要 ARM64 来宾；其早期功能限制与当前产品页存在差异，不照抄旧结论 |
| [Parallels 免费试用](https://www.parallels.com/products/desktop/trial/) | 付费产品的 14 天 Pro 试用，非永久免费 |
| [Parallels Apple 芯片安装指南](https://kb.parallels.com/125375) | ARM 镜像要求及 Get Windows 11 from Microsoft 的界面步骤 |
| [UTM GitHub](https://github.com/utmapp/UTM) 与 [UTM 官网](https://mac.getutm.app/) | 开源方案、架构转换及当前图形能力；不证明 AdsPower 兼容性 |
| [UTM Windows 指南](https://docs.getutm.app/guides/windows/) | ARM64/Intel x64 区分、官方镜像入口及来宾工具 |
| [UTM 网络说明](https://docs.getutm.app/settings-qemu/devices/network/network/) | Shared、Host Only 等模式的实际边界 |
| [AdsPower 官方下载](https://www.adspower.com/download) | 明确列出的 Mac Apple Silicon/Intel 与 Windows 32/64 位下载项；未据此确认 Windows ARM 支持 |
| [Claude 官方下载](https://claude.ai/download) | Windows ARM64 原生下载项；功能仍需现场逐项核对 |
| [微软 PowerShell Direct 文档](https://learn.microsoft.com/en-us/virtualization/hyper-v-on-windows/user-guide/powershell-direct) | 功能依赖 Windows Hyper-V 主机，不是 Mac 通用通道 |

## 7. 尚需在客户 Mac 完成的验收

1. 实体芯片、当前 macOS、所选虚拟机版本、资料目录与资源余量。
2. Windows 安装、许可安排、来宾工具和可恢复控制台。
3. AdsPower 在目标 Windows ARM 或 x64 来宾中的管理界面、浏览器内核、固定环境和更新行为。
4. 同一 AdsPower 窗口的当次指定检测，以及网页两轮连续新对话。
5. 若包含桌面端，独立网络、本人登录和所需功能的两轮新对话。
6. 若包含对应保护，停止实际代理核心、恢复、来宾重启与更新后的规则和新请求行为。

本文件只是说明依据和限制。上述任一项尚未实测时，继续写“待验证”，不能用官方页面存在、安装包可下载或视频展示替它通过验收。
