# Sill Product Requirements Document

| Field | Value |
|---|---|
| Product | Sill |
| CLI / binary | `sill` |
| Config | `~/.config/sill/` |
| `TERM_PROGRAM` | `sill` |
| Tagline | Sill — the attention surface for agents |
| One-liner | 用 libghostty 的核，跑并行 Agent 时比 Otty 更清楚、更轻、能带走。 |
| Document | PRD v0.4 |
| Date | 2026-10-08 |
| Status | Draft |
| Author | Henry Zhang |
| Market | Global English-speaking developers first；CJK 渲染与 IME 为 P0 |
| Platforms | macOS + Linux 一等；Windows GUI 不进 v1 |
| Supersedes | `Sill-PRD-v0.3.md` 及更早的 Keel 稿 |

禁止对外说「比 Ghostty 快」。禁止用 Terminal Mode 的 bench 冒充产品形态。禁止自造私有状态方言当主协议。

---

## 0. Executive Summary

Sill 是 **Agent 终端**。

打开后第一屏是会话画布，不是空 shell。底下是 libghostty 诚实 PTY。上面是注意力轨道、Focus Ring、Dual Surface、Composer。Terminal Mode 是开关，不是首页。

重点只有一句：

> 并行 CLI Agent 时，「谁在等你」是导航本身；终端核和会话状态都不锁在 App 里。

界面是现代、克制、拿来就能用。苹果式：少装饰、字清楚、主操作只有一个。大胆只留在结构（轨、环、Composer），不留在装饰。

程序状态的主源是公开的 **OSC 7501**。官方 hook 只是还没发 7501 的 CLI 的回退。没有事件就显示 unknown，不猜。

不是更快的 Ghostty。不是功能更多的 Otty。不是带浏览器的 Ghostex。不是劫持输出的 Warp。

对 Ghostty：核同一档，嵌它的库，不打它的 `cat`。对 Otty：体验只打四下——Rail + `Cmd+'`、Composer 写进 PTY、Dual Surface、状态可带走。

---

## 1. Problem

2026 年同一批人同时需要两件事：

1. 低延迟、协议完整、SSH / TUI 不撒谎的终端核。
2. 4–8 个 Claude Code / Codex / OpenCode / Grok Build 并行时，能看见谁在等自己，合盖后能续。

| 产品 | 做对的 | 缺口 |
|---|---|---|
| Ghostty | 核、性能、协议、libghostty | 应用不消费程序状态，不管并行注意力 |
| Otty | Composer / Queue / 徽章 / resume | 闭源、锁 macOS、状态绑在 App、信息架构仍是终端 tab |
| cmux | libghostty + 竖标签 + 通知环 | 默认仍是「终端加侧栏」 |
| Warp | 工作流集成 | 账号、云、block 模型，SSH 降级 |
| Ghostex | 工作区 + 浏览器 + IDE | 范围爆炸，热路径不干净 |

Hashimoto 在 2026-10-06 发布 OSC 7501 Program Status Protocol，让程序自己报 `idle` / `working` / `done` / `blocked` / `error`。libghostty 解析它，Ghostty 应用不拿它做界面。Sill 吃这条，做成轨和环。

---

## 2. Goals and non-goals

### 2.1 Goals

- G1：Mac / Linux 上，Raw 热路径与同期 Ghostty nightly 同量级。不宣称更快。
- G2：Workspace 开着测性能。Agent chrome 离开热路径。对 Otty / Warp 在 idle、按键、大输出上拉开。
- G3：`blocked` / awaiting → Composer 可输入，本机已解锁 P50 ≤ 2s。
- G4：同一会话 Raw 与 Transcript 共存。TUI 强制 Raw。字节流不重写。
- G5：`layout.toml` + 官方 CLI resume。卸掉 Sill UI，Ghostty 里能续。
- G6：中文输入、CJK 双宽、emoji ZWJ 在 Mac / Linux 均为 P0。
- G7：OSC 7501 及下表协议面完整。未知 OSC 忽略，不报错，不丢后续字节。

### 2.2 Non-goals

- 自研 VT / 第二套 parser
- 比 Ghostty 更快的营销主张
- Electron、用 WebView 画终端字符
- 把 stdout 重排成气泡 / block / DOM
- 嵌入浏览器或 IDE
- 自有模型、强制账号、默认上云、v1 支付
- Windows GUI
- tmux `-CC` 原生映射
- Otty 式 Details 面板 / skills 厨房水槽
- 毛玻璃、粒子、仪表盘刻度、科幻控制台
- 私有状态序列作为唯一路径
- 第一次启动就进主题工作室

---

## 3. Users

### Primary — Parallel Agent Operator

一周 ≥3 天同时开 4–8 个官方 CLI agent。痛：不知道谁在等、长 prompt 难改、合盖后找 session-id、fork 之后认不出、想看可读层但 debug 必须回 raw。

成功：8 个会话在左轨；被挡住的那个有环、有未读；`Cmd+'` 切过去，Composer 已能打；Raw 一键切回，nvim 和 agent TUI 不变形。

### Secondary

同一人下午跑 nvim / ssh / lazygit。用 Terminal Mode。核必须仍然正确。

### Not for

只要系统原生标签的人用 Ghostty。要内置模型和团队云盘的人用 Warp。要嵌入浏览器的人用 Ghostex。Windows 第一天对齐的人，v1 没有。

---

## 4. Jobs

1. 发现谁需要我，不等翻 8 个 tab。
2. 对着 agent 写完整一段：多行、撤销、排队，不跟 readline 打架。
3. 同一会话看两种东西：人读的 Transcript，程序读的 Raw PTY。
4. 把一条会话分叉，并在图上找得到（P1）。
5. 合盖后本机能续。不承诺像素级 scrollback。
6. 卸掉 Sill，用官方 CLI 在 Ghostty 里续跑。

冲突时按此序砍：注意力是导航 → PTY 诚实 → 热路径同档 → 状态可导出 → 界面克制 → 一张信息架构两套窗口后端。

---

## 5. Positioning

| 产品 | 不比 | 要赢 |
|---|---|---|
| Ghostty | 谁更像系统终端、谁 `cat` 更快 | 打开就能管并行 agent；状态协议被界面消费 |
| Otty | 谁功能清单更长 | 四下：注意力导航、Composer→PTY、Dual Surface、可带走；且 Mac+Linux |
| cmux | 谁标签更多 | 默认是 Surface，不是终端加侧栏 |
| Warp | 谁 AI 更内置 | 无账号、SSH 不降级 |
| Ghostex | v1 不做浏览器 / IDE | 范围小、热路径干净 |

中文品牌名就是 Sill。解释性文字可用「窗台」，产品名不译成「西尔」。

---

## 6. Primary journeys

### J1 打开后 30 秒

1. 启动。无账号。零默认网络。
2. 有 `~/.config/sill/last-layout.toml` 则恢复画布。否则 Home Canvas：主卡片 New Agent Session，次要 Plain Terminal。
3. Provider 按 PATH 检测：有什么列什么（Claude / Codex / Grok；其它走 Custom Command）。
4. 选目录（上次项目或 `~`）。
5. 主表面启动官方 CLI。左轨出现一行。
6. Composer 贴在该表面底部，焦点在 Composer。PTY 在跑，焦点分层。
7. `Cmd+N` / `Ctrl+N` 开第二个会话。

失败：provider 不在 PATH → 卡片内错误 + Install hint，不创建假会话。第一次启动不出现主题选择。

### J2 中断路径

程序发出 OSC 7501 `state=blocked`（或 hook 回退到 awaiting）：

- 轨行出现未读，环绕该表面（若可见）
- 表面不可见则系统通知（可关，默认仅窗口不可见时发）
- `Cmd+'` 跳到最老的未读 blocked
- 焦点落到 Composer

本机已解锁：环 / 通知 → 可输入，P50 ≤ 2s。`kind=permission|question|auth` 显示在轨行副文，不另开对话框。

### J3 Dual Surface

同一 `pane.id`：Raw 与 Transcript 可切。底层 PTY 始终在跑。进入 alt-screen / 全屏 TUI → 强制 Raw，并锁 Transcript。无结构化事件 → Transcript 显示 empty，不编造气泡。

### J4 离开

`sill export layout`。文档给出各家官方 `--resume` 模板。Ghostty 打开后能续，不依赖 Sill UI。

---

## 7. Information architecture

```
Window
├── Attention Rail          左，默认 220px；可折到 48px
├── Surface Stack
│     ├── Title strip       名、cwd、Raw/Transcript
│     ├── Surface body      Raw PTY | Transcript
│     └── Composer dock     贴底输入条，不是气泡
├── Side peek（P1）         Timeline / Graph，默认关
└── Palette
```

主导航是 Rail，不是系统 Tab。系统菜单只放 New、Close、Preferences、Toggle Terminal Mode。

| Screen | Purpose | Priority |
|---|---|---|
| Home Canvas | 无会话起点；主操作 New Agent | P0 |
| Agent Workspace | 轨 + 表面 + Composer | P0 |
| Raw view | libghostty 像素；TUI 强制 | P0 |
| Transcript view | 只读事件层 | P0 |
| Palette | 命令面板 | P0 |
| Import report | Ghostty 导入结果 | P0 |
| Terminal Mode | 藏轨与 Composer，PTY 全幅 | P1 |
| Composer float | 独立小窗 | P1 |
| History / Open Quickly | 本机 session resume | P1 |
| Session Graph | fork 树 | P1 |
| Timeline | OSC 133 跳转 | P1 |
| Settings | config 的薄镜像；含主题 | P1 |

每个可交互表面至少有 `default / loading / empty / error / disabled`。

---

## 8. View specs

### V1 Attention Rail — P0

每行一份 Pane：provider 标记（形状，不靠颜色独活）、标题、副行 `cwd basename` · `branch`、状态。

状态来自 OSC 7501，映射：

| OSC 7501 `state` | 轨上 | 环 |
|---|---|---|
| `working` | processing | 无 |
| `blocked` | awaiting；副文用 `kind` | 有 |
| `done` | 完成未读 | 无；未读点 |
| `idle` | idle | 无 |
| `error` | error | 无 |
| `clear` | 清掉该 `id` 记录 | 无 |

无 7501、无 hook：`unknown` + 进程是否存活。单击聚焦，双击重命名，`Cmd+1..9` 跳行，拖拽排序写入 layout。折叠后 awaiting 仍显示环。

### V2 Focus Ring — P0

只环绕 `blocked` 表面。环宽 2px。进入 120ms，离开 80ms。不循环闪烁。`working` 不环主表面。

### V3 Dual Surface — P0

| Mode | 显示 | 输入 |
|---|---|---|
| Raw | libghostty 像素 | 键鼠进 PTY；Composer 可同时在 |
| Transcript | 结构化事件 | 只读；输入走 Composer 或切回 Raw |

事件来源：OSC 7501、OSC 133、hook、`sill state`。正例：agent 自带 TUI 选单时是 Raw。反例：把 TUI 选项重画成按钮。禁止。

### V4 Composer + Queue — P0 / P1

P0：多行、撤销/重做、`Enter` 换行、`Cmd+Enter` 发送。发送 = bracketed paste 写入该 pane 的 PTY，然后清空草稿。焦点在 Composer 时 PTY 不抢普通字符；`Esc` 交回 PTY。

P1：Queue（`idle` 且 prompt 空再发）、Pin / Float、附图（agent 不收则明示）。

禁止云补全、改模型 API、「智能发送」。发送就是写 PTY。

### V5–V7

Session Graph（P1）：节点 = session-id，边 = fork。无 id 不进图。不支持 fork 则 disabled。

Timeline（P1）：OSC 133 `C/D` 块。无标记则 empty，不猜。

Palette（P0）：`Cmd+Shift+P`。New Agent、New Terminal、Toggle Raw/Transcript、Toggle Rail、Terminal Mode、Import Ghostty、Export Layout、Jump Unread。

---

## 9. Visual system

默认体验：现代、克制、拿来就能用。跟随系统明暗。第一次启动不进主题选择。

大胆只在结构：轨比传统侧栏清楚，awaiting 用环，Composer 是贴底输入条。chrome 安静。字：chrome 用系统无衬线；PTY 只用等宽（默认 JetBrains Mono 13）。

| Token | 默认 |
|---|---|
| 跟随系统 | 明 / 暗两套，启动即用 |
| Rail | 220px，可折 48px；行高 44px |
| Ring | 2px，仅 blocked |
| Composer | 最小 72px，贴底，无气泡 |
| Motion | 120ms ease-out；无空闲动画，无呼吸灯循环 |
| Blur / shader / 粒子 | 关闭 |
| Radius | 小，4–8px；不靠大圆角假装现代 |
| 对比 | 正文 ≥ 4.5:1 |

主题是 P1 产品面，不是新手路径。用户主题是 TOML，两层：`[chrome]` 与 `[terminal]`（fg/bg/cursor + 16 色）。v1 主题不能注入 shader、blur、自定义 draw callback。换主题不得让 NFR-P1 / P3 倒退。

首发包可以有 Void / Dayglass 两套，放在 Settings，不放在第一次启动。Mac / Linux 同一套 token 语言。窗口按钮可原生。

---

## 10. Functional requirements

### FR-001 libghostty 唯一核 — P0

禁止第二套 parser。`TERM=xterm-256color`，`COLORTERM=truecolor`，`TERM_PROGRAM=sill`。不支持的模式查询回 `4`。钉 libghostty commit，升级显式。

### FR-002 性能合同 — P0

见 §12。默认 bench 形态是 Workspace 打开。

### FR-003 Workspace chrome — P0

Mac：AppKit 窗口 + 自绘 Rail / Strip / Composer。Linux：同一 IA 的一条 chrome 后端。主导航禁止系统 Tab。视觉按 §9，不做成仪表盘。

### FR-004 Home + New Agent — P0

见 J1。Custom Command 可启任意二进制。无状态事件则只有 `unknown` + 进程存活。

### FR-005 Rail + Ring + Jump — P0

见 V1/V2。`Cmd+'` 循环未读 `blocked`。

### FR-006 Dual Surface — P0

见 V3。

### FR-007 Composer → PTY — P0

见 V4。控制字符粘贴走确认框。

### FR-008 程序状态协议 — P0

主源 OSC 7501。序列：`ESC ] 7501 ; key=value:key=value ST`。

| Key | 规则 |
|---|---|
| `state` | 必填：`idle` `working` `done` `blocked` `error` `clear` |
| `app` | 可选，稳定程序名 |
| `msg` | 可选，一行 base64 |
| `kind` | `blocked` 时：`permission` `question` `auth` |
| `id` | 可选，分层记录；`clear` 按 id 删 |

未知 OSC 忽略。不认识的 key 忽略，不丢 pane。SSH 与本地同一解析。

尚未发 7501 的 CLI：官方 hook 转成同一五点，经 `sill state` 写入。`sill state` 不是主协议。缺 `pid` 的适配器事件丢弃。适配器失败写 log，不阻塞 PTY。

### FR-009 终端协议面 — P0

| 用途 | 协议 | 验收 |
|---|---|---|
| 程序状态 | OSC 7501 | 五点映射到轨；`blocked` 出环 |
| 命令边界 | OSC 133 A/B/C/D | Timeline 与命令选择；无标记则 empty |
| 当前目录 | OSC 7 | 轨副行 cwd |
| 链接 | OSC 8 | 可点；远程默认确认 |
| 通知 | OSC 9 / 99 / 777 | 仅窗口不可见时系统通知；远程默认关 |
| 进度 | OSC 9;4 | 轨上细进度，不挡格子 |
| 键盘 | Kitty keyboard | nvim / agent TUI 修饰键正确 |
| 同步输出 | CSI ?2026 | 大块更新不撕裂 |
| 粘贴 | bracketed paste，CSI ?2004 | 默认开 |
| 焦点 | CSI ?1004 | focus in/out |
| 能力 | XTGETTCAP、Primary/Secondary DA | 查询有确定应答 |
| 图形 | Kitty graphics | 与 libghostty 同级；Sixel 不承诺 v1 |
| 剪贴板写 | OSC 52 | 默认关，opt-in |

不会的模式查询回 `4`。不实现 iTerm 私有图像当必须。

### FR-010 Adapter — P0

Claude / Codex / Grok：能装官方 hook 就装，不覆盖无关 key。Resume 走官方 CLI。Grok 目录未 trust → `unknown`，不崩。厂商改 CLI = 适配器修补，不改成 Sill runtime。

### FR-011 layout + 本机恢复 — P0

协议 / CLI / layout / token 文档 MIT。layout 含 pane 树、cwd、launch、agent、session、view_mode、rail_order、composer_pinned。启动读 last-layout。有 session 则官方 resume；失败则空表面 + error strip，保留 id。不承诺像素级 scrollback。UI 写明。

### FR-012 Ghostty import — P0

`sill import ghostty`：字体、颜色、padding、cursor、能映射的 keybind。报告 mapped / similar / dropped。未知 key 忽略。

### FR-013 安全默认 — P0

Bracketed paste on。OSC 52 off。远程 OSC 通知 off。无默认网络。无账号。

### FR-014 CJK / IME — P0

候选框跟随当前焦点（Composer 或 PTY caret）。全角 2 cell。Appendix B 全过。

### FR-015 Palette — P0

### FR-016 Queue / Float / History / Graph / Timeline / Terminal Mode / 通知 — P1

Terminal Mode 藏轨和 Composer。后台 agent 仍可用 `Cmd+'`。通知默认仅窗口不可见时发。

### FR-017 Linux — P0 功能 / P1 像素

Workspace 全套可运行。token 一致，允许装饰 80%。不做第二套 raw Wayland IA。

### FR-018 CLI — P0

`sill`、`sill import`、`sill export`、`sill state`、`sill bench`。

### FR-019 主题包 — P1

TOML 两层。不进首次启动。不能注入绘制回调。

---

## 11. Errors

| Input | Behavior |
|---|---|
| libghostty 加载失败 | 退出码 1，原生错误框 |
| provider 不在 PATH | Home 卡片 error，不创建 pane |
| 无 7501 且无 hook | `unknown`，不猜标题 |
| 7501 缺 `state` | 丢弃该条 |
| `msg` base64 坏 | 忽略 msg，保留 state |
| Transcript 无事件 | empty，建议切 Raw |
| alt-screen | 强制 Raw，toggle disabled |
| hook 写失败 | `unknown` + Settings 一行原因 |
| resume 失败 | 空 Raw + error strip + Retry，保留 session-id |
| Composer 发送时 TUI 占输入 | 切 Raw 或拒绝并提示 |
| 粘贴含 ESC | 确认；取消则不写入 |
| 未知 OSC | 忽略 |

---

## 12. Non-functional

热路径对标 Ghostty 同量级。Chrome 有硬顶。

| ID | Scope | Budget |
|---|---|---|
| NFR-P1 | Key-to-photon Raw，焦点在 PTY | P50 ≤ 5ms @120Hz |
| NFR-P2 | 同上 P95 | ≤ 12ms |
| NFR-P3 | `cat` 150MB ASCII，Workspace 开着 | 与同期 Ghostty nightly 同量级 |
| NFR-P4 | Idle CPU，1 表面 + Rail + 空闲 Composer | 5s 后 ≤ 2% |
| NFR-P5 | Idle RAM 同上 | macOS ≤ 90MB；Linux ≤ 120MB |
| NFR-P6 | 8 会话，7 个遮挡 | 遮挡释放 GPU 三缓冲；RAM 不按 8× 可见计 |
| NFR-P7 | Cold start 到 Home Canvas | macOS < 200ms；Linux < 400ms |
| NFR-P8 | Terminal Mode vs Workspace | Raw 延迟差 ≤ 10%；`cat` 差 ≤ 5% |
| NFR-P9 | 状态解析 | 不进 render thread；刷新 ≥ 250ms |
| NFR-P10 | blocked → Composer 可输入 | P50 ≤ 2s（本机已解锁） |
| NFR-S1 | 粘贴控制字符 | 确认 |
| NFR-S2 | 默认零网络 | 是。更新检查 opt-in |
| NFR-I18N | UI English；文档 EN + ZH；CJK P0 | |
| NFR-A11Y | 轨行名可被读屏读出 | |
| NFR-LIC | 协议 / CLI / layout / token MIT | UI 许可证见开放问题 |

CI：无 Workspace 形态 bench 表，不得打 stable tag。

---

## 13. Data

本地 only。不存 API key、云用户、PTY 全量字节。

| Entity | Field | Notes |
|---|---|---|
| Pane | view_mode | `raw` / `transcript`；TUI 可强制 raw |
| Pane | status | 来自 7501 或适配器 |
| Pane | unread | `blocked` 或 `done` 未聚焦 |
| Pane | composer_draft | ≤ 200KB |
| StatusRecord | id / app / state / kind / msg | 7501；`clear` 删除 |
| Layout | rail_order / focused / terminal_mode | version = 1 |
| Config | clipboard-write | `off` / `confirm` / `allow`，默认 off |
| Config | notify-remote | 默认 false |
| Config | theme | 默认 system；包为 P1 |

---

## 14. Architecture

```
Workspace chrome（Rail / Ring / Composer）
        │ layout.toml + OSC 7501 / 133 / hooks
Surface Manager（macOS AppKit · Linux 一条 chrome）
        │ C ABI
libghostty（parse · grid · encode · render）
        │ posix PTY
shell / 官方 agent CLI / ssh
```

唯一 VT：libghostty。Composer / Rail 禁止 WebView。Adapter 失败不阻塞 PTY。macOS 14+。Linux 以 Wayland 为准。Windows：核 ABI 预留，GUI 不做。

---

## 15. Metrics

v1 默认无遥测。数用本地 log。

| Metric | Target（内部 4 周） |
|---|---|
| 第一次有效动作是 New Agent | ≥ 70% |
| blocked → Composer 输入 | P50 ≤ 2s |
| Export 后官方 CLI resume | 抽测 10 个 ≥ 8 |
| 有 TUI 的会话用过 Raw 锁 | 周活 ≥ 40% |
| Terminal Mode 周使用 | 允许 20–50% |

---

## 16. Risks

| Risk | Mitigation |
|---|---|
| 做成带侧栏的 cmux | Dual Surface + Composer + 导出必须进演示 |
| 界面做成仪表盘 | §9 锁死；第一次启动只有 New Agent |
| 自造状态方言 | 7501 是主源；`sill state` 只是回退 |
| 7501 字段以后变 | 未知 key 忽略；钉已发布字段 |
| chrome 打爆 idle | 禁 blur；遮挡停绘制；超标先减装饰 |
| Transcript 诱惑重画 TUI | 无事件 = empty；TUI = 强制 Raw |
| 宣传比 Ghostty 快 | 发布说明并列 Ghostty 对照列 |
| 恢复被当成像素级 | 第一屏写清 resume ≠ scrollback |

---

## 17. Scope and phases

v1：§10 全部 P0，加上 P1 的 Queue、History、Graph、Timeline、Terminal Mode、通知、主题包。Mac 与 Linux Workspace。

以后：Windows 独立 apprt；Sync（唯一以后可收费的点，离线功能集不变）；更多 adapter；第三方实现 7501 消费端。

| Phase | Weeks | Ships | Exit |
|---|---|---|---|
| A | 0–6 | 核 + Raw + Home + New Session + 静态轨 | Mac nvim / SSH / IME 正确；NFR-P1 / P3 绿 |
| B | 6–10 | OSC 7501 消费、Ring、`Cmd+'`、hook 回退 | 4 agent 并行，blocked 不漏 |
| C | 10–14 | Composer、Dual Surface、layout、import | J1 可演示 |
| D | 8–16 并行 | Linux 同一 IA | 功能平 |
| E | 16–22 | Queue、History、Graph、Timeline、Terminal Mode、主题包 | RC |
| F | 全程 | Workspace bench 进 CI | 无表不打 tag |

Phase A 只准从这六刀开工：嵌入 libghostty、Rail、7501 + Ring + `Cmd+'`、Composer→PTY、Dual Surface、layout + 官方 resume。能演示 J1 / J2 再谈 Graph。

---

## 18. Open questions

- 正式名 Sill，已锁定。中文不译。
- UI 许可证。建议协议 + CLI + token MIT；App 源码可用；v1 不许登录墙。
- Linux chrome：GTK custom 或自绘 GPU layer。验收看 token 与 NFR。
- 默认 provider 顺序：检测 PATH，有什么列什么。

未列出的按本文默认执行。不再重开北极星。

---

## 19. Changelog

| Version | What changed |
|---|---|
| v0.1–v0.2 | 从可拆工作台改成 Agent Surface |
| v0.3 | 产品名 Sill；北极星锁为核同档、体验打 Otty |
| v0.4 | 界面改回苹果式简洁，大胆只留结构；OSC 7501 成为轨/环主源；协议面列为 P0；主题包降到 P1，不进首次启动 |

---

## 20. How to use

实现以本文为准。不在本文的功能，v1 不做。交给 Coding Agent 时一次只做当前 Phase。禁止加浏览器、云、block UI、自研 VT、私有状态方言。

---

## Appendix A — Bench

`sill bench --suite=v1` 默认 Workspace 开着。最小 suite：`key_to_photon`、`cat_ascii_150mb`、`idle_cpu`、`idle_rss`、`occluded_rss`。发布说明含 CPU / GPU / OS / 对照 Ghostty 版本 / 120×40 cell。

## Appendix B — CJK

`中文列对齐测试１２３`、`👨‍💻`、`が゚`、nvim `set list` 下中英混排。任一条残字或错宽 = P0。

## Appendix C — 7501 最小例

```text
ESC ] 7501 ; state=working:app=claude-code ST
ESC ] 7501 ; state=blocked:kind=permission:app=claude-code ST
ESC ] 7501 ; state=done:app=claude-code ST
ESC ] 7501 ; state=clear:id=1 ST
```

hook 回退例：

```text
sill state agent=claude status=awaiting pid=41220 session=sess_01
```
