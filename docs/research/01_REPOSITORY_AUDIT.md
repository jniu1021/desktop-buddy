# Desktop Buddy × 活动感知：仓库审计与研究计划

审计日期：2026-10-16（用户时区）。阶段：Phase 0，仅文档，不修改应用行为。

## 1. 范围和证据边界

主应用位于 `DesktopBuddy/`；另有独立的风扇控制实验副本，本阶段不作为研究基座。已盘点主应用源码、测试、项目配置和工程文档，并重点阅读上下文采集、决策、调度、通知和指标链路。IMPLEMENTED 表示源码存在且可追踪到调用，不等于本次运行验证通过。本次未构建、未运行测试、未采集实验数据，也未实测各 macOS 权限状态。

开始审计时已有未提交修改：`DesktopBuddy/Platform/macOS/CodexIntegration/CodexAppServerAllowanceSensor.swift` 和 `DesktopBuddy/Tests/CoreTests/CodexAllowanceTests.swift`，本阶段保留原样。

## 2. 当前架构

- 入口：`DesktopBuddy/App/DesktopBuddyApp.swift:4`，SwiftUI App 通过 AppDelegate 启动协调器。
- 装配：`DesktopBuddy/App/DependencyContainer.swift:4`，以协议注入设备传感器、前台活动、全屏、网络、偏好、诊断和指标持久化。
- 编排：`DesktopBuddy/App/AppCoordinator.swift` 管理 Combine 订阅、Task、环境事件和通知投递。
- 状态：`App/BuddyStateStore.swift` 管理设备状态与偏好；`App/FocusActivityStore.swift` 封装纯逻辑 FocusActivityTracker。
- UI：`Features/MenuBarPet/` 负责菜单栏渲染和动画；`Features/EdgePet/` 负责 AppKit 窗口及气泡；`Features/StatusPanel/StatusPanelView.swift` 是 SwiftUI 状态面板。
- 规则：`Core/DecisionEngine/` 包括设备通知、通知资格、全屏、专注、设备轮询、恢复与退避策略。
- 持久化：`Platform/macOS/Persistence/` 使用 UserDefaults；诊断通过 OSLog；不是已有的研究事件数据库。

以下路径若未以 DesktopBuddy 开头，均相对 `DesktopBuddy/`。

## 3. 功能清单

| 功能 | 分类 | 源码证据与限制 |
| --- | --- | --- |
| 前台应用身份 | IMPLEMENTED | `Platform/macOS/Activity/SystemForegroundActivitySensor.swift:5` 获取 bundle ID；`App/AppCoordinator.swift:434` 更新快照；受 applicationActivityEnabled 控制 |
| 应用切换 | IMPLEMENTED | `App/AppCoordinator.swift:274` 订阅 didActivateApplicationNotification；`Core/DecisionEngine/FocusActivityTracker.swift:68` 保存短期切换时间 |
| 输入空闲时间 | IMPLEMENTED | `SystemForegroundActivitySensor.swift:13` 用 CGEventSource 读取距上次输入时间，返回可空值；不读取输入内容；无输入不代表离席 |
| 窗口元数据 | PARTIALLY IMPLEMENTED | `Platform/macOS/Activity/ForegroundFullscreenSensor.swift:5` 读取窗口 PID、图层和几何；未发现窗口标题或浏览器 URL 的专用读取链路 |
| 全屏状态 | PARTIALLY IMPLEMENTED | 同上及 `Core/DecisionEngine/FullscreenPresentationPolicy.swift:18`；以窗口填满宠物所在显示器、4 点容差进行几何判断，不是语义全屏或视频检测；读取失败返回 false，缺少 unknown |
| 专注通知决策 | IMPLEMENTED | `FocusActivityTracker.swift:82`、`NoticeEligibility.swift:39`、`AppCoordinator.swift:205`；类别白名单、5 分钟历史、45 秒内输入、至少 8 个活跃样本、窗口内最多 2 次切换；是启发式“可能专注” |
| 视频播放检测 | NOT IMPLEMENTED | 未发现可靠的播放器状态、媒体会话或播放事件采集；浏览器、全屏、低输入均不足以证实视频播放 |
| 带时间的本地事件 | PARTIALLY IMPLEMENTED | `Platform/macOS/OSLogDiagnosticRecorder.swift:10` 记录生命周期和故障；通知有 createdAt/expiresAt；缺少可回放的连续研究特征与标签轨迹 |
| 活动四分类及 unknown | NOT IMPLEMENTED | 目前输出专注布尔值，不是 watching_video/coding/browsing/idle_or_away 分类 |
| 实验日志、标签及离线回放 | NOT IMPLEMENTED | AlphaMetrics 是累计产品计数，不是逐候选事件的政策、标签和投递结果 |
| 当前机器运行与权限兼容性 | UNKNOWN / NOT VERIFIED | 需要后续构建、实机操作和权限组合检查 |

注意：`NoticeEvidence.confidence` 是现有通知规则赋值，例如内存告警固定 0.90；不能作为活动识别的校准概率。

## 4. 调度、通知与诊断

- `App/AppCoordinator.swift:420`：同意活动采集后约每 10 秒采样；切换另走系统事件。关闭后取消任务并清空专注历史。
- `App/AppCoordinator.swift:439`、`FullscreenPresentationPolicy.swift:3`：全屏约每 15 秒检查，应用/Space 切换后另有 400ms 去抖刷新。
- `Core/DecisionEngine/DevicePollingPolicy.swift:8`：外接电源/电池/低电量模式对应设备刷新 60/90/120 秒，内存采样 10/20/30 秒。
- `App/AppCoordinator.swift:295` 起监听休眠唤醒；保留生命周期和功耗策略。
- `Core/DecisionEngine/DeviceNoticeEngine.swift:56`：电池、内存阈值变化产生通知；队列按类型去重，最多 3 条，30 分钟过期。
- `AppCoordinator.swift:205`：先入待办，再判断资格和气泡展示。严重电池通知跳过普通资格，但仍受到全屏/专注展示限制。未见到期强制送达机制；不能把“存在待办列表”解释成“保证及时送达”。
- `Features/StatusPanel/AlphaMetricsTracker.swift`：记录展示、关闭、操作、查看和会话累计值；关闭不等于“不受欢迎”，操作不等于“有用”。
- `Tests/CoreTests/` 有专注、通知、传感器、全屏、退避、功耗等 XCTest；传感器测试不能替代真实系统权限和使用场景验证。
- `docs/performance-baseline.md` 包含历史短时性能记录，不是本次测量，也不能直接作为新增模块开销。
- `docs/direction-update.md` 包含历史问题及后续修订，应以当前源码为准，例如 NoticeEligibility 当前已接入协调器。

## 5. 架构适配与隐私

建议沿用协议注入、纯规则和独立状态存储：现有传感器 → 新的可空上下文快照 → 活动估计 → 中断政策 → 实验记录器。不要把四层全部塞进 AppCoordinator，不替换原有通知路径。第一版在影子模式评估，不影响真实提醒。

复用 ForegroundActivitySensing、FocusActivityTracker 的历史思路、通知类别、偏好开关及生命周期。补充传感器可用性、单调时间/相对时间、政策原因码和政策版本；全屏缺失应与 false 区分。共享一份特征历史，避免重复采样。

默认不新增截图、音频、键盘内容、标题、URL、Accessibility 或 Screen Recording 权限请求。现有窗口枚举只消费 PID/图层/边界；各系统版本及权限拒绝时的实际返回需要实测，不承诺所有状态都可用。现有 Codex 集成有外部服务链路，因此“研究上下文本地处理”不能写成“整个应用永不联网”。

实验日志另行 opt-in，开关独立于现有产品累计指标；优先保存粗类别、时间桶、状态可用性和理由，不保存原始 bundle ID。场景、采样模式仍可能泄露行为，应说明用途。建议试验结束后 7 天自动删除，支持立即清除和手动导出；这是待实现设计，不是现有保证。

## 6. 与 Sei Backseat 的关系

本地存在 `../Sei Backseat/backseat/README.md`、完整 `sei/`，以及 `sei/docs/backseat-activity-mvp.md` 所述的 opt-in 视频采样原型。可借鉴事件触发、保守回退、时序上下文、成本与评论质量分开评估的实验方法。不合并 Electron 和 Swift 应用，不引入屏幕采集管线。Backseat README 声明 AGPL-3.0-or-later；本阶段不复制代码。现有原型和自述不构成通用活动识别有效性的证据。

## 7. HiLab 契合度

官网把日常交互转为上下文信号、个性化自适应系统列为方向。这里可提出“有限观测下的上下文估计和用户可接受的中断时机”，而非仅展示宠物外观。此为基于研究方向的匹配判断，不代表导师认可或已确认学术新颖性。

Invisibility Cloak 使用手表惯性信号指导边缘摄像系统遮蔽个人视觉信息；与本项目共享隐私和本地处理原则，但机制、任务和评价目标不同。本项目不复现其贡献，不引用其识别准确率作为预期效果。尚需补充经典中断管理、任务边界和个性化可打断性文献再界定新贡献。

来源（访问于 2026-10-16，用户时区）：
- https://hilab.dev/#publications
- https://hilab.dev/#faq （FAQ 以实际页面标题定位）
- https://hilab-open-source.github.io/InvisibilityCloak/

## 8. 最小可行实验

研究问题：在相同通知候选事件上，短期时间历史相比静态政策和即时上下文，是否改善用户期望的一致性，同时控制延迟、漏送和开销？

A：只用通知优先级、用户显式偏好和固定冷却；B：在 A 上加入当前粗应用类别、输入空闲、可用的全屏信息，不使用派生历史；C：在 B 上加入切换次数、当前上下文持续时间、活跃/空闲转移、状态稳定性。现有产品专注策略本来就有历史，作为第四项参照或代码复用来源，不称为 A。各组使用相同候选事件、优先级、期限和硬性保护，B/C 不得偷用现有历史专注标志造成基线污染。

先做单人可行性：视频、写/调代码、浏览、离席、快速切换、模糊转换六类，每类 2 段、每段约 5 分钟。场景顺序随机，预设同一组模拟通知候选，覆盖普通和紧急优先级。活动按阶段标注并记录实际偏离脚本；对每个候选独立标注是否希望现在收到、是否有用、最长可接受延迟。标签记录时点本身可能造成打扰，应留存该限制并优先使用段后时间线复核。

先采集一份同意后的特征轨迹和标签，A/B/C 在相同轨迹与候选事件上离线运行。调规则与评估使用不同录制片段；不把相关的每秒样本视作独立参与者。四类语义活动允许大量 unknown，尤其看视频/离席无法区分时；不要为了提高覆盖率强行猜测。第一轮优先评估政策，不以四分类全部成功为前提。

离线对照只能验证决策一致性和模拟延迟，不能证明真实打断改善；之后再设计顺序平衡的实时条件比较。设置最大延迟和重评估、到期强制处理/明确失败记录；紧急提醒不得无限等待。

指标定义：
- 活动准确率：正确预测/全部有活动标签的有效样本，unknown 按未识别处理；另报非 unknown 条件准确率、unknown/全部有效样本、逐类 P/R 及包含 unknown 列的混淆矩阵。
- 不受欢迎中断率：用户标为此刻不希望收到的即时投递/全部即时投递；另报相对全部不希望即时收到候选的误投率。
- 漏掉有用通知率：超过用户容忍期限仍未送达的有用候选/全部标为有用的候选。
- 决策一致性：政策输出与明确决策标签相符的候选/有可比较标签的候选；“不想现在收到”不能自动等于永久 suppress。
- 延迟：候选到投递的时间分布，报告中位数、P95、期限内送达率；未投递单独计数，不以删除这些样本美化延迟。
- 性能：采集耗时与政策耗时分别测量；同机器同构建同场景测当前版与实验开关开启，比较 CPU 时间/墙钟时间、内存、唤醒及采样次数。10 秒采样间隔带来的观测滞后与函数执行时间分开。
- 隐私：列出实际保存字段、截图/标题是否采集、外发路径、保存期限及删除验证。

上述都是实验设计和假设，没有测量结果或广泛适用的结论。

## 9. 按优先级推进

1. Phase 0（本阶段）：完成审计、研究范围和基线设计；不改应用代码。
2. 批准 Phase 1 后：先构建/测试现状，检查现有修改；加入可选的统一上下文快照、缺失状态、最小日志与删除功能，保持影子模式，验证开关/休眠/权限失败。
3. Phase 2：透明启发式估计及 unknown；单元测试关键冲突、缺失和边界，不声称概率校准。
4. Phase 3：纯函数 A/B/C、统一候选和离线回放；验证截止期限与未投递计数；先跑单人试验。
5. Phase 4：同机器性能对照、隐私核对，必要时进一步实时用户评价。
6. Phase 5：准备短演示、架构、方法、真实结果及限制；申请材料明确本人代码、上游项目和未实现部分。
7. 可选 Phase 6：仅当 OS 特征的失败模式被测量证明，且新传感器能补充所缺信息时提出硬件对照，不因申请 lab 提前添加 ESP32。

后续文档：02_RESEARCH_QUESTION.md、03_SYSTEM_DESIGN.md、04_EXPERIMENT_PROTOCOL.md、05_IMPLEMENTATION_PLAN.md；06_RESULTS.md 仅在实际测试后填写；07_HILAB_RESEARCH_SUMMARY.md 区分已完成与计划。

## 10. 待用户补充

- 申请身份、时间线以及可投入时间，决定研究范围和材料形式。
- 是否有第二位或更多自愿参与者；当前先按单人可行性设计。
- 可接受的提醒种类和紧急提醒期限，决定候选事件与最大延迟。
- 隐私边界是否接受只在内存读取 app ID、仅保存粗类别；阶段一是否允许进行真实实验记录。

这些不阻塞 Phase 0；按用户提供的任务说明，开始 Phase 1 前等待批准。
