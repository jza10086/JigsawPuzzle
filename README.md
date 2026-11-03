# 拾光拼图 · 花园午后

一个 **Godot 4.x / 3D / 1–8 人在线记忆拼图比赛**。大九宫格的外围八格分配给八个玩家，每格各有九块拼图；中央九块组成完整答案。人数不足八人时保留空位，不生成 AI。

相机正对整个棋盘，不再斜向旋转。滚轮缩近时平滑移向自己的区域，并从 52° 逐渐转为 88° 俯视；缩远回到全局。所有客户端都能看到彼此的拼块位置、朝向、选中状态和完成成绩。

## 运行

本目录是内容子仓，没有独立的正式 `project.godot`。局部场景入口为 `main.tscn`，不依赖框架服务，直接运行时只有一个本机参与者。`party_round.tscn/gd` 是包内多人入口，使用现有 PartyAPI 取得名单、房间规则和消息通道。本次只改动和验证子仓，未做主工程大厅到最终结算的完整接入验收。

本次本机预览工程位于 `tmp/test/3d_preview/`（不提交、不随内容包发布）。在子仓目录运行：

```powershell
godot --path tmp/test/3d_preview --log-file "$PWD/tmp/test/preview.log"
```

预览工程使用本包的场景、脚本、settings.gd 和素材副本，没有复制框架代码；修改后需更新对应副本。使用系统 PATH 的 `godot`，本次版本为 4.7.2。画面铺满窗口，右下角只显示操作说明；轮次、倒计时和积分显示在棋盘的 3D 标牌上。

## 玩法

- **每轮准备 5 秒**：中央显示答案，外围已打乱，不能操作。同轮所有玩家使用相同开局，不同轮使用新开局。
- **左键**：选中一块，拼块随鼠标悬浮；点击原位放下，点击另一格交换并放下。点击棋盘外不改变选中状态。
- **右键**：将自己的选中拼块沿桌面顺时针旋转 90°；未选中时不做任何操作。
- **滚轮**：缩近自己的棋盘并逐渐俯视，缩远查看全局。玩家不能操作别人的区域；观战者可以缩放中央视角。
- **完成条件**：所有拼块的**位置和朝向**都正确，并已放下最后一块。
- **首位完成时限**：默认 120 秒，从准备结束开始计时。时限内无人完成则本轮全员并列，各得 1 分。
- **首位完成后**：公开中央答案，进入完整的 30 秒结算倒计时，即使因此超过原来的两分钟也不会判平局。所有仍在线玩家都完成时可提前结算。
- **每轮排名**：按主机确认的完成耗时升序；同毫秒完成并列，采用竞赛名次（例如 1、2、2、4）。倒计时结束仍未完成者并列最后一名。
- **每轮积分**：N 人局第 r 名得 N+1-r 分；八人局为 8–1 分。未完成者得 1 分；无人完成的超时平局每人只得 1 分。
- **连续小回合**：默认三轮，轮间展示答案和成绩 6 秒，再准备下一轮。最后按累计分降序排名，同分并列；最终成绩保留展示 6 秒后交回父游戏。

比赛阶段中央答案隐藏；准备、结算倒计时、轮间结算和总分结算阶段显示答案。单人版 R/N 重开已移除，避免在线比赛中单独重置。断线者标记退出，当前及后续轮不加分，最终 rank=0；不重连、不转交主机。

房间规则在 `settings.gd` 声明：`duration=120`、`closing_duration=30`、`rounds=3`。时限边界不接受新完成：正好第 120 秒仍无人完成时先判超时；第 119.999 秒完成则得到完整 30 秒窗口。

## 项目结构

```text
main.tscn                  局部玩法场景
party_round.gd/tscn        包内 PartyAPI 多人入口、身份映射和结果提交
scripts/main.gd            大九宫格、相机缩放、状态视图和主机时钟
scripts/match_state.gd     小回合、时限、权威操作、排名和累计分
scripts/puzzle_state.gd    独立可测试的状态模型
scripts/puzzle_piece.gd    立体拼块、九分区贴图与选中材质
assets/garden.svg          原创连续花园矢量插画
assets/AtelierSans.otf     随游戏精简打包的中文字体
```

## 局部验证

测试脚本、隔离工程、日志、截图及缓存只放在本子仓 `tmp/test/`，由 `tmp/.gdignore` 排除正式工程扫描。

本机当前检查：

- `check_match.gd`：实际逻辑操作求解、截止边界、平局、并列末名、三轮总分、断线、旧轮/重复消息和快照校验。
- `check_network.gd`：一个观战主机与八个真实 ENet 客户端；只替换 PartyNet 传输边界，执行生产游戏的身份检查、操作处理、快照校验和显示更新，覆盖对方进度、首位完成、公开答案与断线。
- `capture_match.gd`：八区准备/比赛/结算视图、缩放近景，以及三档缩放的九格点击投影。

旧单人版 `check_3d.gd/capture_3d.gd` 不再是当前验收入口。

```powershell
godot --headless --path tmp/test/3d_preview --script res://check_match.gd --log-file "$PWD/tmp/test/check_match.log"
godot --headless --path tmp/test/3d_preview --script res://check_network.gd --log-file "$PWD/tmp/test/check_network.log"
godot --path tmp/test/3d_preview --script res://capture_match.gd --log-file "$PWD/tmp/test/capture_match.log"
```

上述规则和网络检查断言通过，实际渲染已检查；运行环境仍报告证书库读取与 user:// shader 缓存写入错误，不能称为无错误运行。人工八人操作、跨机器/外网联机、完整框架准备和结算流程仍未验收。

## 素材

- `assets/garden.svg` 为本项目原创矢量插画《花园小憩》，全部图形本地绘制，无第三方图片依赖。
- `assets/icon.svg` 为本项目原创图标。
- `assets/AtelierSans.otf` 为 Noto Sans CJK SC 的精简子集，遵循 SIL Open Font License 1.1，见 [`assets/FONT-LICENSE.txt`](assets/FONT-LICENSE.txt)。
