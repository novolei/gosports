# 排球触屏操控（毫米制触摸套件，2026‑10‑05）

> 套件来自 `gosports-basketball`（`scripts/touch/*`，提交 2baebe1；它按 Minitanks 的触屏研究重新实现：`H:\GDP\mini-tanks\docs\design\touch-feel-tuning.md`、`mobile-control-feel-research.md`）。设计、参数含义、移植步骤、真机数据见篮球仓库的 `docs/TOUCH_CONTROLS.md`（本文只写**排球的胶水层和与篮球不同的地方**）。套件最终要进 `gosports-core`（`CORE_PROPOSAL_TOUCH.md`），现在先各游戏各拷一份。

## 1. 排球原来的问题（Mi 11：画布 2400×1080，1 画布像素 = 0.0657 mm）

| 项 | 旧 | 新 |
|---|---|---|
| 摇杆半径 | 110 px = 7.2 mm | **11 mm**（读真实 DPI） |
| 按键 | HIT r118 / JUMP r82 / DIVE r72 px = 15.6 / 10.8 / 9.4 mm 宽 | 半径 **9.5 / 8 / 7.5 mm**（小 / 中 / 大三档 ×0.85 / 1 / 1.15） |
| JUMP 下沿离屏幕底边 | 4.5 mm（系统回桌面手势区） | ≥ 6 mm（`bottom_margin_mm`），左右 ≥ 7 mm |
| 抬起 | 固定 +90 ms 才释放 | 最短按压 55 ms，长按立刻松开 |
| 死区 | 每轴方形 0.12，再叠 `Input.get_vector(…, 0.18)` 的第二层 | 径向死区 1.4 mm + 满速平台 0.92R，输出按 `HumanBrain.DEADZONE` 预补偿，玩家得到的就是摇杆模型的值 |
| 多指 | 按下时找第一个命中的按钮，手指滑到别的键不处理 | 每根手指绑定它先碰到的东西；滑到别的键不会按它；同一个键的第二根手指被吞掉 |
| 取消 / 失焦 / 暂停 | 只有 `_exit_tree` 释放；暂停菜单打开时触摸还会穿给摇杆 / 按键 | 系统取消 = 取消（不是松手）；失焦 / 后台 / 隐藏 / 暂停时全部释放；暂停时触屏层不吃触摸 |
| 触摸 → 鼠标 | `p1_hit` 绑了鼠标左键，Godot 默认把第一根手指仿真成左键点击，**手指落在摇杆上就可能触发击球** | `Game.set_touch(true)` 时把鼠标键从 `p1_hit` / `p1_jump` 摘掉，非触屏时装回去（见 §4，**未在真机上验证**） |
| 点选落点 | 差一点没点中按键（1.12 半径之外）会当成点选落点；HUD 暂停 / 相机键只靠位置躲开 | 按键 1.4 半径内不算点选；HUD 暂停 / 相机键登记成保留区 |
| 朝向 | `orientation=6`（竖屏也行） | `4`（SENSOR_LANDSCAPE）+ `Main._ready` 里移动端再调一次 |

## 2. 结构

```
InputEventScreenTouch/Drag ─▶ TouchControls._input (scripts/ui/touch_controls.gd，排球胶水层)
                                │ router.handle(event)        → 吃掉的触摸 set_input_as_handled
                                ▼
                          TouchRouter (scripts/touch)        手指绑定 / 命中 / 最短按压 / 取消
                           ├─ StickModel                      浮动或固定摇杆，径向死区，满速平台
                           └─ buttons {hit, jump, dive}       圆心 / 半径 / 命中半径（半径 + 3 mm）
          button_down/up, stick_changed ─▶ Input.action_press("p1_hit" / "p1_jump" / "p1_dive", p1_left … p1_down)
                                ▼
                          HumanBrain.think → _to_world (屏幕方向 → 世界方向，侧面视角也一样)
```

* 点选落点：没被摇杆 / 按键 / 保留区拿走的触摸，落在「屏幕中间、下 28 % 以上」的区域里就发 `aim_tapped(pos)`（HUD 把它变成落点标记）。
* 按键布局（毫米，离右 / 下边；左手模式整体镜像）：HIT r9.5 @ (27, 21)、JUMP r8 @ (47, 15)、DIVE r7.5 @ (21, 43)；摇杆休息位 (32, 27)，触摸区 = 屏幕左 42 %、上 38 % 以下。`button_scale` 以边距角为中心缩放整个扇形，按钮之间留 ≥ 3 mm（`_resolve_overlaps` 兜底）。
* HIT 键的图标跟随上下文（bump / set / spike / serve / block）并在球快到时脉动：`Hud._update_timing_ring()` → `set_hit_hint()`，没变。

## 3. 与篮球套件的差异（改了套件的地方）

* `TouchFeel.hidden` / `TouchFeel.rows()`：游戏声明自己不用的参数，调参面板跳过（排球没有冲刺和蓄力甜区：`auto_sprint`、`sprint_on/off`、`haptic_sweet_*`、`haptic_sprint_*`）。`tools/test_touch.gd` 有对应的 2 项检查。其余 6 个套件文件与篮球一致（要往 core 提升时只需对齐这一处）。
* 没有自动冲刺、没有蓄力环、没有 `cancel_hook`（排球的三个键都是点按，取消 = 立即释放动作）。
* 绘制仍是排球原来的立即模式（没有 HudAtlas 烘焙）：只在摇杆 / 按键状态变化或脉动时重绘；以后手机上帧率不够再烘焙。

## 4. 触摸 → 鼠标仿真的疑点（还没有真机验证）

Godot 的 `emulate_mouse_from_touch`（默认开）把「第一根手指」变成一次左键点击；排球（以及足球 / 乒乓球 / 网球 / 篮球）都把 `p1_hit` 绑了鼠标左键、`p1_jump` 绑了右键，所以手指只是落在摇杆上也可能触发 `p1_hit`。机器人用 `Viewport.push_input` 注入触摸，**绕过 `Input` 单例**，所以测不出这件事。现在的做法是在触屏模式下摘掉鼠标键（`Game._sync_mouse_bindings`，`--touchbot` 检查「触屏模式下没有鼠标键绑定」）。要验证真的有问题 / 修好了：Mi 11 打开「开发者选项 → USB 调试（安全设置）」后 `adb shell input tap` 才能注入（HyperOS 默认拦截），或者用真手指在摇杆上按一下看角色会不会挥臂。

## 5. 设置、开发开关、测试

* 玩家设置：设置 → 操作：「触屏按键大小」（`touch_size` 小 / 中 / 大）、「摇杆样式」（`touch_stick` 浮动 / 固定）、左手模式、触觉震动；`--touch` 强开触屏 UI。**调参面板存过的键优先于玩家设置**（`TouchFeel.is_tuned`）。
* 真机调参：对局里三根手指按住不动 2 秒打开面板（调试包顶部有常驻 `T` 键）；`<` `>` 选参数、`-` `+` 改（按住连发）、`Copy` 把改过的数字 + 设备信息复制出来，贴回来即可；改动存在 `user://touch_tune.json`，`Reset` 清掉。
* 开发开关：`--touch`（桌面强开触屏 UI，鼠标当一根手指）、`--touchlog`（logcat 里 `[touch] dpi=… down / up / button / stick …`）、`--touchbot`（整链路机器人）、`--touchshots=<dir>`、`--touch-tune`（常驻 T 键）、`--touch-dpi=<n>`、`--noexclusion`（关掉边缘手势排除区做 A/B）、`--lefty`。手机调试包可以在 `files/dev_args.txt`（每行一个开关）里放同样的开关，`Main` 在调试包里读它。
* 测试：
  ```bash
  G=/d/Godot_v4.7.1/Godot_v4.7.1-stable_win64_console.exe
  $G --headless --path . -s tools/test_touch.gd                                   # 套件纯逻辑：56 项
  $G --path . --resolution 1920x864 --windowed -- --screen=match --touch --touchbot --nosave --skipvs --mode=solo --view=0   # 整链路：31 项（--view=1 = 侧面视角）
  ```
  机器人检查：布局在屏内、不重叠、物理尺寸（HIT ≥ 9×0.85 mm 等）、最低按键边离底边 ≥ 6 mm、触屏模式下没有鼠标键绑定、满推 / 半推 / 斜推 / 死区抖动、20 ms 点按能被 60 Hz 循环看到（三个键）、300 ms 长按抬起即释放、取消触摸立即释放、手指滑到别的键不按它、双指（摇杆 + 按键）、切后台全部释放、点选落点 / 差一点不算 / HUD 暂停键不算且真的暂停了、暂停时释放且不吞触摸、三指 2 秒打开调参面板；每项在两个视角下都成立（屏幕右 = 世界 −z 的侧面视角用 `CameraRig.input_basis` 换算）。

## 6. 没做 / 下一步

* **真人手感**：所有数字（半径、死区、按键位置）是按 Minitanks 研究、篮球的 Mi 11 实测和人机工程资料推出来的起点，需要真人用调参面板定数（`Copy` 贴回）。
* 边缘手势排除区的实际效果没验证（见篮球文档 §6）；默认开。
* 手机上的帧率 / 发热没测（触屏精灵变大了，摇杆约 367² px）。
* One Euro 摇杆平滑、回中弹簧动画、自定义布局编辑器、触摸 → 画面延迟探针没做。
* 物理按键 / 手柄混用时自动隐藏触屏层（Minitanks 的 `InputModeTracker`）没做，靠 `touch` 设置（自动 / 开 / 关）。
