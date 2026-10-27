# 拾光拼图 · 花园午后

一个轻松、明亮的 **Godot 4.x / 2D / 3×3 记忆拼图**。完整画面只展示 5 秒，随后打乱位置与朝向；凭记忆交换、旋转，还原一个花园午后。

## 运行

1. 使用 Godot 4.x 标准版（推荐 **4.3 或更新版本**；已在 **4.7.2** 验证）。
2. 在 Godot 项目管理器导入 `project.godot`，按 **F6**（主场景打开时）或 **F5** 运行。
3. 或命令行：`godot --path .`

无插件、无网络服务、无运行时下载；插画与中文字体已随项目打包。面向桌面鼠标，窗口可缩放，默认 1280×900，最小 720×640。

## 玩法

- **观察 5 秒**：倒计时结束后自动打乱九块拼图的位置和 0 / 90 / 180 / 270° 朝向。
- **左键**：选中一块，拼块随鼠标悬浮；点击原位放下，点击另一格交换并放下。点击棋盘外不改变选中状态。
- **右键**：将选中拼块顺时针旋转 90°；未选中时不做任何操作。
- **完成条件**：所有拼块的**位置和朝向**都正确，并已放下最后一块。
- **操作数**：只计算实际交换和旋转；选中、原位放下不计数。
- **用时**：打乱动画结束后开始，完成时停止。
- **重新记忆**：重新观察 5 秒，挑战相同的洗牌开局。
- **换个开局**：重新观察 5 秒，生成新的随机开局（同一幅原创插画）。

观察、打乱、完成阶段禁止操作拼块；动画中暂时锁定点击，避免重复交换。重开会取消旧动画与选中状态，清零用时和计数。没有常驻答案缩略图、编号或正确位置提示。

## 项目结构

```text
main.tscn                  主场景
scripts/main.gd            响应式 UI、阶段、输入、动画与计时
scripts/puzzle_state.gd    独立可测试的状态模型
scripts/puzzle_piece.gd    拼块绘制与悬浮反馈
assets/garden.svg          原创连续花园矢量插画
assets/AtelierSans.otf     随游戏精简打包的中文字体
```

## 测试

```sh
godot --headless --path . --editor --import --quit
godot --headless --path . --script res://tests/state_test.gd
godot --headless --path . --script res://tests/ui_test.gd
```

详细覆盖见 [`tests/README.md`](tests/README.md)。可选的实际渲染截图工具（需要现有桌面显示会话）：

```sh
mkdir -p qa
godot --path . --script res://tests/visual_capture.gd
```

截图保存在 `qa/`，不包含在版本控制中。截图工具使用实际控制器与动画完成交换、旋转和求解；完整行为另由控制器测试验证。

## 素材

- `assets/garden.svg` 为本项目原创矢量插画《花园小憩》，全部图形本地绘制，无第三方图片依赖。
- `assets/icon.svg` 为本项目原创图标。
- `assets/AtelierSans.otf` 为 Noto Sans CJK SC 的精简子集，遵循 SIL Open Font License 1.1，见 [`assets/FONT-LICENSE.txt`](assets/FONT-LICENSE.txt)。
