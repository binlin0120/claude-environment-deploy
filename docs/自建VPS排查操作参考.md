# 自建 VPS 卡顿排查操作参考

适用于已经有自建 VPS、希望保留现有公网 IP 的用户。先找出慢在哪一段，再决定要不要改浏览器规则或测试 BBR。示例中的 `7897`、`443`、`sing-box.service` 和节点名都要按自己当前的配置核对。

## 1. 在电脑和 VPS 上分别下载同一文件

先在实际使用的 Chrome 和 AdsPower 中打开新的 IP 检测页，并对照 Clash 的连接列表确认该浏览器走的是哪台 VPS。下面的下载命令用于比较传输速度。浏览器是否走原出口，仍要在浏览器里查。

**Windows 电脑上运行。** 把 `7897` 改成这台电脑里 Clash 实际的 SOCKS 或混合代理端口，混合端口就是同时接收 HTTP 和 SOCKS 连接的本机端口。`127.0.0.1` 指运行命令的这台电脑。在虚拟机里执行时，要填虚拟机自己的端口。

```powershell
$proxyPort = 7897
curl.exe -q -sS -f --noproxy localhost --proxy "socks5h://127.0.0.1:$proxyPort" --connect-timeout 6 --max-time 15 -o NUL -w 'http=%{http_code} bytes=%{size_download} seconds=%{time_total}\n' 'https://speed.cloudflare.com/__down?bytes=1000000'
"curl exit=$LASTEXITCODE"
```

**登录 Linux VPS 后运行。** `--noproxy '*'` 让这个测试请求跳过 curl 的应用代理设置，检查 VPS 到测速站这一段。VPS 若另外配置过全局透明代理或改过路由，先核对该请求实际走哪里。

```bash
curl -q -sS -f --noproxy '*' --connect-timeout 6 --max-time 15 -o /dev/null -w 'http=%{http_code} bytes=%{size_download} seconds=%{time_total}\n' 'https://speed.cloudflare.com/__down?bytes=1000000'
printf 'curl exit=%s\n' "$?"
```

两边尽量在同一时段各跑几次。返回 `http=200`、`bytes=1000000` 且 `curl exit=0` 才记为完整下载。退出码 `28` 是超时，记下实际收到的字节。VPS 自己下载多次都快、电脑经代理多次都慢时，再查电脑到 VPS 这段。两边都慢时，换一个可靠的测速目标，并检查 VPS 负载和它到目标的网络。[curl 参数说明](https://curl.se/docs/manpage.html) · [Cloudflare 测速接口说明](https://github.com/cloudflare/speedtest)

## 2. 网页卡顿时看 Clash 连接记录

在目标浏览器新开一个网页，到 Clash 的连接列表看**程序名、目标端口、TCP 或 UDP、命中的规则、实际节点**。只有当这次请求确实用了 UDP 443、出现只发不回或走了意外的直连路径时，才考虑让这个浏览器回退到 TCP。先备份当前配置。

下面是 Mihomo（Clash 的代理内核）的规则片段。`REJECT` 表示拦下请求，`我的自建VPS` 要换成你配置里已经存在的节点或策略组名。先确认它确实选中原 VPS。把示例行合并进已有 `rules` 列表，放在需要保留的专用例外之后、会抢先匹配该请求的通用规则之前。

```yaml
rules:
  - 'AND,((PROCESS-NAME,chrome.exe),(NETWORK,UDP),(DST-PORT,443)),REJECT'
  - 'AND,((PROCESS-NAME,chrome.exe),(NETWORK,TCP)),我的自建VPS'
```

这两条用于演示 Chrome 的规则顺序。需要对 AdsPower 做同样的测试时，先核对连接里显示的实际进程名，例如 `SunBrowser.exe`。如果只需要修正网页 UDP 443，已有 TCP 路由时只加第一条。若还需允许其他 UDP，请先确认原 VPS 和节点协议支持，并核对规则是否会落到 `DIRECT`（不经代理直接连接）。应用后，用原浏览器新开请求，看规则是否命中、网页能否连上、公网 IP 是否仍与原 VPS 一致。若目标网站或其他连接受影响，恢复配置备份并复测。[Mihomo 路由规则说明](https://wiki.metacubex.one/config/rules/)

## 3. 在 Linux VPS 上查看连接并临时对照 BBR

以下以使用 `systemd`（Linux 的服务管理工具）的 VPS 为例。把服务名和端口改成自己的实际值。这一段只读取状态。保持电脑端正在通过代理下载，再查看 VPS 的 `ss` 输出，找出这次新连接的算法名和重传情况。`ss` 是 Linux 查看网络连接的工具。

```bash
proxy_service=sing-box.service
proxy_port=443
systemctl is-active "$proxy_service"
sysctl net.ipv4.tcp_congestion_control net.ipv4.tcp_available_congestion_control
sudo ss -tinp state established "( sport = :$proxy_port )"
```

当两段测速和连接记录都指向电脑到 VPS 这段，并且系统支持 BBR 时，可以安排短时对照。BBR 是服务器调整 TCP 发送速度的算法。在**同一个登录终端**记下旧算法。若 `bbr` 已在可用列表里，直接测试。若系统带有 `tcp_bbr` 模块但尚未加载，可先执行 `sudo modprobe tcp_bbr`，再检查可用列表。仍无 `bbr` 就结束本次对照。

```bash
original_algorithm=$(sysctl -n net.ipv4.tcp_congestion_control)
printf '原算法：%s\n' "$original_algorithm"
sudo sysctl -w net.ipv4.tcp_congestion_control=bbr
```

电脑端再开一次下载，同时在 VPS 上重跑 `ss`。如果代理的新连接仍显示旧算法，原监听端口可能沿用了旧值。只有确认服务名且允许这台 VPS 的使用者短暂重连时，才重启这一个代理服务，然后检查服务状态、再从电脑发起下载，同时复查连接。

```bash
sudo systemctl restart "$proxy_service"
systemctl is-active "$proxy_service"
sudo ss -tinp state established "( sport = :$proxy_port )"
```

用同一出口、同一文件、同一客户端交替测原算法和 BBR，把成功和超时都记下来。若效果不稳或需要回退，在原终端执行下方命令。原终端已关闭时，先按记录把变量设为原算法。若代理监听仍保留了 BBR，再按上面的服务重启步骤处理，最后核对新连接的算法、服务状态和浏览器出口。

```bash
if [ -n "$original_algorithm" ]; then
  sudo sysctl -w "net.ipv4.tcp_congestion_control=$original_algorithm"
fi
```

这些命令改的是当前运行设置。VPS 重启后是否保留，要单独验证。[Linux 内核的 TCP 算法说明](https://docs.kernel.org/networking/ip-sysctl.html) · [ss 命令说明](https://github.com/iproute2/iproute2/blob/main/man/man8/ss.8)
