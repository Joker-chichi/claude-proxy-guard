# Claude Desktop Proxy Guard

[![Validate skill](https://github.com/Joker-chichi/claude-proxy-guard/actions/workflows/validate.yml/badge.svg)](https://github.com/Joker-chichi/claude-proxy-guard/actions/workflows/validate.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

一套面向 Windows Claude Desktop 的 sing-box 本地代理与防火墙隔离方案，同时也是可安装的 Codex Skill。

> 本项目用于可审计的网络路由与隐私隔离，不保证账号安全，也不能改变 Claude 的地区、付款或服务资格。请仅在 Anthropic 当前支持的地区使用，并遵守服务条款。

## 工作方式

```text
Claude Desktop MSIX
        │ 仅允许 IPv4 127.0.0.1:20808
        ▼
     sing-box
        │ HTTP 或 SOCKS 上游
        ▼
   用户自己的代理服务
        ▼
     Internet
```

它不会启用 TUN，也不依赖 Windows 系统代理或常见的 `7890` 端口。Claude MSIX 包的出站流量由 Windows 防火墙限制；本地代理不可用时，Claude 应保持断网，而不是回退为直连。

## 主要能力

- 生成仅监听 `127.0.0.1` 的 sing-box 配置。
- 写入前运行 `sing-box check`，备份旧配置并原子替换。
- 将含凭据的配置 ACL 限制为当前用户、Administrators 和 SYSTEM。
- 按 Claude 的 Package Family 创建 fail-closed 防火墙规则。
- 事务化更新规则；更新失败时保留临时阻断规则。
- 通过 Windows `ApplicationActivationManager` 启动 Claude MSIX。
- 提供独立、无扩展、固定代理参数的 Edge/Chrome 配置目录。
- 安装登录自启任务、受控桌面快捷方式，以及保留用户数据的卸载流程。
- 在 Windows PowerShell 5.1 上执行自动化测试，并通过 Gitleaks 检查提交历史。

## 环境要求

- Windows 10/11；已在 Windows 11 与 Windows PowerShell 5.1 上测试。
- 已安装 Claude Desktop MSIX。
- 已安装 [sing-box](https://sing-box.sagernet.org/)；已测试 1.14.2。
- 一个由用户合法取得的 HTTP/HTTPS 或 SOCKS5 上游代理。
- 安装防火墙规则和计划任务时需要管理员 PowerShell。

## 使用原则

- 中文界面、中文输入或本地时区本身不是可靠的账号风险结论，也不需要为了“看起来像当地人”而强行伪装。保持系统时间准确，语言与时区按本人真实使用习惯设置即可。
- 比所谓“纯净 IP 分数”更重要的是出口专用、稳定、可验证：单设备优先使用一个低变动的固定端点，不要把轮换代理池当作“魔法池”，也不要在登录、验证和付款期间频繁跨国家、ASN 或 IP 跳转。
- “纯净”“零风控”都不是可验证的保证。第三方检测只能提供线索；购买前仍需检查当前价格、期限、流量、续费与退款条件。个人遇到的月费只能作为预算案例，不能写成长期固定价格。
- 官方注册流程支持邮箱或 Google 登录。强烈建议优先使用本人长期控制、已配置恢复方式和 MFA 的 Google 账号；项目经验认为这样更有利于保持登录与恢复链路完整，并可能减少额外手机验证，但这不是 Anthropic 公布的概率结论，也不保证免验证。
- 若出现手机号验证，优先使用本人长期控制且符合当前要求的号码。第三方接码或临时号码是部分用户会自行尝试的高风险路径，但不受官方保证，可能无法通过、被重复使用、泄露验证码，并导致账号无法找回或订阅损失；本项目不代办、不推荐供应商，也不提供绕过步骤，是否承担这些后果由用户在核查当前规则后自行决定。证件和人脸验证必须由账号本人使用自己的真实材料完成，不能借用他人身份、代扫脸或交出远程控制。
- **中国护照实测可用：**截至 2026 年 10 月，项目作者已使用本人的有效中国大陆护照完成 Claude/Persona 的护照验证与真人自拍。遇到个人 KYC 时，可以优先使用本人实体中国护照；选择 `China` 和 `Passport`，按页面要求拍摄原件并由本人完成自拍。不同账号可能进入不同验证模板，实测通过不等于承诺所有账号必过，也不改变 Anthropic 的地区资格规则。
- **手机线路是重点：**从电脑扫码转到手机前，先确认本人实际身处 Anthropic 当前支持的地区，再确认手机系统时间正确、验证页面可以正常访问，且手机使用安全、稳定、与真实所在地及电脑会话一致的预期线路。若本人不在支持地区，应暂停并等实际移动到支持地区或政策变化后再尝试；若人已在支持地区但手机出口错误、泄漏或不稳定，应先修复网络配置并重新核验。验证开始后不要切换 Wi-Fi、蜂窝网络、国家或出口 IP；手机与电脑出现明显的地区或出口跳变可能导致流程失败。仅修改手机 IP 不会使不受支持地区的用户获得资格。
- 可以在付费前安排约 72 小时的观察期，用来确认端点是否稳定、出口是否一致；这不是保证安全的“养号”，也不应制造虚假互动。

完整判断与操作清单见 [references/account-environment-consistency.md](references/account-environment-consistency.md)。

## 快速开始

克隆仓库：

```powershell
git clone https://github.com/Joker-chichi/claude-proxy-guard.git
Set-Location .\claude-proxy-guard
```

先以普通 PowerShell 预览，不修改系统：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\install.ps1 `
  -Server 203.0.113.10 -ServerPort 12323 -Username USERNAME `
  -Protocol http -PlanOnly
```

确认计划后，从管理员 PowerShell 运行同一命令并移除 `-PlanOnly`。脚本会在本机安全提示框中读取代理密码；不要把密码写进命令行、Issue、聊天或截图。

安装完成后使用桌面上的以下入口：

- `Claude (Proxy Guard)`：检查代理和防火墙后启动 Claude。
- `Claude Clean Browser`：打开独立的无扩展浏览器配置目录。

## 检查与测试

只读检查本机配置、监听进程和出口：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\inspect-claude-proxy.ps1 -CheckExit
```

运行仓库测试：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\test-skill.ps1
```

## 卸载

先预览：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\uninstall.ps1 -PlanOnly
```

再从管理员 PowerShell 移除 `-PlanOnly` 执行。默认只删除本项目创建的计划任务、防火墙规则和快捷方式，并保留配置及 Claude/浏览器用户数据。需要把运行目录移到可恢复归档时，增加 `-ArchiveRuntime`。

## 安全边界

- 本项目不能验证或保证代理 IP“纯净”，也不能消除平台风控。
- 防火墙规则针对 Claude MSIX 包，不等同于 Hyper-V 虚拟机或完整设备隔离。
- 上游代理能够观察部分连接元数据；请自行评估其信誉和隐私政策。
- Claude、Windows、浏览器或 sing-box 更新后，应重新运行测试及只读检查。
- 不要自动化账号注册、验证码、批量登录或身份/地区伪装。
- 第三方接码或临时号码可能带来验证失败、号码复用、隐私泄露、账号无法恢复和订阅损失；本项目只披露风险，不代办或提供绕过步骤。借证件、代扫脸、冒充他人以及交出密码、Cookie、MFA 或远程控制不属于可接受的验证路径。

完整代理工作流和执行约束见 [SKILL.md](SKILL.md)，账号与环境一致性见 [references/account-environment-consistency.md](references/account-environment-consistency.md)，Windows 隔离设计见 [references/windows-isolation.md](references/windows-isolation.md)。

## 关联披露

- `https://iproyal.cn/?r=chichi` 含项目作者的邀请码，作者可能获得佣金或奖励。
- 项目作者声明其拥有并使用 `https://chipays.vip/` 提供 Claude Pro 代充；该网站不属于 Anthropic。应优先选择 Anthropic 官方付款方式，并自行核查当前价格、退款、隐私和交付条款。

### 充值前的重要提醒

请把充值或开通付费计划后触发额外验证视为显著风险。部分用户反馈充值后更容易出现付款、安全、手机号或身份验证，但 Anthropic 没有公开可量化的概率，因此不能断言一定发生或承诺不会发生。

付款前应确认本人能够访问账号邮箱、MFA 和恢复渠道，并愿意使用真实、符合资格的信息亲自完成任何官方验证。不要把密码、短信/MFA/邮箱验证码、Cookie 或远程控制权限交给代充方。如果无法或不愿完成可能出现的验证，应暂缓充值；同时保存商品说明、订单与退款条款，因为付款不代表审核发生时仍能立即或持续获得订阅权益。

## 许可证

本项目采用 [MIT License](LICENSE)。
