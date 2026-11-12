# 来宾 Windows 语言、区域与时间

Windows 来宾安装并首次进入桌面后、网络和 AdsPower 验收前，执行本节。Windows 主机的 Hyper-V 与 Mac 主机的 Windows 来宾均适用；只修改本次选定来宾，不顺带修改物理电脑。

这是 Agent 的配置任务。已获完整部署授权且目标明确时，由 Agent 读取现值、执行必要命令、回读并验收，不能只告诉用户去设置里自行调整。没有浏览器点击工具，不等于不能通过来宾终端配置系统；先检查已有来宾命令通道。确实缺少进入来宾的工具、权限或必要目标信息时，只暂停对应项目，写出具体缺口，继续独立可做的工作。

## 1. 分开确认五层设置

| 层次 | 实际影响 | 执行原则 |
| --- | --- | --- |
| Windows 显示语言及用户语言列表 | 系统界面、键盘和输入法 | 复用当前已选值；要改变时核实目标、语言包和输入法，不把浏览器英文照搬成系统英文 |
| Windows 区域及日期时间格式 | 数字、货币和日期时间的显示习惯 | 按用户已确认习惯配置；区域格式不会改变真实时钟，也不是 Claude 通用的强制要求 |
| Windows 系统时区 | 同一真实时刻在来宾里显示成几点，含适用的夏令时 | 按已确认用途和 Windows 支持的时区标识设置；不能凭出口国家猜一个城市 |
| 实际时钟及校时 | UTC 真实时间是否准确、重启和恢复后是否仍准确 | 确认实际校时来源，验证成功时间和偏差；开关打开不等于同步成功 |
| AdsPower 浏览器语言及其时区 | 网站收到的语言和浏览器向网页报告的时区 | 按 [AdsPower 配置与验收](AdsPower配置与验收.md) 单独设置和实测，不用 Windows 结果代替 |

本包没有找到原机 Windows 显示语言、区域格式及系统时区的确定记录，不能编造“原来就是英文／某个美国时区”。新来宾先回读，保留当前已选值；仅对确需改变而目标仍缺失的项目，一次问清该项目。已有明确目标不重复问。原机 AdsPower 的浏览器语言和网页中文翻译有单独依据，不能据此推断 Windows 设置。
本次明确要求调整但目标未给时，一次请本人确认显示语言、区域与 12／24 时格式、系统时区，或明确接受保留已读现值；不能把回读默认值称为复制原机，已授权的独立工作继续。

不同层可以采用不同值。例如系统界面供本人阅读、区域格式符合本人习惯，浏览器按已选环境设置；不能用“必须全部一致”强迫改动。不要为获得检测页绿色评分改变实际所在地资料或任意更换地区。

## 2. 在正确的来宾和用户下只读盘点

先确认终端属于目标来宾。Windows 用户语言和区域命令针对当前用户；如果管理通道运行在 SYSTEM 或另一管理员账号下，其结果不能代表本人日常使用的来宾账号。先定位正确会话，不能靠改另一个用户的设置宣称完成。

在目标来宾的 Windows PowerShell 中执行下列只读命令。不存在的命令或权限不足分别记为未知，不能替换成主机结果：

```powershell
whoami
Get-Culture | Select-Object Name, DisplayName
(Get-Culture).DateTimeFormat |
    Select-Object ShortDatePattern, LongDatePattern, ShortTimePattern, LongTimePattern
Get-WinUserLanguageList |
    Select-Object LanguageTag, InputMethodTips, Handwriting
Get-WinUILanguageOverride
Get-WinHomeLocation
Get-WinSystemLocale
Get-TimeZone | Select-Object Id, DisplayName, SupportsDaylightSavingTime
Get-Date -Format o
[DateTime]::UtcNow.ToString('o')
Get-Service -Name W32Time -ErrorAction SilentlyContinue |
    Select-Object Name, Status, StartType
w32tm /query /source
w32tm /query /status /verbose
w32tm /query /configuration
w32tm /query /peers
```

`Get-WinUILanguageOverride` 为空通常表示未单独覆盖，Windows 按用户语言列表决定界面语言，不直接判为故障。`Get-WinHomeLocation` 是系统地区选项；`Get-WinSystemLocale` 是旧式非 Unicode 程序使用的系统区域，均不能冒充显示语言。一般不改后者，不为本任务随意启用“Beta: 使用 Unicode UTF-8”选项。

校时命令可能暴露内部时间服务器名；原始结果只在本人机器受控位置查看，公开报告仅保留来源类型、成功／失败、最近成功时间和偏差等必要结果。`Get-Date` 与 `UtcNow` 来自同一台机器，只能检查时区换算，不能相互证明时钟准确。域成员身份也需现场核对；加入组织域的来宾优先遵守组织授时策略，不擅自改成公共时间服务器。

## 3. 按已确认目标执行，再分别回读

以下为 Agent 在目标来宾执行的命令形式，不是另一个一键脚本。变量值必须先从本次已确认目标填入并核对；目标尚未确认就不运行对应变更，也不把跳过写成完成。记录必要旧值和回退方式，不删除原有输入法、账号或语言。

### 区域及日期时间格式

`$targetCulture` 为已确认的 Windows 区域标记。仅在现值确实不同且改动已获授权时执行：

```powershell
Set-Culture -CultureInfo $targetCulture
powershell.exe -NoProfile -Command "Get-Culture | Select-Object Name, DisplayName; (Get-Culture).DateTimeFormat | Select-Object ShortDatePattern, LongDatePattern, ShortTimePattern, LongTimePattern"
```

微软说明 `Set-Culture` 的变化在后续 PowerShell 会话生效，因此用新进程回读；原终端的缓存不能证明失败或成功。切换区域通常会改变其默认日期格式。用户明确要求自定义长短日期或 12／24 小时格式时，再按当前 Windows“语言和区域 → 区域格式”的实际界面处理并检查显示，不能为了凑格式顺手改系统国家、时区或非 Unicode 区域。

### 显示语言和用户语言列表

只有本人明确要求变更显示语言时才处理；先核实 Windows 版本是否允许该显示语言、所需语言包是否已安装，以及下载、磁盘写入和重登的授权。语言标记被命令接受，不代表语言包已安装或界面已切换。

`$targetDisplayLanguage` 为已确认的目标标记；需要添加用户语言时，保留现有列表和输入法：

```powershell
$guestLanguageList = Get-WinUserLanguageList
if ($guestLanguageList.LanguageTag -notcontains $targetDisplayLanguage) {
    $guestLanguageList.Add($targetDisplayLanguage)
    Set-WinUserLanguageList -LanguageList $guestLanguageList
}
Set-WinUILanguageOverride -Language $targetDisplayLanguage
Get-WinUserLanguageList | Select-Object LanguageTag, InputMethodTips
Get-WinUILanguageOverride
```

上述命令不会自动补齐所有语言包。需要本人处理许可或权限时仅停在该项；已有适用工具和授权时由 Agent 完成下载安装及后续设置。微软要求注销再登录才能让显示语言覆盖生效；先保存工作，只注销目标来宾会话，再回读并检查实际 Windows 界面及原输入法可用。不能直接替换整张语言列表而丢掉本人输入法。

### 系统时区

先列出受支持标识，`$targetWindowsTimeZoneId` 必须取自其结果并符合已确认目标。Windows 标识与网页常见的 IANA 标识命名不同，不能直接互填。

```powershell
Get-TimeZone -ListAvailable | Select-Object Id, DisplayName
Set-TimeZone -Id $targetWindowsTimeZoneId -PassThru
Get-TimeZone | Select-Object Id, DisplayName, SupportsDaylightSavingTime
Get-Date -Format o
[DateTime]::UtcNow.ToString('o')
```

确认有修改系统时区的权限后执行；不要通过 `Set-Date` 把实际时钟平移几小时来伪装换时区。还要检查 Windows 是否按位置自动设置时区，避免它稍后覆盖已选固定值；只在与已确认目标冲突时调整对应选项，说明改动及回退方式。不为此全局关闭其他系统定位功能。

## 4. 选定并验证实际校时方式

先检查所选虚拟机软件及来宾工具的实际配置。Hyper-V 有来宾时间同步集成服务；VMware Tools、Parallels Tools 等可能在启动、恢复或周期性校时中介入。Mac 的这些工具不等于 Hyper-V 服务，不能套用它的命令或仅看 Windows 开关。

确定这台来宾的主要授时策略：复用已准确运行的主机／来宾工具同步，或使用获准的 Windows 时间服务来源；域成员按组织策略。记录谁负责启动、恢复和运行期间校时。部分平台允许两类机制配合，不能为了“只留一种”就盲目关闭工具服务；关键是没有相互拉扯、跳时和来源不明。改变工具同步开关前查其当前版本官方说明，并保留本地控制台和原值。

- 使用主机／工具同步：先核实主机真实时间准确、工具已安装且同步策略生效；实际回读来宾时间，并在正常恢复或已授权重启后复验。来源显示本地时钟不一定能单独否定工具校时，但也不能据此宣布准确，必须和可信时间独立比对。
- 使用 Windows 时间服务：核实服务与 provider（向时间服务提供时钟的组件）配置、上次成功同步和实际来源。已有正确来源则复用；停止或禁用状态先查原因，不无条件重新注册服务、清配置或关闭集成工具。
- `Local CMOS Clock`、`Free-running System Clock`、未同步状态或旧成功记录，均不能作为当前网络授时成功的证据。虚拟机恢复后时间暂时正确，也不能替代持续同步验证。

非域成员且本次已明确选择手动 NTP 来源时，`$approvedNtpPeer` 为已核实、获准使用的实际服务器，不默认换成某个公共服务。NTP 是网络校时协议。必要的服务启用及网络规则经确认后，再执行：

```powershell
Start-Service -Name W32Time
w32tm /config "/manualpeerlist:$approvedNtpPeer,0x8" /syncfromflags:manual /update
w32tm /resync /rediscover
w32tm /query /source
w32tm /query /status /verbose
w32tm /query /peers
```

`0x8` 表示以客户端模式请求该时间服务器。原服务被禁用时，只有选定此策略且获准后才修改启动方式；不要未经诊断重置系统服务。每个 `w32tm` 命令都检查退出码和输出；命令返回成功后仍要确认最近成功同步时间已更新、实际来源符合计划。域成员不执行这段手动来源配置，也不把普通来宾设成对外可靠时间服务器。

需要独立比较时，可对同一获准来源使用：

```powershell
w32tm /stripchart /computer:$approvedNtpPeer /samples:5 /dataonly
```

这是对比工具，不会替代真正的服务同步；它与 W32Time 服务的发包方式可能不同。仅 `stripchart` 成功不能证明后台服务通过了防火墙。偏差必须给出实际采样和本次用途的合理标准，不能在未测量时写“时间准确”。服务器不可达、偏差过大或证书因时间错误失败时先定位，不禁用证书校验凑通。

## 5. 默认拒绝出站时，把校时纳入必要连接

先完成可信校时，再施加新的默认拒绝出站策略；如保护已存在，不临时全放通。复用原可行授时方式，新增例外前保存规则和回退入口。规则必须与当前 [部署流程](部署流程.md#3-配置网络与出站限制) 的网络设计共同审查，不能把校时变成绕过既有保护的任意直连口。

- Windows NTP 通常使用 UDP 目的端口 123，W32Time 客户端还会使用源端口 123。若设计为来宾直接访问指定授时服务器，允许规则需限定当前系统内实际服务程序、`W32Time` 服务、UDP、所需本地／远端端口、获准远端地址及适用接口／配置文件；回包按现有有状态防火墙处理。不要添加所有 `svchost.exe` 任意出站、任意地址 UDP 123 或显式全阻止后堆允许的规则。
- 若使用域名，先确认受保护路径下解析可用；Windows 防火墙静态远端地址规则不能靠随便填一个域名解决动态地址。服务器地址变化时重新核对来源与规则，不扩大成全网段。报告不保存实际内部地址。
- 若校时经已验证 TUN（接管系统流量的虚拟网卡）或获准代理路径，先验证该路径对 UDP 校时的支持、解析及路由，再仅允许需要的服务沿指定接口访问指定来源；不能假设 HTTP／SOCKS 浏览器代理会自动承载 NTP。用实际服务重新同步证明规则有效。
- 若采用主机／来宾工具同步，确认该平台实际机制是否需要来宾网络；不为了“开了自动时间”无端给来宾增加公网 NTP 例外。主机时钟准确性仍须单独验证。
- 保护前后分别执行真正的同步并回读来源、最近成功时间和偏差；允许的授时连接在断代理测试中不算违规直连，但不得夹带其他应用流量。没有可行的受控授时路径时，将校时写成受阻并修正方案，不能关闭整个防火墙保护。

本节不提供可直接套用所有机器的固定防火墙命令；实际程序、服务、接口、地址和代理路径必须来自目标来宾的现场证据。具体规则由 Agent 在既有授权内生成、检查语法、应用并回读，不能只把规则要求丢给用户自行编写。

## 6. 结束条件、重登和重启

每层记录原值、已确认目标、实际动作、回读结果和状态。保留当前选择也必须有回读证据，不能写“默认应该没问题”。Windows 结果与 AdsPower 结果分开；显示语言、日期格式与网络校时不能互相替代。

1. 区域：从新 PowerShell 会话回读区域及实际长短日期、时间格式；确认仍在本人目标账号。
2. 显示语言：只在变更后按要求注销再登录，检查实际界面和输入法；语言包未就绪则此项未完成。
3. 时区：回读标识、当前显示和 UTC 换算，核实自动设置没有覆盖已选值；只改时区通常不需重启来宾。
4. 校时：确认来源、最近同步、独立偏差及保护开启后的实际同步；启动、恢复和校时工具各自负责什么写清。
5. 正常重开或已授权来宾重启后，先在未手动纠正前回读上述值，再进入 AdsPower 同环境设置、指定网络检测及产品验收。来宾重启在完整部署既有授权内执行；物理主机重启另按主流程，不借此重启 Mac 或 Windows 主机。

尚未做重登、恢复或重启验证的项目写明未测，并给出下一个具体动作；不反复重启已经验证且没有新变化的环境。回退时按事前保存的原值恢复对应层及新增窄规则，不重置所有语言、网络或用户配置。

## 权威命令说明

以下 Microsoft Learn 页面于 2026-10-28 读取并核实命令用途；这属于文档核对，不代表客户来宾已执行：

- [Set-Culture](https://learn.microsoft.com/en-us/powershell/module/international/set-culture?view=windowsserver2025-ps)：区域变更在后续 PowerShell 会话生效。
- [Get-WinUserLanguageList](https://learn.microsoft.com/en-us/powershell/module/international/get-winuserlanguagelist?view=windowsserver2025-ps) 与 [Set-WinUserLanguageList](https://learn.microsoft.com/en-us/powershell/module/international/set-winuserlanguagelist?view=windowsserver2025-ps)：当前用户语言列表及输入法。
- [Set-WinUILanguageOverride](https://learn.microsoft.com/en-us/powershell/module/international/set-winuilanguageoverride?view=windowsserver2025-ps)：界面语言覆盖及注销再登录要求。
- [Set-TimeZone](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.management/set-timezone?view=powershell-5.1)：按 Windows 标识配置系统时区。
- [Windows 时间服务工具和设置](https://learn.microsoft.com/en-us/windows-server/networking/windows-time-service/windows-time-service-tools-and-settings)：W32Time、NTP 端口、配置、重新同步及查询。
- [Hyper-V 集成服务](https://learn.microsoft.com/en-us/virtualization/hyper-v-on-windows/reference/integration-services)：时间同步服务用途；Mac 平台另查所选虚拟机工具的当前说明。
