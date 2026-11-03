# 拾光拼图 · 花园午后

一个轻松、明亮的 **Godot 4.x / 3D / 3×3 记忆拼图**。完整画面只展示 5 秒，随后打乱位置与朝向；凭记忆交换、旋转，还原一个花园午后。

固定斜俯视相机看向立体木质棋盘。九块拼图使用有厚度的网格、分区纹理、光照和投影；选中时抬起，交换时先平移再落下。鼠标通过相机投影到棋盘平面选格，抬起的拼块不会遮挡目标格的点击。

## 运行

本目录是内容子仓，没有独立的正式 `project.godot`。局部场景入口为 `main.tscn`，不依赖框架服务；已有的 `party_round.tscn` 保留为框架包装入口。本次 3D 改动只在子仓内开发和验证，未做大厅、协议或结算的完整接入验收。

本次本机预览工程位于 `tmp/test/3d_preview/`（不提交、不随内容包发布）。在子仓目录运行：

```powershell
godot --path tmp/test/3d_preview --log-file "$PWD/tmp/test/preview.log"
```

预览工程使用本包的场景、脚本和素材副本，没有复制框架代码；修改后需更新对应副本。使用系统 PATH 的 `godot`，本次版本为 4.7.2。UI 按 1920×1080 设计，窄窗口改为上下布局。插画和中文字体随包提供，无运行时下载。

## 玩法

- **观察 5 秒**：倒计时结束后自动打乱九块拼图的位置和 0 / 90 / 180 / 270° 朝向。
- **左键**：选中一块，拼块随鼠标悬浮；点击原位放下，点击另一格交换并放下。点击棋盘外不改变选中状态。
- **棋盘内右键**：将选中拼块沿桌面顺时针旋转 90°；未选中时不做任何操作。
- **完成条件**：所有拼块的**位置和朝向**都正确，并已放下最后一块。
- **操作数**：只计算实际交换和旋转；选中、原位放下不计数。
- **用时**：打乱动画结束后开始，完成时停止。
- **重新记忆**：重新观察 5 秒，挑战相同的洗牌开局。
- **换个开局**：重新观察 5 秒，生成新的随机开局（同一幅原创插画）。

观察、打乱、完成阶段禁止操作拼块；动画中暂时锁定点击，避免重复交换。重开会取消旧动画与选中状态，清零用时和计数。没有常驻答案缩略图、编号或正确位置提示。

## 项目结构

```text
main.tscn                  主场景
scripts/main.gd            3D 桌面、相机投影、容器 UI、动画与计时
scripts/puzzle_state.gd    独立可测试的状态模型
scripts/puzzle_piece.gd    立体拼块、九分区贴图与选中材质
assets/garden.svg          原创连续花园矢量插画
assets/AtelierSans.otf     随游戏精简打包的中文字体
```

## 局部验证

测试脚本、隔离工程、日志、截图及缓存只放在本子仓 `tmp/test/`，由 `tmp/.gdignore` 排除正式工程扫描。

本机已有的 `tmp/test/3d_preview/check_3d.gd` 覆盖：四种尺寸的九格投影选取、鼠标事件路由、动画输入锁、旋转与交换计数、相同种子重开、旧动画取消、完整求解和完成信号。`capture_3d.gd` 使用实际 3D 渲染输出记忆阶段与抬起拼块的截图。

```powershell
godot --headless --path tmp/test/3d_preview --script res://check_3d.gd --log-file "$PWD/tmp/test/check_3d.log"
godot --path tmp/test/3d_preview --script res://capture_3d.gd --log-file "$PWD/tmp/test/capture_3d.log"
```

人工鼠标手感、完整框架流程和联机不属于本次自动检查范围。

## 素材

- `assets/garden.svg` 为本项目原创矢量插画《花园小憩》，全部图形本地绘制，无第三方图片依赖。
- `assets/icon.svg` 为本项目原创图标。
- `assets/AtelierSans.otf` 为 Noto Sans CJK SC 的精简子集，遵循 SIL Open Font License 1.1，见 [`assets/FONT-LICENSE.txt`](assets/FONT-LICENSE.txt)。
