# GoSports 排球 — 设计说明 / 需求理解

> Godot 4.7（Mobile 渲染器）· 2v2 卡通排球 · 视觉与手感参考 *Nintendo Switch Sports · 排球*，
> 操作改为 **PC 键鼠 / 手柄 / 手机触屏** 三套方案。

## 1. 我对需求的完整理解

| 你的要求 | 本作的落实 |
|---|---|
| 做一款 **Nintendo Switch Sports 排球** 风格的 2v2 对战游戏 | 2v2、每队最多 3 次触球（垫→传→扣）、发球 / 拦网 / 扑救 / 快速扣球、落点圈、PERFECT 判定、左上角队伍计分牌、“接下来是 扣球” 提示条、发球气泡，全部按参考截图复刻 |
| **不用 Toon / 赛璐璐**，按 Switch Sports 的画面与着色风格 | 柔和的“半兰伯特 + 柔边缘光”材质、明亮高饱和配色、暖白方向光 + 天空环境光、Filmic 色调映射 + 轻微泛光 / 饱和度提升、光滑的橙→粉渐变球场与青绿色缓冲区、白色抗锯齿线条、天际线背景、绿植 |
| 场地直接用 **4182 低面体育场套件** | 看台（Seating_01 / 02）、泛光灯塔（Stadium_Light）、树（Stadium_Tree）均来自该套件；球场地面 / 球网 / 球柱是程序化生成（为了做出 Switch Sports 的渐变球场与黑色球网） |
| 角色：**20 个卡通角色 + 4 个忍者**（Cubebrush 角色包 + 忍者模块包） | 24 名可选角色（`scripts/data/roster.gd`）：20 个 Simple Character Pack 的动物 / 人类（每个独立贴图），4 个忍者由 *身体 + 头 + 脸 + 头发 + 头饰* 模块在运行时拼装；每个角色有 **速度 / 弹跳 / 力量** 三项数值 |
| 球：使用提供的排球模型 | `assets/ball/volleyball.fbx` |
| 动作动画：现有素材 + 可用 Mixamo 补充 | 见 §4：Cubebrush 跑 / 走 / 待机动画重定向到两套骨骼，排球专用动作（准备、垫、传、扣、发球、拦网、扑救、庆祝、沮丧…）用“肢体端点规格”手工制作并烘焙；烘焙器也支持 Mixamo（`ClipDefs.MIXAMO`，已验证可用，默认未启用） |
| 物理 / 磁吸 / 落点预判 | 球使用**自定义弹道模拟**（可精确预测落点、保证击球轨迹可控，比刚体更稳定）；击球时球被“磁吸”到手部接触点再按规则给出速度；地面实时显示落点圈 |
| 运镜：近景冲击、震屏 | 自写 `CameraRig`（等价于 Phantom Camera 的用法）：跟随球、完美扣杀时 FOV 收紧 + 震屏、得分时慢动作 + 推进、开场摇镜 |
| 特效：拖尾、击球星星 | 球拖尾（扣杀 / 完美击球时点亮，颜色随质量变化）、击球火花、灰尘、落地冲击环、彩带、PERFECT 光晕 |
| **PC 键鼠 / 手柄 / 手机触屏** 操作（不是 Switch 体感） | 见 §3 |

## 2. 玩法设计

### 2.1 规则
* 2 对 2，场地 9 m × 14 m，球网高 2.2 m。
* 每队最多 3 次触球，同一人不能连续触球（拦网后双方次数重置）。
* 球落在对方场内 = 得分；出界 = 最后触球方失分；发球触网 = 失误；抛球没打到 = 发球失误。
* 先到 **7 / 11 / 15** 分且领先 2 分获胜（最多 +5 封顶）。得分方发球，换发球权时队内轮流发球。

### 2.2 “击球键”是情境按键（核心设计）
同一个按钮根据球的高度 / 角色状态自动决定动作，所以键鼠、手柄、触屏只需要一个主按钮：

| 状态 | 动作 | 说明 |
|---|---|---|
| 发球位 | 抛球 → 再按击球 | 抛球后在最高点附近击球；先按跳跃再击球 = 跳发（更快、更难控） |
| 地面，球低 | **垫球 / 接发** | 默认垫给队友（传球目标） |
| 地面，球在头顶 | **传球** | 默认传到队友起跳点；队友已起跳 → 自动变成 **快速扣球（QUICK）** 的低平快球 |
| 空中 | **扣球 / 吊球** | 落点靠瞄准；瞄准点靠近球网 = 吊球 |
| 球太高 | 直接按击球键 → **自动起跳** 去扣 | 单键友好 |
| 网前起跳（不击球） | **拦网** | 手臂过网；KILL BLOCK 直接砸回对方场地 |
| 扑救键 | **扑救** | 够不到的低球 |

击球质量按“球与理想接触点的距离”分为 **PERFECT / NICE / OK**：质量越高，落点越准、扣球越快，并触发火花、拖尾、震屏。
角色脚下的发光圈 = 击球范围，球进入圈内并变亮时按键即 PERFECT。

### 2.3 瞄准
* 键鼠：**鼠标指针**指向对方场地的位置（准星落点实时显示）。
* 手柄：**右摇杆**（推向哪里，球就打向对方场地哪里；松开 = 智能落点）。
* 键盘单人：方向键瞄准。
* 触屏：**点一下对方半场**设定落点，击球后自动清除。
* 不瞄准 = “智能落点”：避开对方防守者的空位。
* 第 1 / 2 触球默认是配合（垫给队友、传给扣球手）；用右摇杆 / 方向键向前瞄准可以直接把球打过网。

### 2.4 辅助
“自动跑位辅助”（默认开）：球来时，如果你是该队“最该接球”的人且摇杆没动，角色会自动跑向球的落点，你只负责**时机与瞄准**；一碰摇杆立刻手动接管。

### 2.5 模式
* 单人对战：你 + 电脑队友 vs 电脑二人组（4 档难度）
* 双人合作：P1 + P2 同队 vs 电脑
* 双人对决：P1（+电脑）vs P2（+电脑）同屏
* 锦标赛 / 新手教学 / 回合挑战：见第 18 节；成长 / 解锁 / 成就 / 每日任务：第 17 节

## 3. 操作

| | 移动 | 击球 | 跳跃 / 拦网 | 扑救 | 瞄准 | 暂停 |
|---|---|---|---|---|---|---|
| **P1 键鼠** | WASD | J / 鼠标左键 | K / 空格 / 鼠标右键 | L / Shift | 鼠标指针（单人模式也可方向键） | Esc / P |
| **P2 键盘** | 方向键 | 小键盘 1 / `,` | 小键盘 2 / `.` | 小键盘 3 / `/` | 小键盘 8 4 5 6 | — |
| **手柄 1 / 2** | 左摇杆 / 十字键 | A / RB / RT | B / LB | X / LT | 右摇杆 | Start |
| **触屏** | 左半屏浮动摇杆 | 右下“击球”大按钮 | “跳” | “扑” | 点击对方半场 | 右上角 II |

F11 全屏，C 切换镜头（远 / 中 / 近）。

## 4. 画面与美术实现

* **渲染**：Mobile 渲染器（PC 与手机共用）；MSAA、方向光阴影（4096）、泛光、色调映射 Filmic、饱和度 / 对比度调整，画质分三档（低档关闭阴影 / 泛光 / MSAA，手机默认中档）。
* **材质**：`StandardMaterial3D`，`Lambert Wrap` 漫反射 + 柔边缘光（无自发光——自发光会让颜色发白）；像素风调色板贴图使用 Nearest 过滤。
* **球场** `shaders/court.gdshader`：解析式线条（抗锯齿）、橙→粉渐变、网前进攻区高亮、青绿缓冲区、虚线、斜向光带；高光反射天空。
* **球网** `shaders/net.gdshader`：黑色网格 + 白色上下沿；球柱 / 天线 / 地面 VOLLEYBALL 字样。
* **环境**：程序化天空 + 天际线背景（程序生成贴图）+ 体育场套件看台 / 灯塔 / 树 + 蕨类绿植 + 观众（用角色模型站在看台上，通过三角网格射线检测找到座位高度）。
* **UI**：全部代码生成（`scripts/ui/ui_kit.gd`），圆角胶囊按钮、队伍色条计分牌、圆形头像（`tools/make_portraits.gd` 离线渲染）、弹出式 PERFECT / 得分字样；UI 字体为字魂趣圆黑（见 §9 授权说明），中文缺字回退系统字体。

### 角色与动画管线（`scripts/rig/`）
1. `RigInfo` 读取任意类人骨架（卡通角色、忍者、Mixamo），推导朝向 / 肢体长度。
2. `PoseSolver` 把姿势描述成**与骨骼无关的规格**（髋位移、躯干 / 头旋转、手腕目标、肘 / 膝极向量、脚目标…，全部按臂长 / 腿长归一化），再用两段 IK 求解成骨骼旋转。
3. 重定向 = 测量源动画的规格 → 在目标骨架上求解；因此同一份动作可以用在卡通角色（短手臂 → 运行时把上臂骨骼放大 1.45 倍）和忍者上。
4. `tools/bake_anims.gd` 把 Cubebrush 的 31 个原始片段 + `ClipDefs.authored()` 里手写的排球动作烘焙成 `assets/anim/cube_lib.res` / `ninja_lib.res`。
5. 运行时 `CharacterRig` 组装模型 + 贴图（忍者：身体 / 头 / 脸 / 发 / 头饰；人类：头发贴图）+ AnimationPlayer。

## 5. 代码结构

```
scripts/
  core/    game.gd(设置/输入映射/场景流转·autoload)  sfx.gd(音效/BGM·autoload)  main.gd(根节点)
  data/    roster.gd            24 个角色 + 数值
  rig/     rig_info / pose_solver / clip_defs / character_rig(含 AnimationTree 跑动层)
  match/   court(常量) arena(场景) ball(弹道) athlete(运动员)
           match_director(规则/计分/投球规划/拦网/AI 规划)
           human_brain / ai_brain   camera_rig vfx confetti crowd  match_scene(装配)
           body_collisions(角色碰撞) dizzy_stars ball_ribbon(彩带拖尾) move_hint(脚下箭头)
  ui/      hud  touch_controls  menu_screen(主菜单/模式/选角/阵容/设置/说明)  results_screen  stage  ui_kit
  dev/     human_bot.gd         用真实 InputMap 驱动 P1 的测试机器人
tools/     bake_anims  make_portraits  preview_*(含 preview_loco / preview_trail)  inspect_*  check_scripts(严格版)
           gen_audio.py  gen_env_textures.py  gemini_icon.ps1  key_icon.py  build_android.ps1
art_src/   Gemini 生图的原始图 + 提示词（带 .gdignore，不进包；生成不可复现，原图是唯一来源）
shaders/   court  net  ring
```

### 关键逻辑
* **Ball**：自定义弹道（重力、地面反弹、球网碰撞）、`predict_landing()`、`Court.solve_velocity()` 反解“从 A 到 B 用时 T 的初速度”，`MatchDirector._solve_over_net` 保证击球一定过网（除非故意失误）。
* **MatchDirector**：阶段机（开场 → 准备发球 → 发球 → 回合 → 得分 → 结束）；每帧为双方规划“谁去接球 / 去哪 / 何时”（供 AI 和玩家辅助共用）；`plan_shot()` 把一次击球变成轨迹（垫给队友 / 传给扣球手 / 吊球 / 扣杀 / 发球…），质量越差误差越大。
* **AIBrain**：反应时间、跑位误差、起跳时机、扣球落点选择、拦网、扑救均由 `skill`（0‑1）调节；难度档位 = 对手 skill 0.3 / 0.5 / 0.72 / 0.93，电脑队友略强。
* **Athlete**：移动 / 跳跃 / 扑救 / 情境击球 / 输入缓冲（0.2 s）/ 动画选择 / 脚下圈圈；击球动画提前 45 ms 起播，使接触帧与出球对齐。

## 6. 音频
全部为程序合成（`tools/gen_audio.py`）：31 个音效 + 2 首循环 BGM（菜单 104 BPM / 比赛 126 BPM）+ 胜利 / 失败短曲。

## 7. 开发者命令（`--` 之后）
```
--screen=match|menu|select|howto|results   直接进入某界面
--page=mode|lineup|settings|howto|practice|career   菜单子页（更多开关见第 19 节）
--autoplay                                  四个电脑互打（--timescale=8 加速，--points=7，--quit_on_over，--log）
--humanbot --mode=solo|coop|versus          用 InputMap 驱动 P1 的机器人
--team_a=m,bear --team_b=snow,wang          指定阵容   --diff=0..3
--shot=out.png --frames=N                   截图后退出   --burst=prefix --burst_n --burst_every --burst_start
--hitshots=prefix                           在每种击球瞬间截图
--dbgpose                                   统计骨骼单帧旋转突跳（姿态是否丝滑）
--dbgcollide=head|chase|brush --collshots=prefix   强制两名队友互撞（迎面 / 追撞 / 轻碰）并截图
--movehintshot=out.png  --shotspd           脚下箭头截图 / 打印各类击球的球速
--touch                                     强制显示触屏控件     --cam=h,z,fov   覆盖镜头
```
注意：`Engine.time_scale` 会同时放大物理步长，`--timescale` 建议 ≤ 2，过大会让物理步过粗、AI 表现失真。
`godot --headless --path . -s tools/check_scripts.gd` 编译检查全部脚本；`godot --headless --path . -s tools/bake_anims.gd -- cube|ninja` 重新烘焙动画；`godot --path . -s tools/make_portraits.gd` 重新生成头像。

## 8. 验证情况
* 无头模式下 4 电脑互打整局（7 / 11 / 15 分）多次，规则、发球轮换、触网 / 出界 / 拦网判定通过，平均回合约 10 次触球。
* 三种模式、触屏布局（1280×590 手机比例）、Windows 导出版（`build/windows/GoSports.exe`）均已实机运行并截图检查。
* 真人手感（时机窗口、辅助强度、手柄 / 触屏）需要你上手试玩后微调，常量集中在 `Athlete.KINDS`、`MatchDirector._shot_*`、`AIBrain`。

## 9. 授权 / 注意
* 角色 / 体育场 / 球 / 忍者素材来自你提供的素材包，请遵守各自许可。
* `assets/fonts/ui_font.ttf`（字魂趣圆黑）是**试用版，商用需授权**；商用前请替换为已授权字体（删除该文件即回退到系统字体）。
* Android：已按 Minitanks 的 ship-kit 流程出包（见 §14），APK 经静态校验；**尚未在真机上跑过**（需要你确认安装到哪台手机）。
* 你打开的 Godot 编辑器是在我修改 `project.godot`（自动加载、输入、窗口设置）**之前**启动的，请**关闭并重新打开**项目，否则编辑器可能用旧设置覆盖它。

## 10. 角色运动（locomotion）

目标：全向移动丝滑、优雅。运动员始终面朝球网，向任意方向跑 / 侧移 / 后退，所以用**局部速度驱动的二维混合空间**。

* `CharacterRig._build_tree()`：AnimationTree = `Loco`（BlendSpace2D，17 个点：中心 `ready`；前 / 后 / 左 / 右各 3 档速度 0.35 / 0.7 / 1.0（单位 `ClipDefs.LOCO_SPEED`=5.05 m/s）；前左 / 前右斜向 2 档）→ `LocoTS`（TimeScale）→ `Mix`（Transition：loco / 动作 A / 动作 B，A/B 交替保证同一个动作连按也能重新开始）。
* `Athlete._update_visual_motion()` 每帧把本地速度喂给混合空间（半衰期 0.055 s 平滑），所以换向时是连续插值而不是硬切；同时给身体一个**随速度 + 加速度**的前倾（`lean_pivot`），击球 / 摔倒等动作状态下归零。
* 瞬时转向（击球后朝向出球方向、扑救）只改模拟用的 `yaw`，视觉上用 `_vis_yaw` 在约 0.1 s 内转过去。
* **步频随速度上升**（`CharacterRig.gait_rate`，最高约 3.8 步 / 秒）：角色是 Q 版（腿长 0.43 m）却要以 5 m/s 跑，脚不可能不滑，只能靠提高步频和适度幅度来缓解；静止时保持 1.0。
* 烘焙修正（`tools/bake_anims.gd`）：
  * 左侧移 / 后退的源循环与前跑的**步态相位相反**，斜向混合时左右腿互相抵消 → 烘焙时按 `ClipDefs.LOCO_PHASE` 把循环对齐（实测前左斜向脚速 1.2 → 2.3 m/s）。
  * `PoseSolver.measure` 的脚 yaw 在脚尖垂直时会翻转约 160° → 归一化 + 限幅 + 按水平分量置信度衰减；再对脚角度做循环 3 点低通。
  * 同一个 clip 另烘焙 `<clip>_h`（从接触前 0.045 s 开始），击球零延迟。
* 验证：`--dbgpose`（逐帧骨骼最大旋转跳变：p99 0.71 → 0.22 rad）、`tools/preview_loco.gd -- slide|sheet|sweep`（支撑脚滑动量 / 方向 × 速度联系表）。

### 关于 Motion Matching 插件的评估（`D:\Godot resource\rooftop-bird-team\addons\motion_matching`）

结论：**本项目暂不采用**，保留 AnimationTree 混合空间；借鉴它的思路（步频匹配、倾斜、惯性化式的短过渡）。依据：

* 它是 C++ GDExtension（`MMCharacter` / `MMAnimationNode` / `MMAnimationLibrary` + 脚 / 惯性化 / 倾斜修改器）。你的路线图写明**只验证了 Windows x64**；`bin/android` 里的 .so 是上游旧版 debug 二进制，**没有** gait / 步频 / 惯性化 / 查询调度等你后来的改动，也没有 release 版。
* C++ 源码：原路径 `C:\Users\aresr\Downloads\godot-motion-matching-master` 已不存在；新找到的 `godot-motion-matching-demo` 只有 demo 工程和预编译二进制，没有 `.cpp` / `SConstruct`。要出 Android 版需重新拉上游（基线 commit + 文档里的 patch + godot-cpp 指定 commit）并用 NDK 编译（Minitanks 的 `.tools` 里有 NDK）。
* 性能（取自你的 Release 实测，非我实测）：53,849 姿势 × 67 维的精确扫描，单次查询 p95 约 0.8–1.0 ms，20 Hz 错峰；PC 上 4 人完全没问题。手机上按内存带宽估算约 1–3.5 ms / 次，4 人 × 20 Hz 约占一个大核 10–25%（**估算，未实测**）。
* 数据：数据库是**骨架专用**的（24 骨 Meshy，116 MB），我们的 48 骨方块角色 / 40 骨忍者要各自重烘焙；手上的 Mixamo 包只有约 30 个 locomotion 循环（没有起步 / 急停 / 转身），做成数据库就退化成混合空间，得不到 MM 的收益。
* 若以后有适配 Q 版骨架的带起停 / 转身动捕数据，并重编 Android release 库，再评估混合方案（PC 用 MM、手机用混合空间会让测试矩阵翻倍，不建议）。

## 11. 角色碰撞（`scripts/match/body_collisions.gd`）

对手被球网隔开，碰撞实际发生在**同队两人**之间（追同一个球、冲刺、扑救）。每个物理帧：重叠的身体按质量（`power^3`）推开（躺下的人几乎不动）；沿接触法线的相向速度 × 质量份额 = "冲击量 jolt"：

| 冲击量 | 反应 |
|---|---|
| < 1.6 | 只推开 |
| 1.6 – 4.8 | 轻碰（轻微音效 + 小尘土） |
| 4.8 – 8.5 | **踉跄** 0.3–0.55 s：手臂张开的踉跄动作 + 上身后倾，短暂失控，末段可以击球 |
| ≥ 8.5 | **撞倒**：朝撞击方向仰面摔出 → 眩晕坐姿（头顶星星环绕，0.5–1.0 s）→ 起身；期间不能击球、导演选人时被当作"不在场"；有 4 s 免疫防止连环撞 |

* 击球姿势中受冲击 ×0.75，扑救中 ×0.5，已失衡再受撞 ×1.25。
* 特效：撞击处「咚」表情图标（Gemini 生成）+ 星星 / 尘土 / 地面冲击环 + 镜头抖动；音效 `body_bump` / `crash` / `dizzy`（`tools/gen_audio.py`）。
* **灵敏度刻意压低**（你要求：不能影响对局质量）：AI 中不接球的队友会提前、明显地让路（对真人队友更多）。5 分钟 AI 对打统计：撞倒约 1–2 次、踉跄 3–8 次。`--dbgcollide` 可强制复现。

## 12. HUD / VFX（对照 Switch Sports 对局画面与你提供的视频，原创实现，不使用任何官方素材）

* **记分牌**：叠放圆形头像 + 名字药丸 + 尾部渐隐的队伍色长条 + 大号描边数字（`_ScoreBar` 自绘）。
* **动作气泡**：圆形双环气泡 + 白色动作剪影（垫球 / 传球 / 扣球 / 拦网 / 发球 / 扑救，Gemini 生成），顶部「下一步: 垫球」提示、发球者头顶「发球」气泡；来不及时提示「扑救」。
* **判定弹字**：`Nice!`（薄荷绿）/ `Nice! ×N`（粉）/ `早了!` / `晚了!`；落点 `In` / `Out` 小药丸。
* **完美连击**：垫球 → 传球 → 扣球全部完美 = 粉色**强力扣球**（`Ball.combo`：粉色粗拖尾，拦网无法直接拍死）。
* **彩带拖尾**（`ball_ribbon.gd`）：朝向相机的带状网格，颜色**按球速逐点渐变**：青（吊球）→ 薄荷 → 黄 → 橙 → 粉红（重扣）；"Nice!"更宽更亮，强力扣球为粗粉带；球周围光晕同色。`tools/preview_trail.gd` 可预览。
* **得分过场卡**（双方头像 + `1 - 0`）、**赛点横幅**（发球两人头像 + 滑入文字）、玩家头顶 `P1` 标记（取代 3D 名牌）、脚下**青色左右箭头**（真人是接球人且还没到位时出现，朝落点一侧更亮）。

## 13. Gemini 生图流程（图标 / 概念图）

沿用 `hard-north` 的流程：`tools/gemini_icon.ps1`（Vertex AI + 本机 gcloud 登录，无 API 密钥；`gemini-3-pro-image`，global 端点）。模型**不能输出真透明通道**，所以让它在**纯绿色背景**上画，再用 `tools/key_icon.py` 抠色（边缘用抠像方程做前景色还原，去绿溢色）。

* 原图和 `.prompt.txt` 保存在 `art_src/gemini/`（生成不可复现，原图是唯一来源；改抠色参数不需要再调 API）。
* 429 = 太快，间隔 ≥ 28 s；遇到 Google 的 "Sorry…" HTML 页是反滥用拦截，**不要重试**。每次调用都花钱，批量前先确认。
* 同一套图标：先出一张当风格锚点，后面的把它作为参考图。

## 14. Android 打包（`tools/build_android.ps1`，参考 `H:\GDP\mini-tanks` 的 ship-kit）

暂存目录里做一份隔离拷贝 → 便携编辑器（独立编辑器设置）→ 导入 → `--export-debug "Android"` → 检查 manifest / `lib/arm64-v8a/libgodot_android.so` / 资源包 / `apksigner` / `aapt`，versionCode = 自 2025‑01‑01 起的分钟数，写 `build/android/build_record.json`。手机上不开 MSAA；`adb -s <序列号> install -r`（降级用 `-d`），不卸载 / 不清数据 / 不杀 adb server，另一台设备可能不是你的。

## 15. 手机性能（小米 M2007J17C / Android 12 / 2400×1080 实测）

流程：`tools/phone_perf.sh <序列号> <标签> [画质] [渲染比例] [阴影图] [开关]`（写入设置文件 → 重启游戏 → 自动点进对局 → 读调试包每 5 秒打印的 `[perf]` / `[prof]`：fps、脚本耗时、渲染 CPU / GPU 耗时、绘制调用、分段计时 `Prof`）。`Game.dbg()` 提供渲染"关闭开关"（`ambient nosky nofog noadjust notonemap noshadow noferns nostands nobackdrop nocrowd nohud nocourt fsr`）用来逐项定位。

首次实测 **22–30 fps**，GPU 约 25 ms/帧，绘制调用约 800；我自己的脚本每帧合计只有 5–7 ms，**不是瓶颈**。逐项开关对比（GPU ms / 绘制调用）：HUD −3.2 ms / **−475 次**（渐隐比分条每帧画 ~380 个多边形）、蕨类 −4.7 ms / −190 次（每株 3 个节点）、改纯色环境光 + 关天空反射 −3.7 ms、球场着色器 −2.7 ms、天空 −2.6 ms、阴影 −1.9 ms；雾 / 色彩调整 / 背景 / 观众几乎没有成本。

已做的优化与结果：

| 优化 | 说明 |
|---|---|
| 比分条改为预生成纹理 | 按队伍色缓存，`_ScoreBar` 只画一张图 |
| 蕨类合并为一个 `MultiMesh` | 约 190 → 1 次绘制 |
| 手机环境光 | 纯色环境光 + 关闭天空反射（`Arena._build_environment`） |
| `shaders/court_lite.gdshader` | 手机用的球场着色器，`specular_disabled` |
| 3D 渲染比例 + FSR | 画质档 0 / 1 / 2 = 0.62 / 0.74 / 0.9；手机用 FSR 放大，UI 保持原生分辨率 |
| 手机阴影 | 1024 阴影图 + 单级正交阴影（中档）；泛光仅高档 |
| **动态分辨率** | `Game._dynamic_resolution`：每秒看平均帧时间，> 21 ms 降 0.05（最低 0.5），连续 3 秒 < 17.5 ms 再升 0.03（不超过该档上限）；自动渲染比例时才启用 |

结果（同一台手机、同一场景）：28 fps / 25.5 ms GPU / 770 次绘制 → 固定 0.74 比例 **38 fps / 19.4 ms / 218 次** → 自动动态分辨率 **约 52 fps / 13 ms / 201 次**。内存平稳（static 约 172 MB，PSS 约 600 MB，无上涨）。其余设备会按各自性能自动取不同分辨率。

## 16. 打击感（Hit feel）

出手瞬间叠加多层反馈（`MatchScene._hit_feel` 统一调度，强度随击球质量 / 力度缩放）：

* **顿帧**：`CameraRig.hit_stop(dur)` 把 `Engine.time_scale` 短暂压到 ~0.05（用真实时间计时，不受时间缩放影响），Nice! 约 40 ms、扣球 / 强力扣球 60–90 ms。
* **球的形变**：`Ball.punch_shape` 在 `pivot` 上做压扁→拉长回弹；球速线（`_SpeedLines`）、屏幕边缘的冲击光。
* **音效分层**：击球 + 质量音 + 扣球加 `whoosh`；`tools/gen_audio.py sfx name...` 可只重生成指定音效。
* **震动**：`Game.haptic()` → 手机 `Input.vibrate_handheld`，手柄 `start_joy_vibration`（设置里可关）。
* **击球时机圈**：球进入击球范围时，球上出现缩小的光圈，缩到最小按键 = Nice!（设置 / 暂停菜单可关）；手机上击球按钮同步脉动，并随情境显示「垫球 / 传球 / 扣球 / 发球」。
* **热血时刻（Fever）**：连续 Nice! / 拦网 / 救球 / 大分累计热血条（`MatchDirector.add_hype`），满格后 9 秒（`FEVER_TIME`）：判定窗口 ×1.35、击球更有力、球拖火焰、观众欢呼、屏幕边框火光（`shaders/fever_frame.gdshader`）。
* **强力扣球**：垫、传、扣三次全是 Nice! → 粉色球轨迹，`ball.combo`，几乎拦不住（`Game.live("power_spikes")`）。
* **差点出界**（`close_call`）、**赛点**（音乐加速 `Sfx.music_tension`）、最后一分慢动作。

## 17. 成长系统（`scripts/core/profile.gd`，存档 `user://profile.json`）

* **经验 / 等级**：每级需要 `100 + 50·level` 点经验，30 级封顶；头衔随等级变化（新手 → 传奇）。比赛结算 `finish_match()`：胜负、得分、Nice!、ACE、拦网、强力扣球、热血等分项 + 难度 / 连续登录倍率，返回 `lines / mults / xp / unlocks / achievements / missions` 给结果页。
* **解锁**：球拖尾 7 种（速度彩带、星光、队色、樱吹雪、彩虹、烈焰、寒霜）、比赛用球 6 种、球场主题 4 种（晴空日场、黄昏、灯光夜场、薄雾清晨）。球皮肤在 `MatchScene` 里通过 `Ball.skin_tint / trail_style` 注入（球脚本不依赖 `Game`，便于工具脚本单独实例化）；拖尾样式只作用于己方（team 0）的击球；球场主题由 `Arena.THEMES` 参数化天空 / 阳光 / 环境光 / 雾 / 背景色（夜场多一盏无阴影泛光灯，手机路径保持纯色环境光）。
* **成就**（20 个，计数器驱动，`bump / record_max`）与**每日任务**（每天 3 个，按日期种子抽取，次日刷新；连续登录天数给经验倍率最高 ×1.25）。`recheck_all()` 修复旧存档（旧的胜场记录迁移时按局数截断）。
* **角色特性**（`Roster.PERKS`）：iron / gale / eagle / might / agile / morale / steady 七种小特性，选人界面可见。
* 结果页（`results_screen.gd`）：经验计数动画、升级、解锁卡片、成就、任务进度；锦标赛 / 练习各有变体。

## 18. 模式

| 模式 | 说明 |
|---|---|
| 单人 / 双人合作 / 双人对决 | 原有对战，难度和分数在模式页设置 |
| **锦标赛** | 3 轮 7 分制（小组赛→半决赛→决赛，固定对手 + 递增难度），冠军 +150 经验；若玩家选了对手阵容里的角色，会自动换人（`Game.tournament_opponents`） |
| **新手教学**（`TrainingCoach`） | 清单：垫球接发 → 传球 → 扣球 → 3 次 Nice! → 8 次连续触球；球机发球，传球一步会把球先送给队友 |
| **回合挑战** | 球机发球 / 回球，3 条命，铜 / 银 / 金牌 = 连续 10 / 25 / 50 次触球；练习模式里对面球员不碰撞、不拦网 |

首次启动弹出欢迎窗，引导进入新手教学（`flags.welcomed`）；主菜单右侧显示等级卡片和今日任务，"生涯"按钮有新内容时亮红点。

## 19. 开发 / 测试开关（新增）

`--profile=user://x.json`（测试用独立存档）、`--nosave`、`--court=night|sunset|dawn`、`--trail=<id>`、`--ballskin=<id>`、`--welcome`、`--page=career --tab=0|1|2`、`--mode=rally|training|tournament`、`--autonext=<秒>`（结果页自动点主按钮）、`--resultshot=<png> --resultdelay=<秒>`、`--fever`。`tools/preview_trail.gd out.png 0 styles` 一次渲染所有拖尾样式。

碰撞阈值复测（2026‑10‑04，4 局 × 170 秒电脑互打）：原阈值 3.6 / 7.0 约每分钟撞倒 1.4 次，过于频繁；调到 4.8 / 8.5 后约 2–3 分钟 1 次。测试脚本 `tools/coll_count.sh`（数日志里的 `level=3`）。

## 20. 对照参考视频的第二轮 HUD / 体验打磨（2026‑10‑04）

逐段看了 `E:\backup\Volleyball! - Nintendo Switch Sports.mp4`（每 10 秒一帧的 16 张接触图 + 关键帧），补上此前缺的部分（均为原创实现）：

| 参考画面 | 实现 |
|---|---|
| 开场「VS」分屏卡：黑边、斜线分割左右两队、大 VS、每人名牌（称号 + 名字） | `ui/vs_card.gd` + `CameraRig.start_vs()`（侧面镜头，两队在场上摆好姿势，称号用角色特性名）；任意键 / 点击可跳过；锦标赛会显示轮次 |
| 「Score 5 points to win!」整屏宽斜条 | `Hud.show_target_banner()`，VS 卡之后、READY 之前 |
| 得分后慢动作回放（左上「Replay」+ 进度线 + 右下「Skip」） | `match/replay_system.gd`：30 Hz 录制球 + 四名角色骨骼姿势（7 秒环形缓冲），回放时用幽灵角色 + 侧面推进镜头 + 减速，青色斜向转场（`ui/replay_overlay.gd`）；只在长回合（≥ 8 次触球）/ ACE / 拦网得分 / 强力扣球后触发，且至少隔 3 分，结束时必放；设置 `replays` 可关 |
| 「Win!」整屏斜条 + 比分 + 获胜两人头像 | `Hud.show_win_banner()`（回放之后） |
| 「Your timing was… A BIT EARLY」两行教练提示 | `Hud._timing_note()`（替代原来的「早了! / 晚了!」） |
| 连续 Nice! 旁边的 ×2 金色气泡 | `Hud._combo_badge()` |
| 球飞出画面时，屏幕边缘的球图标；队友出画面时的头像气泡 | `Hud._EdgeTracker`（球带速度色尾迹指向球场；队友离屏 0.25 秒后出现头像 + 箭头） |
| 教程：深色标题 pill + 白色说明条 + 右侧「Bump!」卡片和三个打勾圆圈 | `TrainingCoach` 改成「垫 ×3 → 传 ×3 → 扣 ×3 → Nice! ×3 → 连续 8 次」，HUD 用 `_build_tutorial_ui()`；修了教练在 HUD 之后才创建导致教学面板从未显示的问题 |
| 菜单右下角按钮提示（Select / Back / OK） | `MenuScreen._build_footer()`（有手柄时显示 A / B） |
| 底部操作提示 | 改成键帽 chips（键盘 / 手柄两套） |
| 脚下的发光双环 | `ring.gdshader` 加外发光和亮芯线，环更粗 |
| 镜头跟随玩家左右移动、球场更贴近 | `CameraRig.follow_players`：水平跟随玩家 + 前瞻，玩家深入后场时抬高焦点；默认镜头更低更近 |

PC 手感 / 打击感新增：完美扣球的**镜头侧倾 + 白闪**（`roll_kick` / `flash_screen`）、跑动**脚步尘土**（仅人类玩家）、教学里**发球机会把球送给队友**。回放中隐藏 HUD 其余部分，结束后用同一转场回到比赛（`ReplaySystem._leave`）。

开发开关：`--replay`（autoplay 下也启用回放）、`--replayshot=<前缀>`（截回放 3 帧后退出）、`--winshot=<png>`、`--vs`（强制 VS 卡）、`--skipvs`（跳过 VS 卡，测试 / 截图用，autoplay 默认跳过）。

## 21. 第三轮：参考 Game UI Database 的整套界面语言（2026‑10‑04）

参考页：<https://www.gameuidatabase.com/gameData.php?id=1421>（Nintendo Switch Sports 的 69 张界面截图：标题 / 模式选择 / 加载 / 设置 / 教学 / 弹窗 / 选人 / 比赛设置 / 赛前 / 开场 / 暂停 / 比赛结束 / 结算 / HUD）。按用户要求**不做 Switch 体感操作相关的界面**（Joy-Con 摆放 / 挥动提示等），其余逐类对照：

| 参考类别 | 本项目实现 |
|---|---|
| 统一的按钮语言：浅蓝灰胶囊、选中变青绿 + 橘色 ▶ 光标、右下角 Select / Back / OK 提示 | `UIKit.button()` 整体重做（`GREEN` = 主按钮常亮青绿），`UIKit.toggle_pill()` 开关（取代过小的 CheckButton），分段选择器同款，菜单页脚按键提示 `MenuScreen._build_footer()` |
| 暂停：模糊的背景 + 药丸菜单（继续 / 重新开始 / 更改比赛设置 / 回到选择） | `shaders/ui_blur.gdshader`（读屏幕纹理做模糊），`Hud._build_pause_menu()` |
| 选人数 + 比赛设置：左侧磨砂面板列表，中央面板里头像 VS 行、`◀ 选项 ▶` 行、OK | `MenuScreen._build_mode()`：左「选择模式」列表 + 右「比赛设置」（头像槽 VS、难度 / 分数箭头行、自动跑位 / 回放开关、选择角色） |
| 开场：地点名 → VS 卡 → 「Score N points to win!」 | `Hud.show_title_tag()`（排球 · 球场名）→ `VsCard` → `show_target_banner()`；VS 卡有跳过提示 |
| 开始 / 结束用青绿胶囊（Start / Game!） | `Hud.show_pill()`：「开始!」「比赛结束!」 |
| Match Point：整屏宽的队伍色横幅 + 头像 + 文字 | `Hud.show_match_banner()` |
| 加载页：深色斜纹底 + 黄绿色标题 + 一句带彩色关键词的小技巧 | `ui/loading_card.gd`，`Main.goto("match")` 时显示至少 1.5 秒（12 条技巧，可用 `--noloading` 关闭） |
| 教学：说明条 + 右侧 Bump! 卡片 + 打勾圆圈 | 第 20 节 |
| 设置里的「Staff Credits」 | 设置 → 「制作与素材」（引擎 / 素材来源 / 字体试用版提示 / 灵感声明） |
| 提示「Next: Block」 | `Hud._update_hint()`：对方二传后，玩家在网前时显示「下一步: 拦网」 |

PC 手感新增：
* **按键设置**（设置 → 按键设置）：P1 的 WASD / 击球 / 跳跃 / 扑救可改键，冲突自动互换，存在 `settings.cfg` 的 `[keys]`；HUD 键帽提示、教学文字随之变化。`tools/test_keys.gd` 是单元测试。
* **晚按宽容（coyote time）**：球刚离开击球区 0.1 秒内按键仍算一次「ok」击球，不再空挥。
* 开发开关：`--demo=matchpoint|pill|win|title --demoshot=<png>`、`--pauseshot=<png>`、`--loadshot=<png>`、`--noloading`。

## 22. 第四轮：「去网页味」的界面语言、落点提示、本地化、字体（2026‑10‑04）

### 22.1 界面语言（`scripts/ui/game_widgets.gd` = `GW`，`UIKit`）
目标：看起来是游戏，不是网页。规则：
* **少容器**：能直接把胶囊按钮摆在（模糊的）场景上就不放卡片（暂停、模式、设置、按键、练习场）。
* **斜切 + 厚描边**：页面标题是斜切彩带 `GW.ribbon()`，面板是斜切、带高光和硬阴影的 `GW.board()`，而不是圆角白卡片。
* **整行胶囊代替表格**：设置项是「标签 ……… 控件」的一条长药丸 `GW.row_pill()`，没有分隔线、没有卡片。
* **深色记分牌 + 浅色字**用于数据密集的面板（结算、生涯、回合挑战 HUD、角色信息、主菜单的等级 / 任务），白底整页文字只剩弹出提示。
* 统一控件：胶囊按钮（浅蓝灰 → 选中变青绿 + 橘色 ▶）、`UIKit.toggle_pill()` 开关、`GW.slider()`（粗轨道 + 大圆钮）、键帽、圆形头像（粗白底盘 + 平滑遮罩，参考暂停键）。
* 弹窗：欢迎窗 = 斜切面板 + 压在上沿的标题彩带 + 弹跳的排球徽章；暂停 = 模糊背景 + 一摞药丸（声音与提示是第二页）。

性能约束（这一轮的硬性要求）：所有形状只在 `_draw()` 里画一次（无逐帧重绘），没有 `clip_children`（头像原来用它，会多一次离屏通道，现在改成一个共享的 `shaders/ui_circle_mask.gdshader`），模糊只在暂停时才读屏幕纹理，加载页 / 热血条 / 球形徽章是仅有的逐帧重绘。小米手机实测见 22.5。

### 22.2 落点提示：要不要在己方半场显示？（设计结论）
**结论：要，但只显示「你该站到哪里」，而且默认只显示一个。**

理由与风险：
* 低机位、从底线后方看球场时，**深度很难判断**（球高度与落地距离混在一起），一个地面标记能把「深度判断」变成「反应时机」，对新手和手机触屏玩家价值最大。参考作品靠自动跑位 + 「Next: 垫球」提示 + 脚下光圈解决，我们的自动跑位可关，所以需要这个。
* 风险是**信息过载**：球速快、画面里已有球拖尾、时机圈、击球圈、弹字。所以不做「每个球都画落点」。

设计（`Vfx._update_marks`，设置里「落点提示」三档）：
| 档位 | 内容 |
|---|---|
| 关闭 | 什么都不画（老玩家） |
| **简洁（默认）** | 只给**球要落到己方、且由你来接**的那一个球画一个白色圆环（接球高度处的站位点，不是地面落点）；球出手后才出现，离接触 0.1 秒前消失；预计出界时变红；对方半场的球、队友要接的球都不画 |
| 标准 | 在简洁基础上加：圈内有一个**收拢的内圈**（剩余时间 1.2 s → 接触），队友要接的球画一个淡圈（避免你跑错位置） |

新手（教学未完成且比赛 < 3 场，且没手动选过档位）自动用「标准」，之后回落到「简洁」。所有标记只有 2 个四边形网格，几乎没有成本。**需要真人试玩验证**：圈的大小、出现时机（球出手 0.08 s 后）、是否遮挡脚下的击球圈。

### 22.3 本地化（`scripts/core/loc.gd`、`loc_en.gd`、`tools/test_loc.gd`）
* 源语言是中文（代码里的字符串就是 key），英文表在 `loc_en.gd`（一行 `中文<TAB>English`，`\n` 表示换行）。
* `Loc.EnTranslation` 继承 `Translation` 并重写 `_get_message()`：先精确匹配，再用 `%d / %s / %.2f` 模板匹配（所以先格式化再赋给 Label 的字符串，如「5 连击」也能翻译，`%s` 捕获的内容递归翻译），最后按「 · / / 」分段翻译；结果带缓存。Label / Button / RichTextLabel 自动翻译；`draw_string` / 拼接富文本处用 `Loc.t()`；操作说明长文用 `Loc.howto()`。
* 设置里「Language / 语言」：自动（跟随系统，`zh*` 为中文，否则英文）/ 中文 / English，切换后重载菜单。
* **新增文字的流程**：写中文 → 在 `loc_en.gd` 加一行英文 → 跑 `godot --headless --path . -s tools/test_loc.gd`（检查重复 key、残留中文、模板）→ 跑 `-- --lang=en --audit=<帧数>`（遍历场景树，列出翻译后仍含中文的控件）。
* 目前英文版本已审计：菜单各页、生涯三页、对局 HUD、教学、回合挑战、结算、VS 卡全部 0 残留。

### 22.4 字体推荐
当前 `assets/fonts/ui_font.ttf`（字魂趣圆黑）是**试用版，商用需授权**。建议换成下面这些**可商用**的字体（下载前请再核对各自许可证原文）：

| 用途 | 英文 | 中文 |
|---|---|---|
| UI 正文 / 数字 | **Fredoka**（Google Fonts，OFL，圆润友好，最接近任天堂体育类的气质）；备选 Nunito、Quicksand | **寒蝉全圆体 / 寒蝉圆黑体**（OFL，基于思源黑体的圆体，字重齐全，覆盖全，首选）；备选 站酷快乐体（OFL，偏卡通） |
| 大标题 / 横幅（VS、胜利、Match Point） | **Lilita One**（OFL，粗壮的运动海报感）；备选 Baloo 2、Luckiest Guy | **得意黑 Smiley Sans**（OFL，斜体运动感，很适合斜切彩带）；备选 优设标题黑（作者声明可免费商用）、站酷快乐体 |
| 稳妥兜底 | Noto Sans | 思源黑体 / Noto Sans SC（OFL） |

搭配建议：**UI 用 Fredoka + 寒蝉全圆体，标题用 Lilita One + 得意黑**。接入方式：
1. 中文字体覆盖 `assets/fonts/ui_font.ttf`；
2. 英文字体放到 `assets/fonts/ui_font_en.ttf`（可选，`Game._make_font()` 会让它接管所有拉丁字符，中文字体作为后备）；
3. 完整中文字体 5–20 MB，用 `python tools/subset_font.py <原字体> <输出.ttf>` 裁成只含游戏用到的字符（实测当前字体 2.1 MB → 160 KB），手机包体和内存都会好很多；新增中文后重新跑一遍。

### 22.5 其它小细节
头像换成粗白底盘 + 平滑圆形遮罩（和暂停键同一套语言）；热血条改成带高光的药丸 + 尖端光点；手机击球键随「垫球 / 传球 / 扣球 / 发球」变化并随来球脉动；提示条第二行说明在熟练后（教学完成或 ≥ 3 场）自动隐藏；暂停菜单永远置顶、默认聚焦「继续比赛」，支持键盘 / 手柄导航。

### 22.6 图标（Gemini 生成 + `tools/key_icon.py` 抠色，原图与提示词在 `art_src/gemini/`）
* `assets/ui/act_jump.png`：新的「跳跃」白色小人图标（与 act_bump / set / spike / block / serve / dive 同一风格，以 act_block 为风格参考）。
* `assets/ui/emb_flame.png`（热血条火焰）、`emb_trophy.png`（锦标赛冠军：结算页两侧、生涯纪录）、`emb_lock.png`（生涯收藏里未解锁的装扮）：贴纸风的彩色徽章，`UIKit.emblem()` / `UIKit.emblem_rect()` 读取；文件缺失时自动回退到程序绘制，不会报错。
* **手机动作按钮**（`TouchControls`）：文字全部换成图标。击球键的图标随情境变化（垫球 / 传球 / 扣球 / 发球 / 拦网，换图标时有一个弹跳），跳 = act_jump，扑救 = act_dive；按钮是带高光、深色底边、按下会下沉的「街机大按钮」，来球时击球键外圈脉动。
* 提示：生成脚本 `art_src/gemini/gen_round2_icons.ps1`，调用间隔 ≥ 28 秒，遇到 Google 的 "Sorry" 页面不要重试。

## 23. 第五轮：轻微扁平化 + 更贴近 Switch Sports 的菜单质感（2026‑10‑04）

**风格方向（用户要求）：轻微扁平化。** 保留圆角、白色描边和斜切，去掉重的渐变高光、条纹和大面积柔和阴影：
* `shaders/ui_pill.gdshader`：几乎纯色（渐变 5 %、无高光带），描边 3 px，阴影短而淡；选中态才有很淡的斜条纹。
* `GW.board()` / `GW.ribbon()`：纯色面板，硬而短的阴影，不再有高光带；`UIKit.style_box()` 的阴影统一缩短 / 变淡。
* `shaders/ui_frost.gdshader`：毛玻璃面板（模糊的场景 + 淡色罩），极淡的水印圆环，细白边。
* 手机动作按钮：纯色圆面 + 白描边 + 深色底边，不再有高光弧。

**页面（参考 Game UI Database 的 Switch Sports 截图）：**
| 页面 | 做法 |
|---|---|
| 主菜单 | 左侧淡色渐变罩 + 斜体 Logo「Go Sports」+ 三条彩色掠影线；`MenuEntry`（`ui/menu_entry.gd`）倾斜 3.5° 的大胶囊：图标徽章 + 标题 + 副标题 + 右侧人数标签，选中变青绿 + 淡斜条纹 + 橘色 ▶；右上角等级胶囊 + 毛玻璃「今日任务」 |
| 选择模式 / 比赛设置 | 左：三个模式条（选中常亮青绿）；右：毛玻璃面板，头像 VS 行 + `GW.option_row()`（「标签 ◀ 选项 ▶」，选中项是青绿胶囊，下方青绿细线） |
| 设置 | 左侧分类（声音 / 画面 / 操作 / 语言）+ 右侧毛玻璃面板（面板高度随行数变化），另有「制作与素材」 |
| 页眉 | `GW.header()`：图标 + 描边标题 + 白色细线和圆点，替代斜切彩带（彩带只留给弹窗 / 结算 / 练习卡片） |
| 结算 | 毛玻璃面板（浅底深字）+ 顶部大彩带「胜利!」，分区小彩带，按钮同一套胶囊 |

**开场 VS 卡（电视直播机位）**：显示**整个球场和球网**，摄像机在**我方半场底线斜后方**低机位斜向拍摄，带一段慢推镜头（3.4 秒，`CameraRig._vs`，`--vscam=x0,y0,z0,x1,y1,z1,fx,fy,fz,fov` 可调）；我方两人在前景、四分之三转向镜头，对手隔网站在远处面向我们；比赛球在 VS 期间隐藏。叠加直播感元素：黑边、左上角闪烁的红色 LIVE 标、球员名牌（称号 + 名字），斜线分割的淡色罩按我方球员在屏幕的哪一侧自动对齐（我方蓝、对手粉）。VS 卡 / 回放转场 / 欢迎提示都按真实视口大小排版（宽屏手机不会被裁掉）。

**开始游戏**：模式页右下角是一个大号、脉动、默认聚焦的「开始游戏」按钮（带「下一步：选择你的角色」提示），回车 / 手柄 A 直接确认。手机上毛玻璃面板改成半透明纯色面板（`GW.frost` 的移动端回退），因为 `hint_screen_texture` 每帧复制后台缓冲，在测试手机上要多 ~8 ms GPU。

**落点提示**（`Vfx._update_marks`）已实现并验证：日志里站位点、剩余时间、档位都正确（`--dbgmark` 打印），截图里「简洁」档的白圈出现在接球点；圈的大小 / 出现时机还需真人试玩调。

## 24. 第六轮：启动画面、环绕式球队介绍、场馆广告牌、高座裁判、判线 UI、操作说明重做（2026‑10‑04）

**启动画面**（`tools/make_splash.py` 生成 `assets/ui/splash.png` + `icon.png`）：Godot 默认的 logo + 深蓝底换成我们自己的天蓝底 + 排球 + 斜体 Logo；`project.godot` 里 `boot_splash/*`、`config/icon`。进入菜单时 `Main` 先用同一种天蓝色盖住画面再淡出（`_fade`），启动画面 → 菜单是连续的。

**球队介绍（VS 机位，电视直播环绕）**：
* 取消中间的斜线分割与左右着色；两队整齐站成两排（`MatchDirector._vs_pose`：都朝 +x 看向摄像机一侧，对手 z=−3.3/−5.5，我方 z=+3.3/+5.5），中间是球网和大「VS」。
* 摄像机（`CameraRig._vs_pose`，`VS_DUR`=4.4 s）绕场中心的一段弧：φ −48°→+34°，半径 10.6 m，高度 1.9→2.5 m（中段微微升高并拉近），焦点 z −4.3→+4.4；smootherstep，在两队前面各停留一下；`--vscam=phi0,phi1,半径,高,fov` 可调试。
* **最后落点在我方一侧**：弧的终点就是我方二人组正前方；`CameraRig.intro()` 在 `vs` 模式下以当前机位为起点滑向比赛机位（不再跳切）。
* 名牌（`VsCard`）改为每帧跟随球员投影位置（UI 同款胶囊：队色 + 称号 + 名字），对手先出现，我方后出现；球员离开画面边缘就隐藏，不会堆在屏幕边上。

**判线（In / Out）UI**：`HUD._inout_pill` 做成广播式徽章——青绿 IN / 珊瑚 OUT，圆盘 ✓ / ✗ 图标、大写文字、指向落点的小尖角；压线（< 10 cm）显示「压线球!」，< 50 cm 显示「差 / 仅余 N cm」；IN 弹跳、OUT 摇头。3D 部分 `Vfx.line_call`：落点处同色涟漪 + 球印，OUT 有红叉，险球让最近的那条边线闪三下。开发开关 `--callshot=in|out|inclose|outclose`。

**场馆**（`Arena`）：
* 球场四周的绿色灌木（几百个交叉面片）换成 **LED 广告隔板**：深色底座 + 彩色压顶 + 轮播广告面（`tools/make_ads.py` → `assets/env/ads.png`，16 块虚构品牌，4×4 图集）。所有广告面是**一个网格 + 一个 shader**（`shaders/ad_board.gdshader`：顶点色里存图集格号和相位，每 7 秒按 5 的步长换下一块，换屏时一条扫描线），底座也是一个顶点色网格 → 全场 2 个 draw call，比原来的灌木还省；内外两面都有广告，环绕机位从场外看也不是白板。
* **场馆外观**（`Arena.LOOKS`，随 `Profile.COURTS` 解锁）：除了天空 / 灯光预设，现在每个场馆有自己的球场配色（shader 颜色）、地台边、隔板底座 / 压顶颜色和亮度（夜场的 LED 更亮）。四个场馆：晴空日场 / 黄昏（紫橙）/ 灯光夜场（蓝）/ 薄雾清晨（薰衣草）。
* **选择场馆**：模式页「球场」一行四张贴纸卡（`MenuScreen._fill_venue_row`，预览复用生涯里的 `_Swatch`），未解锁的显示 Lv.N；点击即装备（和生涯里是同一个存档字段）。

**高座裁判**（`scripts/match/referee.gd`，`class_name Referee`）：
* 每场随机一只**动物**（Roster 里除人类外的 cube 角色；`--ref=<id>` 指定）坐在网柱旁的高椅上（x=−6.6，椅子是一个顶点色合并网格；球员被挡在椅子外面，`Athlete._clamp_to_court`）。
* 整个上半身**跟着球转头**（半衰期 0.14 s，±60°，VS 镜头里看着球网）。
* 动作是烘焙进 cube 动画库的 16 个 `ref_*` 片段（`ClipDefs`，坐姿 `rsit` 为基础）：idle 扫视、哨子、指向得分方、出界双手举、摇头、叹气、欢呼、惊讶、哈欠、擦汗、点头、托腮思考、挥手、耸肩、打瞌睡。
* 反应表：发球 → 吹哨；得分 → 指向得分一侧（右手 = +z = 蓝队）；出界 → 举手；触网 / 发球失误 → 摇头 / 耸肩；ACE / 比赛结束 → 欢呼；险球 → 托腮；大力扣球 / 拦死 / 触网 → 惊讶（9 秒冷却，保持稀有）；长回合（≥ 9 次）之后擦汗；平静时每 10–18 秒随机来一个搞怪动作（哈欠 / 擦汗 / 耸肩 / 叹气 / 挥手 / 点头）；34 秒什么都没发生就睡着，下一个事件把它惊醒。`--log` 会打印 `[ref]`，`--refclip=<clip>` + `--refcam=px,py,pz,fx,fy,fz,fov` 用来单独看一个动作。

**操作说明页重做**（`scripts/ui/howto_page.gd`）：左边 5 个话题胶囊（`MenuEntry`，和设置页同一套），右边毛玻璃面板：控制方式用「动作标签 + 键帽」行（双人并排、手柄有彩色 ABXY 圆键、触屏用动作图标 + 圆盘），规则 / 技巧 / 成长用「彩色标签 + 一句话」行和三枚规则徽章；不再是整块文字。英文翻译按行写进 `loc_en.gd`（旧的整块 `HOWTO` 常量已删除）。`--howtab=N` 直接打开某个话题。

**验证**：check_scripts 66 个脚本通过、`test_loc` 通过、`--lang=en --audit` 在操作说明 5 个话题上 leftovers=0；solo humanbot + `--vs --replay`、training、rally、autoplay 回归无脚本错误。
