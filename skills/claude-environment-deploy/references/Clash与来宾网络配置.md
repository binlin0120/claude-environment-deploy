# Clash 与来宾网络配置

本节是完整部署的必做阶段。完成虚拟机、安装 AdsPower 或给 Codex 一条启动提示，都不等于网络已配置。Agent 应在已选定的 Windows 来宾机内完成：安装或复用 Clash Verge Rev、导入本人已有合法代理、落实已选链路、配置服务和 TUN、限制出站、保存并重开检查、完成中断与恢复及重启验收。不能把这些工作全部改成“请用户自行设置”。

本文件核对日期：2026-10-28。官方发布页当日正式版为 Clash Verge Rev v2.5.8；该项目许可证为 GPL-3.0，使用维护中的开源客户端，不另写代理程序。本文件只提供公开资料和操作规范，未在目标新电脑或 Mac 虚拟机上完成实机验收。

修正版9补充（2026-10-31）：多节点与订阅新鲜度、持久源、当次核心状态及主机外层路径必须分别复核；本版不修改现有主机网络，脚本通过不等于目标新电脑完整验收。

## 1. 先确定操作位置，再盘点

Windows 主机＋Hyper-V 与 Mac 主机＋Fusion／已选虚拟化软件，都在已选 Windows 来宾中执行本节 Windows 步骤。苹果 M 系列来宾通常是 Windows ARM64，但仍须读取来宾实际架构；不能根据宿主机名称猜测。Mac 主机上的 DMG 安装成功，不代表 Windows 来宾已安装代理，更不代表来宾桌面客户端走代理。

需要本人连接来宾时，先分清主机与来宾账户。Windows Hello PIN（本机解锁码）不一定能作为账户密码用于来宾连接或 PowerShell Direct；锁屏时实际选择的登录方式也要核对。用户名和密码只在本机安全窗口填写，不发送聊天。认证失败、来宾未就绪、工具权限不足和网络失败分别排查，不能因“连不进去”就重装。

完整方案已授权来宾安装和网络配置时，继续执行该范围内工作；管理员凭据、账号登录与原生授权弹窗由本人完成。不得因缺少 Hyper-V 专用控制方式而跳过 Mac 来宾：使用 Fusion／Parallels／已选软件的本地控制台，或已获准、实际可用的来宾控制工具。Mac 不能照搬 Windows 主机的 PowerShell Direct（不依赖来宾网络的 Hyper-V 访问方式）。没有可用控制工具时，说明“缺少来宾控制能力”及当前停点，继续独立工作，不能写成已配置完成。

由 Agent 在来宾执行只读盘点；以下命令只读取系统与进程，不打印配置内容、账号、订阅地址或进程命令行：

    Get-CimInstance Win32_OperatingSystem | Select-Object Caption,Version,OSArchitecture
    Get-CimInstance Win32_Processor | Select-Object Name,Architecture
    [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture
    ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    Get-Process -Name '*clash*','*mihomo*' -ErrorAction SilentlyContinue | Select-Object Id,ProcessName,Path
    Get-CimInstance Win32_Service | Where-Object { $_.Name -match 'clash|mihomo' -or $_.DisplayName -match 'clash|mihomo' } | Select-Object Name,State,StartMode
    Get-NetAdapter | Select-Object Name,InterfaceDescription,Status,ifIndex
    Get-NetFirewallProfile -PolicyStore ActiveStore | Select-Object Name,Enabled,DefaultOutboundAction,AllowLocalFirewallRules

Windows 进程架构与操作系统架构可能不同；例如 ARM64 Windows 里正在运行 x64 版 PowerShell，不代表应该安装 x64 代理核心。结合操作系统／处理器与 Windows“设置→系统→系统信息→系统类型”确认。盘点已有 Clash、其他代理核心、VPN、虚拟网卡、系统代理和端口占用，先识别用途，不能为本次安装卸掉无关软件。

只在本机受控界面检查现有订阅是否有效、选用节点和协议、订阅更新时间、代理链是否已配置。不要整份读取、上传或打印私人 YAML、备份包、订阅链接、用户名、密码及控制接口密钥。Agent 应尽量通过原生界面和只输出非敏感字段的查询完成工作。

Windows 主机原脚本路线的源文件、公开下载和交付物保存在主机 D:\Codex。Mac 主机使用 Mac 流程中本人已确认的任务目录；Mac 的 Windows 来宾另核对可用目录，必要时用已授权虚拟磁盘内的来宾 C 盘，不为本节新建 D 盘，也不因缺少 D 盘停止。来宾 C 盘与物理宿主机系统盘分开；来宾程序注册、服务和用户配置按已授权的完整来宾安装范围执行。若改为物理本机安装，系统盘写入按项目规则说明并取得覆盖该写入的授权，不能借用来宾授权。

## 2. 下载、核验、安装匹配版本

先复用已安装且来源、版本、运行状态合适的软件；发现旧版也不要未备份就覆盖升级。需要新装时，从官方 GitHub Release 固定标签下载，保存到前节按平台确认的实际任务目录，并核对安装包确实可由目标来宾读取。不要下载旧 Clash for Windows 的第三方转载，不执行来历不明的“一键修复”。

| 实际安装位置 | 对应 v2.5.8 资产 | 本节用途 |
| --- | --- | --- |
| x64 Windows 来宾 | Clash.Verge_2.5.8_x64-setup.exe | 本节 Windows 安装 |
| ARM64 Windows 来宾，包括苹果 M 系列中对应来宾 | Clash.Verge_2.5.8_arm64-setup.exe | 优先使用 ARM64 原生安装包，不先改走 x64 模拟 |
| Intel Mac 本机，仅用户另选本机路线 | Clash.Verge_2.5.8_x64.dmg | Mac 本机应用，不能替代 Windows 来宾 EXE |
| Apple M 系列 Mac 本机，仅用户另选本机路线 | Clash.Verge_2.5.8_aarch64.dmg | 同上；官方当前说明要求 macOS 12 及以上 |

官方固定发布页：https://github.com/clash-verge-rev/clash-verge-rev/releases/tag/v2.5.8 。在该页选择表中资产，不自动随 latest 漂移。下载失败先检查实际网络、证书、下载错误和文件完整性；不能关闭 TLS（加密连接）验证，也不能下载一个 HTML 错误页后当 EXE 执行。

安装前由 Agent 对下载文件计算 SHA-256（文件内容摘要），并检查 Windows Authenticode（发行方数字签名）。以下变量由 Agent 设为实际下载文件完整路径，不让用户研究命令：

    Get-Item -LiteralPath $InstallerPath | Select-Object Name,Length
    Get-FileHash -LiteralPath $InstallerPath -Algorithm SHA256
    Get-AuthenticodeSignature -LiteralPath $InstallerPath | Select-Object Status,StatusMessage,SignerCertificate

本次从官方 GitHub Release API 读到的两个普通 Windows 安装包摘要为：

| 资产 | 官方 API 的 SHA-256 |
| --- | --- |
| Clash.Verge_2.5.8_arm64-setup.exe | 077efab7874a6be7c48630d19c941ef679fa265f79c243f9d20ce5878eb5a943 |
| Clash.Verge_2.5.8_x64-setup.exe | 821c0f5957f84c8f7d14532044840e8280d708af24a6a143db360b49bd1e7302 |

再次部署时复核固定标签的官方资产信息；摘要不一致、已有签名验证失败或发行方异常时停止安装。签名记录实际状态和发行方，不能预填“有效”。NotSigned（没有该类签名）不自动说明恶意，也不能写“Windows 签名已验证”：从官方 HTTPS 固定发布页取得资产，并与可信官方 API 的 SHA-256 对上，是本节可采用的来源核验路径；官方提供分离签名时也可按对应受信公钥和方法核验，不强迫用户安装额外校验工具才接受前述已完成的官方摘要核对。两种来源证据都无法取得时停在该依赖点。Windows 签名、Tauri 更新签名和 SHA-256 是不同证据，报告说明实际采用哪一种及限制。不要为过关关闭 SmartScreen、系统证书检查或其他保护；系统明确拦截时查原始原因。

核验后由 Agent 启动官方安装界面并完成已授权安装，让本人只处理必须亲自完成的系统授权。先用普通安装包；只有确实缺少 WebView2（应用显示界面的微软运行环境）且不能正常安装它时，才核对官方同架构 fixed_webview2 资产，不能把 ARM64 来宾故障直接归咎于 Mac。安装完成必须启动程序、读取应用版本、确认实际核心进程和路径，不能只凭安装进程退出码成功。

服务模式需要核心和安装路径具备安全权限。官方目前会检查核心文件及上级目录，普通用户不能随意替换以系统权限运行的核心。来宾默认 Program Files 安装适用时优先沿用；若使用其他已授权位置，先检查权限和官方报错，不把整个磁盘权限改成“所有人完全控制”，不递归重置 C 盘权限。下载资料放 D 盘不等于应在普通用户可写的下载文件夹以系统服务运行核心。

## 3. 由 Agent 导入已有代理并落实链路

代理软件不包含免费的可用节点。先确认本人已有、合法且允许当前用途的订阅或服务器；已有资料就继续导入。缺的只有订阅或凭据时，只停在该依赖点，继续完成安装、架构核对、私有备份和其他不依赖资料的工作；不擅自购买、不把资料不足说成“整套已部署”。

由本人在来宾原生窗口安全输入订阅地址、登录资料或代理凭据；Agent 负责导入方式、配置字段、保存、选择、重载和验证。本人安全输入是必要操作，不代表把余下的代理配置交给本人自学。不要把敏感信息放在聊天、命令行参数、公开文件、截图或版本库中。

1. 在 Clash Verge Rev 的“订阅”页选用官方支持的订阅链接导入，或新建／拖入本地配置。已有受控本地配置时优先原生导入，确认没有只生成空配置。
2. 选择本次配置卡片，使其成为活动订阅；确认节点与策略组已出现，记录匿名配置代号和更新时间。连接错误应区分订阅下载、证书、格式与核心重载，不能勾选“允许无效证书”凑成功。
3. 根据已选的普通代理与最终出口关系完成配置，不能自行简化成只有普通代理。若最终出口本身可直接连接且本人已选直连它，不新增中转；若本人已选“普通代理中转＋住宅等最终出口”，落实下段的链路。住宅、独享等是供应商属性描述，不能只凭名字证明属性。
4. 在“代理”页选择应使用的节点／组；完整固定出口路线不保留会回退到 DIRECT（直连）的策略，也不能自动换成其他国家／其他最终出口。需要规则模式时，逐条检查受保护流量及最终兜底去向；不把中国域名全部直连、绕过局域网等默认规则不加审查照搬。

### 自建 VPS 直接做最终出口

已有自建 VPS 且希望网站看到它的公网 IP 时，在目标虚拟机导入自己的节点并选中它。检查该节点和策略组的实际去向，确保指定应用的新请求走这台 VPS。如果另有末端代理，按下节核对链路，最终由末端代理对外连接。用目标虚拟机里的实际应用查公网 IP，并对照代理客户端连接日志确认走的是哪个节点。主机浏览器测出的 IP 只记录主机结果。[自建 VPS 操作和实测范围](../../../docs/完整教程.md#61-用自建-vps-做最终出口)

### 已选链式代理时，不能把前后顺序写反

mihomo 的 dialer-proxy 字段写在最终出口节点上，值指向用于连接它的前置代理节点或代理组。示意链路是：来宾应用→来宾 mihomo→前置普通代理→最终住宅等出口→目标网站。网站应看到最终出口；来宾物理虚拟网卡通常只连接前置代理。

只表示结构的片段如下，不是完整配置，不能单独保存后宣称能用：

    proxies:
      - name: FINAL_EXIT
        # 此处沿用本人在本机已安全填写并核对的最终节点协议、服务器、端口和凭据。
        dialer-proxy: UPSTREAM_GROUP

    proxy-groups:
      - name: UPSTREAM_GROUP
        type: select
        # 这里引用本人实际订阅内已选的前置节点，不能填 FINAL_EXIT 形成环路。
      - name: PROTECTED
        type: select
        proxies:
          - FINAL_EXIT

    rules:
      - MATCH,PROTECTED

FINAL_EXIT、UPSTREAM_GROUP、PROTECTED 都是示例代号。实际由 Agent 在受控本机配置中使用明确且无重名的名称，把已有节点和组完整引用；不把原电脑的 Residential-Alt1、别人服务器、端口、密码、规则整份写死给新用户。不同协议的 UDP（不先建立连接的数据传输）与串联能力不同，应按供应商文档和实测确定，不能给只支持 TCP 的最终出口强加 UDP 或 QUIC。

优先使用 Clash 当前版本的订阅扩展配置／扩展脚本等持久化入口，避免只改会在重载或订阅更新时消失的运行文件。已有配置先本机私有备份再改；如需在已有节点中加入 dialer-proxy，保留完整节点并检查合并效果，不能用一小段 proxies 列表意外覆盖其他节点。mihomo 官方已废弃 relay 类型代理组，不把旧教程 relay 写法当新方案。

**保存后必须检查最终生成的运行配置。** 官方 v2.5.8 文档明确：端口、mode、allow-lan、顶层 ipv6、tun.enable，以及在 TUN 对话框保存过的若干字段受应用设置接管，可能覆盖扩展写入值；扩展列表通常整体替换，DNS 相关对象还有版本特定合并规则。Agent 应在本机对照应用设置和脱敏后的关键有效字段，不把“文件里写了”当成“核心用上了”。不要为读取活动配置把控制接口密钥或私人配置打印到工具输出。

### 换节点或重新导入后，核对订阅、持久源与运行状态

远程订阅、本地节点配置、客户端保存的选择和核心当前使用的选择可能各自独立。刷新远程订阅不会自动替换另一份本地节点，也不保证客户端缓存与防火墙同时更新；“重新导入后不超时”只能证明本次链路改善，不能反推所有旧值都已一致。

1. 核实订阅来源和本次采集时间，对账所选链路及可切换候选的全部相关节点，不只检查当前能用的一个。在本机受控配置中比较活动节点和所选订阅对应项的协议、服务器、端口及该协议需要的认证／公钥／短标识／服务器名称等字段。只报告匹配与否或变化的字段名，不输出值；不能只按同名节点判相同。
2. 核对当前活动配置来源与客户端保存的组选择，再核对正在运行的核心选择；保存文件或旧快照不能证明当前核心已生效。可选 -ReadCoreApi 仅使用现有回环控制接口读取当次状态，不向工具输出密钥、不新增接口。核心证据缺失就写待核对；已确认的保存错误仍要报错，不能被未知掩盖。
3. 依据实际链路的第一跳检查防火墙程序路径、地址、端口、协议和出站接口。最终出口与第一跳可能不同，不能把网站看到的地址直接填成第一跳规则。节点变化时先保留阻断，私有备份后精确更新，不能临时全放通。
4. 保存并重开原应用，先原样回读上述状态，再做新请求；需要订阅更新和来宾重启时，按授权范围分别复验。

本版的 [来宾网络一致性检查](来宾网络一致性检查.md) 提供只读辅助入口。在实际 Windows 来宾运行 scripts/Test-ClaudeGuestNetwork.ps1，可选 -EvidencePath 读取本机私有证据，用 node_pairs 对账多节点、persisted_config_path 核对持久源，并检查 subscription_checked_at_utc 的订阅快照龄；可选 -ReadCoreApi 读取现有本机核心接口。先读该参考了解字段与未知状态。脚本不下载订阅、不修改配置或规则、不停止核心，也不替代本节后面的动态验收。

### 同时核对主机外层路径与增强持久化

按 [主机与来宾链路复核](主机与来宾链路复核.md) 先确认有意串联，再在实际 Windows 主机只读关联本次第一跳与最近转发日志。主机 TUN 开启本身不算故障，住宅等最终节点也可能需要前置代理，不能把超时统一修成 DIRECT。目标匹配只是关联证据，不能独立证明流量来自指定来宾；记录当前限制，不擅自改主机网络。

确有证据且已有授权覆盖必要修改时，由 Agent 私有备份当前全局/单订阅脚本、合并配置和关联规则，仅更新自有条目并去重，保留其他用户内容。按当前版本持久化入口重载，核对生成配置、核心当次状态及新日志，订阅切换和更新后重验，失败按备份回退。不只改运行文件；公共包不放原机器的 7 个私人端点。节点名相同不证明字段相同，订阅缺项也不能单独证明停用。

## 4. 配好服务、TUN、DNS、IPv6 与监听

### 服务和 TUN

在来宾“设置→服务模式”安装并启用所需服务，让本人完成必须的管理员授权。确认首页实际显示服务模式，核对已发现的真实 Windows 服务名、状态及启动方式，再启用 TUN（将系统流量送入本地虚拟网卡）。服务管理进程、GUI 界面进程和实际 mihomo 核心是不同对象，三者不能互相代替。

若官方安全检查拒绝服务模式，先读本机错误原因及实际路径；修复已经证实的目录权限问题或按官方方式在管理员 Sidecar 模式进行受控诊断。管理员 Sidecar 能临时启用 TUN，不等于普通登录后可自动恢复的服务部署已完成；不得跳过持久化验收。不要无依据关闭防火墙、杀毒软件或删除虚拟网卡。

在 TUN 设置中核对实际核心版本支持的 stack（流量处理方式）、auto-route（自动加路由）、auto-detect-interface（识别出口网卡）、strict-route（严格路由）和 dns-hijack（接管指定 DNS 请求），保存后再检查活动配置与真实路由。不要照抄 Mac 的 utun 名称、Linux 的 auto-redirect、旧教程的默认堆栈；这台 Windows 来宾使用的是安装包内实际核心。

### DNS 与 IPv6

DNS 是把域名查成地址的过程；既要让应用查询受控，也要让代理节点本身能被解析。Agent 核对并实施已选 DNS 策略：dns.enable、实际监听、nameserver、需要时的 respect-rules、proxy-server-nameserver 和 TUN 的 dns-hijack。用于解析代理节点的引导解析不能依赖尚未建立的同一代理而形成死循环；如确需直连引导解析，只允许已核定程序／服务访问已核定解析器的必要协议和端口，记为明确例外。

Clash 界面里的“DNS 覆写”用于改变配置来源的优先关系，开关关闭本身不能证明 DNS 泄漏。如果订阅、扩展或活动配置已经启用所需 DNS，核心也确实加载并通过 TUN 接管，界面关闭覆写仍可能正常。反过来，开关打开也不证明所有应用解析都受控。先核对最终有效配置、真实解析路径和防火墙，再决定是否需要覆写；不要为凑一个开关自动改掉已有可用 DNS。

不要把示例公共解析器和所有 DNS 端口一股脑放行，也不能“DNS 能解析”就认定 DNS 请求没有旁路。浏览器 DoH（通过 HTTPS 做域名解析）与应用内置解析可能绕过系统 DNS，应结合真实连接、浏览器检测及防火墙验证；53 端口接管不能证明覆盖所有解析。

dns.ipv6=false 只表示 DNS 不返回 AAAA（IPv6 地址）结果，不等于禁用了 Windows IPv6。按已选能力处理 IPv6：需要支持时验证 IPv6 流量经过同一受控链路；不支持时确保 IPv6 不能通过物理虚拟网卡直连，记录实际设置和测试范围。不能仅关 Clash 一个 IPv6 开关就宣称不泄漏，也不无依据全局卸载 Windows IPv6 协议。

### 实际监听与应用接入

在设置页核对 HTTP／SOCKS／mixed（同时接受多种代理协议）端口、控制端口与绑定范围。只在来宾本地使用时关闭 allow-lan（允许局域网连接），代理和管理接口保持本机回环访问；不要为图方便绑定到所有网卡、开放无认证管理端口。

由 Agent 将 AdsPower 的已选环境接到这台来宾真实监听的正确协议／端口，或按既定方案使用已经实测的系统 TUN，两者选择有依据的一条入口，不胡乱叠加。来宾的 127.0.0.1 是来宾自己，不能把宿主机某端口直接照抄进来宾。实际桌面客户端若不读取系统代理，必须由已验证的 TUN 或该客户端官方支持的配置接管，不能用 AdsPower 网页能联网代替桌面验收。

下面的来宾本地查询只返回监听地址、端口和进程号。先从盘点结果取得并确认实际核心的进程号，设为 $CorePid；不能误用 PowerShell 内置的只读变量 $PID：

    Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue | Where-Object OwningProcess -EQ $CorePid | Select-Object LocalAddress,LocalPort,OwningProcess
    Get-NetUDPEndpoint -ErrorAction SilentlyContinue | Where-Object OwningProcess -EQ $CorePid | Select-Object LocalAddress,LocalPort,OwningProcess

监听检查应与 GUI 端口、活动配置、实际核心路径及应用配置交叉核对。检测器报端口可连、核心存在或托盘图标出现，都不能独立证明流量走了预期最终出口。

## 5. 完整隔离：默认拒绝出站，再做最小允许

本节只用于用户选定并授权的来宾完整隔离方案；不自动作用于 Mac／Windows 宿主机或用户其他工作网络。Hyper-V、Fusion 和 NAT（由主机转发来宾网络）本身都不阻止来宾直连。

先从本地控制台登录来宾管理员，确认网络断开也能操作；Mac 使用虚拟化软件本地控制台。创建可用的来宾快照／检查点或其他已选回退资料，并在本机私有目录备份防火墙、路由、系统代理及 Clash 配置。含地址／凭据的备份不放公开仓库或交付 ZIP。下列变量 $PrivateBackupDirectory 必须由 Agent 指向实际存在、符合保存规则且仅本人可访问的私有备份目录，不是公开项目目录：

    netsh advfirewall export "$PrivateBackupDirectory\before-network.wfw"
    Get-NetFirewallProfile -PolicyStore PersistentStore | Select-Object Name,Enabled,DefaultOutboundAction
    Get-NetFirewallProfile -PolicyStore ActiveStore | Select-Object Name,Enabled,DefaultOutboundAction,AllowLocalFirewallRules

备份文件存在且可用后，再实施规则。域、专用、公用三类网络都应启用防火墙并默认拒绝出站，防止网络类别改变后失效。**默认拒绝不是新增一条显式“阻止所有出站”规则。** Windows 显式 Block（阻止）可能优先于 Allow（允许）；新增显式全阻止会压过本来需要的允许规则。反过来，已有显式宽 Allow 也可能使默认拒绝失去预期效果。

先在本地高级防火墙界面或不外传原始内容的受控查询中审查 ActiveStore（合并后的实际策略）下所有启用的出站规则，逐条关联程序、服务、端口、地址、接口、网络类别与规则来源。重点检查安装器／旧配置给核心、浏览器、桌面程序、PowerShell、svchost 或 System 留下的全网允许。不能只查看本次新建规则就宣布无旁路，也不能批量删除所有既有规则。

对确需收窄的现有宽规则记录原始精确规则名、来源及回退方式，先建立已核定的最小允许，再停用本次冲突项。受域策略或管理平台控制且本地规则不生效时，写清管理策略停点；不要用关闭防火墙规避。

最小允许表由这台来宾的真实链路生成：

| 允许对象 | 允许范围 | 不能使用的替代 |
| --- | --- | --- |
| 当前实际使用的 mihomo 核心完整路径 | 只到第一跳代理的已核实地址、端口、协议及实际出站接口 | 核心到任意公网、整个安装目录或所有核心候选版本全部放行 |
| 代理链第一跳解析／必要引导解析 | 明确程序或服务到所选解析器的必要端口；能经代理的查询经代理 | 全程序 UDP/TCP 53、任意解析器或整个 svchost 全网允许 |
| 必需 DHCP（自动取得来宾局域网地址）、时间同步等 | 只保留实际需要、与对应服务和局域网／指定服务器相符的最小范围 | 把所有 Windows 核心网络规则不加审查全部开放 |
| 应用到来宾本地代理 | 确需时限制实际应用到本地回环监听及端口，并核对回环／UWP 限制 | 浏览器、桌面端或 PowerShell 到任意公网的允许 |

链式代理通常只在来宾物理虚拟网卡看见第一跳，不能把所有最终网站 IP 放行；最终出口可直连时第一跳就是它本身。动态端点要按当前真实解析结果管理最小地址集合；地址改变时先保持阻断，再经受控入口更新精确规则并重验，不临时开放核心任意联网。普通 Windows 防火墙地址规则不要把域名当成固定 IP 使用。

以下为参数化操作示例，必须由 Agent 在目标来宾完成实际盘点、私有赋值和规则审查后执行，不是直接可运行的总脚本。$CorePath 为实际核心完整路径，$FirstHopAddresses 为本机保存的第一跳真实地址列表，$FirstHopPort 与 $OutboundInterface 为其实际端口和接口；示例 TCP 只适用该第一跳实际使用 TCP 的情况，不能照此放开不需要的 UDP：

    New-NetFirewallRule -Name 'ClaudeVM-Core-FirstHop-TCP' -DisplayName 'ClaudeVM core to selected first hop' -Direction Outbound -Action Allow -Program $CorePath -Protocol TCP -RemoteAddress $FirstHopAddresses -RemotePort $FirstHopPort -InterfaceAlias $OutboundInterface -Profile Any -PolicyStore PersistentStore

名称冲突时先检查和更新本次对应规则，不反复新增重复项。建立必要最小允许、处理已证实的冲突宽规则并确认回退通道后，按授权在来宾设置持久默认策略：

    Set-NetFirewallProfile -Profile Domain,Private,Public -Enabled True -DefaultOutboundAction Block -PolicyStore PersistentStore

随后同时回读 PersistentStore 和 ActiveStore，确认三个类别均为启用和默认拒绝，逐条检查最终有效允许范围。已有明确 Block 与所需 Allow 冲突时，定位具体来源后定点调整；不能增加更宽的 Allow 希望盖过 Block。不要关闭默认入站保护，不开放无关入站。

软件更新可能新增出站允许规则，程序路径与程序包身份也可能变化。更新前后重新审查 ActiveStore，结合程序、服务、程序包、用户、地址、端口和接口判断真实适用对象。Program=Any（程序筛选为任意）若仍有限定服务或程序包，不等于允许所有程序；反之，规则名带 TUN 也不能证明接口确实受限。受保护程序出现能绕过所选 TUN 的新允许时，保留原始精确规则和回退方法，再按授权定点收窄，不批量删除系统规则。

Windows 过滤机制与不同 TUN 栈的结合需要实测。默认拒绝后若 TUN 应用流量不通，先用本机防火墙记录、核心连接与路由确定拦截位置；不能为了测试通过把 PowerShell、浏览器或核心的物理接口任意公网权限打开。只有已经证明局限于本地回环或 TUN 虚拟接口、不会形成物理接口旁路的最小规则，才可作为必要连接加入并重验。不能保证该组合正常工作时，保留阻断、明确故障和待验证项，不能用“开关已开”代替结论。

原电脑某些进程看门狗（定时检查并关闭程序）可作为辅助，但不是本节默认拒绝出站规则的替代。不要移植会改坏原有保护的一键工具，也不为本节新增无关监控程序。

## 6. 保存、重开：先读状态，不能先修正再算通过

按已确认的启动方式保存活动订阅、运行模式、选中组与节点、TUN、DNS、IPv6 和应用入口，并核对实际服务恢复机制。登录后手动启动原应用也是一种有效范围，应在复验时如实记录；不额外设置 Windows 自动登录，不把手动启动后可用写成开机无人操作联网。确需新增应用自启时，先说明具体改动并纳入已确认计划后执行。mihomo 的 profile.store-selected=true 可保存策略组选择，但仍须核对客户端是否实际保留、订阅更新是否改变节点名；不是写一个字段就承诺永远不变。

1. 记录当前非敏感状态和待核对项：版本、实际核心路径、活动配置匿名代号、策略组选择代号、TUN／服务状态、监听端口、防火墙默认动作、规则组与例外类型。真实端点与凭据只留本机受控配置。
2. 退出并重新启动 Clash 应用，重新打开同一 AdsPower 固定环境。首先原样回读实际状态，不要自动切回节点、重开 TUN、重载配置后再声称“持久化通过”。发生丢失即记录失败，修复后重新开始该测试。
3. 新请求必须落到既定最终出口，不能在住宅节点失败后静默回退到普通代理或 DIRECT；订阅能更新也不能代替链路验证。严格规则阻止某项更新时记录并按已授权维护方式处理，不加全网直连例外。
4. 无人登录前、登录后、界面未启动时分别以实际启动设计为准；只测登录后的状态，就只报告这一范围。服务进程仍在不等于核心或 TUN 已恢复。

## 7. 同一浏览器与独立桌面验收

https://ip.net.coffee/claude/ 保留为来宾访问限制中的明确浏览器检测例外；默认出口脚本的 Claude trace 连续 3 次请求只测连通与出口，不是双独立来源，不证明住宅属性、登录或对话，其他第三方归属查询放主机。检测被策略阻止时先报告，不擅自扩大允许范围。

先按 AdsPower配置与验收.md 保存并打开实际目标环境。在同一目标窗口先打开 https://ip.net.coffee/claude/ ，等待本次结果，检查预期最终出口、国家／地区、DNS、WebRTC（浏览器实时通信）、时区及 IPv6 等可观察结果。缺少结果、打开失败、出口不符或异常未解决时，停在依赖它的 Claude 网页步骤。不要换普通浏览器截图或 PowerShell 结果代替，也不把页面评分当作唯一判据。

当本次检测符合既定要求且无待处理异常后，再在同一窗口打开 Claude 官方网页，由本人完成登录；服务资格另按部署流程核对。只记录检测时间、匿名环境代号和非敏感结论，不记录真实公网 IP、不上传含真实地址的截图。

本次包含 Claude Desktop 时，在真实桌面应用中独立检查代理接管、登录、两轮新对话及第二轮承接第一轮；不能因为网页和检测页通过就默认桌面通过。需要账号或付费调用的测试先遵循已有授权，不能用读取密钥来证明安装成功。

最低测试顺序如下，所有请求使用新连接／新页面，排除旧缓存和已有响应：

| 阶段 | Agent 的实际操作 | 通过条件与边界 |
| --- | --- | --- |
| 正常链路 | 回读配置和规则；同一浏览器完成本次检测；检查所选产品 | 与已选最终出口一致，浏览器和桌面分别有证据 |
| 核心中断 | 在本地控制台中停止实际核心／对应服务，确认核心已不存在且未被自动拉起；只关 GUI 不算 | 同一浏览器、所选桌面产品及未获准程序的新请求不能直接访问未获准公网目标；明确代理端点及必要基础连接例外 |
| 核心恢复 | 恢复原核心与服务，先回读运行状态，再在同一浏览器重新完成检测和所选产品验证 | 原链路恢复，没有临时宽规则遗留，桌面独立复验 |
| 来宾重启 | 在已授权计划内重启 Windows 来宾，先回读持久策略、服务／启动项、活动配置、组选择、TUN、DNS、监听和应用入口，不先手动修正 | 不靠补开开关或改节点即可达到已声明启动阶段；同一浏览器重新检测，桌面独立复验 |
| 更新后复验 | 程序、核心、订阅、系统或浏览器更新后按影响重验 | 路径、端点、组名和规则变化没有造成旁路或丢失；未更新实测就写未测 |

核心获准连接的第一跳和事先明确的基础连接不是违规直连；允许范围必须能逐项说明，不能因此把所有失败都解释为正常。核心停下后若代理核心自动重启，先标记“中断条件未建立”，不能算断网保护已验收。

默认拒绝出站可能让系统测试脚本本来就无法直连测试网站；这是测试条件，不应给 PowerShell 任意联网权限来凑绿灯。必要时在已验证的代理入口检查系统请求，结合浏览器、桌面和最小规则证据，不把脚本失败自动解释为泄漏，也不把脚本失败当作所有应用绝不直连的证明。

若来宾重启后首次状态失败，保留原始脱敏结果，定位原因，修复后重新重启测试。Mac 宿主机重启、物理 Windows 主机重启和 Windows 来宾重启是三种不同范围；只按已授权范围操作，分别记录，不能互相冒用结果。

## 8. 停点、回退和交付记录

遇到错误先区分架构、安装来源、权限／服务、订阅格式、第一跳连接、链路顺序、DNS、TUN 路由、Windows 规则或产品本身。先保留脱敏错误，换有依据的方法，不重复运行同一失败步骤；不直接把 Mac／ARM64 判成不支持。

修改规则导致失联时，通过先前验证的本地控制台撤销本次精确改动；必要时恢复本次私有防火墙备份。整份导入会影响备份之后的所有规则，因此先核对时间与本次范围；不要清空全部防火墙、删除用户浏览器资料、重置主机网络或拆掉现有正常代理。实际回退命令由 Agent 按选定备份与范围执行，不把维护责任全部交给用户。

交付记录至少逐项写明：Windows 来宾位置与架构；Clash 与核心版本和来源核验；代理资料是否已导入；链路、TUN、DNS、IPv6 和持久化是否完成；三类防火墙默认动作与最小例外类型；正常、中断、恢复、来宾重启及所选浏览器／桌面的实测结果；未完成项、具体原因和下一步。地址、凭据、私人配置及备份不进入公开交付物。

本文件与公开包的文字／静态检查完成，只能标“部署说明已补齐”。没有新电脑实操证据时必须写“安装、链路与隔离尚待目标电脑验收”，不能写“Mac 已完整配置”“已保证不泄漏”或“一键部署全部完成”。

## 9. 本次核对的官方来源

以下均于 2026-10-28 只读核对。网页会继续更新，实际部署优先固定所用版本并读取对应说明：

- Clash Verge Rev 官方仓库与许可证：https://github.com/clash-verge-rev/clash-verge-rev ；https://api.github.com/repos/clash-verge-rev/clash-verge-rev/license 。
- v2.5.8 固定发布页与官方资产信息：https://github.com/clash-verge-rev/clash-verge-rev/releases/tag/v2.5.8 ；https://api.github.com/repos/clash-verge-rev/clash-verge-rev/releases/tags/v2.5.8 。
- 官方安装、架构、资产和组件说明：https://www.clashverge.dev/install.html 。
- 官方订阅导入与快速入门：https://www.clashverge.dev/guide/profile.html ；https://www.clashverge.dev/guide/quickstart.html 。
- 官方服务模式说明与 Windows 服务权限错误处理：https://www.clashverge.dev/guide/term.html ；https://www.clashverge.dev/faq/windows.html 。
- 官方扩展合并与应用字段优先级：https://www.clashverge.dev/guide/extend.html 。
- mihomo 官方 dialer-proxy 方向、示例与 relay 迁移：https://wiki.metacubex.one/config/proxies/dialer-proxy/ 。
- mihomo 官方 TUN、DNS、IPv6 与选中节点保存：https://wiki.metacubex.one/config/inbound/tun/ ；https://wiki.metacubex.one/config/dns/ ；https://wiki.metacubex.one/config/general/ 。
- Microsoft 官方 Windows 防火墙规则优先级、出站默认拒绝与规则合并：https://learn.microsoft.com/en-us/windows/security/operating-system-security/network-security/windows-firewall/rules 。

官方资料也是待核对参考；其中通用排错建议若要求关闭全部防火墙、允许无效证书、删除网卡或扩大访问范围，不自动适用于本项目。以当前授权、实际错误、既有保护和可复现验证决定具体操作。
