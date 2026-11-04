# Desktop Buddy 研究控制台

这是与现有宠物同时运行的研究工具，不是两个应用合并。无需 Python 依赖或云账号。需要本机 Xcode/Swift 和 Python 3。

## 启动

在 Finder 双击本目录 `run.command`，或在仓库根目录运行：

```sh
./tools/research/run.command
```

首次编译需要稍等。勾选同意前不采集；选择计划场景后点击开始。控制台打开不代表已经开始记录。

## 第一段试验

1. 开始一段 3–5 分钟的编码或浏览任务。
2. 在预定时点回到控制台设置等待时间并点击“预约一个测试候选”，然后立即切回任务；不会发出真实通知。
3. 过一会回到控制台，为候选当时的活动、即时提醒偏好、实用性和最长容忍延迟作标注。标注的是候选时刻，不是点击保存时刻。
4. 最后一个候选后继续至少 120 秒再停止；短录制也能评估，但未完成的送达观察会单独计数。
5. 点击查看记录，找到 `research-data/session-<UUID>.jsonl`。

候选使用固定内容：普通为可选休息建议，紧急为模拟电池即将耗尽（不是设备真实告警）。内容和优先级保存到记录；标注时显示该候选原始内容。支持 5/30/60/180 秒预约；默认 30 秒。无法回忆时点击跳过，不强行填写标签。

## 回放

```sh
python3 tools/research/evaluate.py research-data/session-实际UUID.jsonl --output research-data/report.json --html research-data/report.html
python3 -m unittest discover -s tools/research -p 'test_*.py' -v
```

A 是静态立即策略；B 增加即时上下文；C 再增加历史。它们共用紧急覆盖和普通 120 秒期限。输出中的 delivery 是模拟送达，不是真实弹窗。空值不等于零。报告也含用户活动标签，按实验数据对待，默认在被 git 忽略的 research-data 中。

## 当前边界

- 没有可靠的视频识别，活动推断统一 unknown；不把 coding 或 browsing 仅由 app 名认定。
- 没有采集截图、窗口标题、输入内容，也没有外发上下文。
- 研究控制台本身的前台样本不作任务活动解释。
- 系统权限/多显示器/空间切换还需要实机验证；全屏是几何启发式。
- 记录保存相对时间；原始 app ID 只在内存用于粗类别和观测切换。
- 自动清理仅针对 UUID 格式的 session 文件，在下次开始采集时移除修改时间超过 7 天的记录；手工生成的报告需自己删除。不要把这里作为长期敏感数据存档。
- 点击删除本次记录会直接删除该文件。导出的副本与报告不受该按钮影响。

详见 `docs/research/05_IMPLEMENTATION_PLAN.md`。

最终申请文档与结果报告使用英文，日常使用说明和沟通使用中文。英文实验协议见 `docs/research/04_EXPERIMENT_PROTOCOL.md`；研究定位见 `docs/research/02_RESEARCH_QUESTION.md`。

## 一键查看最近一段结果

录制并停止后，双击本目录 `analyze.command`。脚本选择最近修改的完整会话，生成英文 JSON/HTML 报告并打开 HTML。仍在录制、缺少结束事件或损坏的文件不会被选中；没有候选或标签时会提示。报告不是实际送达效果。
