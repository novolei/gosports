# English strings (edit here). The source language of the game is Chinese: every key is the exact Chinese text used in the code.
class_name LocEn
extends RefCounted
## A backslash-n in a line stands for a real line break. %d / %s / %.2f placeholders keep their order.

const TABLE := r"""
轻松	Easy
普通	Normal
困难	Hard
大师	Master
单人对战	Solo Match
双人合作	Co-op
双人对决	Versus
新手教学	Tutorial
回合挑战	Rally Challenge
锦标赛	Tournament
左移	Move Left
右移	Move Right
上移	Move Up
下移	Move Down
击球	Hit
跳跃 / 拦网	Jump / Block
扑救	Dive
小组赛	Group Stage
半决赛	Semifinal
决赛	Final
速度彩带	Speed Ribbon
颜色随球速变化	Color follows ball speed
星光	Stardust
金白色的星尘拖尾	A trail of golden stardust
队色	Team Color
跟随你的队伍颜色	Matches your team color
樱吹雪	Sakura
粉白渐变的花瓣	Pink-to-white petals
彩虹	Rainbow
七彩渐变	A seven-color gradient
烈焰	Blaze
红橙色的火焰	Red-orange flames
寒霜	Frost
冰蓝色的冷光	Icy blue glow
经典黄蓝	Classic
标准比赛用球	The standard match ball
沙滩球	Beach
暖黄色的沙滩风格	Warm beach style
霓虹	Neon
青色荧光	Cyan glow
糖果	Candy
粉嫩甜甜的颜色	Sweet pastel pink
黄金	Gold
金灿灿的冠军球	A shiny champion's ball
午夜	Midnight
深蓝色的夜场用球	Deep blue for night games
晴空日场	Sunny Day
明亮的白天	A bright afternoon
黄昏	Sunset
金色的夕阳	Golden evening light
灯光夜场	Floodlit Night
璀璨的夜间比赛	A glittering night match
薄雾清晨	Misty Dawn
粉蓝色的清晨	A pink and blue morning
新手	Rookie
球场新星	Rising Star
校队候补	Reserve
校队主力	Starter
区域好手	Local Ace
地区冠军	District Champ
省队选手	State Player
国家队后备	National Reserve
国手	National Player
传奇	Legend
初战告捷	First Blood
赢得第一场比赛	Win your first match
常胜将军	Winning Streak
累计赢得 10 场比赛	Win 10 matches
节奏大师	Rhythm Master
累计 30 次 Nice! 击球	Land 30 Nice! hits
完美主义	Perfectionist
累计 200 次 Nice! 击球	Land 200 Nice! hits
十连不倒	Ten in a Row
单回合 10 次触球	10 touches in one rally
拉锯大战	Long Haul
单回合 25 次触球	25 touches in one rally
三连默契	In Sync
完成一次垫传扣全 Nice! 的强力扣球	Bump, set and spike all with Nice! for a power spike
扣杀之王	Spike King
累计 10 次强力扣球	10 power spikes
发球机器	Serve Machine
累计 5 个 ACE	5 aces
铜墙铁壁	Iron Wall
累计 5 次拦网得分	5 points from blocks
头晕目眩	Seeing Stars
把队友或自己撞得眼冒金星	Bump into someone hard enough to see stars
热血沸腾	Fired Up
触发一次热血时刻	Trigger a Fever Time
燃烧吧!	Burn Baby Burn!
累计触发 10 次热血时刻	Trigger Fever Time 10 times
绝地反击	Comeback Kid
落后 5 分以上后逆转获胜	Win after trailing by 5 or more
完美零封	Shutout
不让对手得分赢下比赛	Win without conceding a point
合格新人	Graduate
完成新手教学	Finish the tutorial
回合达人	Rally Pro
回合挑战中拿到金牌	Earn gold in Rally Challenge
锦标赛冠军	Champion
夺得一次锦标赛冠军	Win a tournament
三天打卡	Three Days Running
连续 3 天登录	Log in 3 days in a row
十级球员	Level 10
达到 10 级	Reach level 10
赢得 %d 场比赛	Win %d matches
完成 %d 次 Nice! 击球	Land %d Nice! hits
扣杀得分 %d 次	Score %d points with spikes
单回合达到 %d 次触球	Reach %d touches in one rally
发出 %d 个 ACE	Serve %d aces
拦网得分 %d 次	Score %d points with blocks
触发 %d 次热血时刻	Trigger Fever Time %d times
完成 %d 次强力扣球	Land %d power spikes
完成 %d 场比赛	Play %d matches
铜牌	Bronze
银牌	Silver
金牌	Gold
参赛奖励	Participation
得分 %d	Points scored %d
精彩表现	Great Play
胜利	Victory
难度	Difficulty
加时	Overtime
默契	Teamwork
连续登录	Login Streak
最长回合 %d	Longest rally %d
累计触球 %d	Total touches %d
练习	Practice
小M	M
元气满满的队长	A full-of-energy captain
阿宝	Bao
弹跳力惊人	Incredible jumper
小樱	Sakura
发球超准	Pinpoint server
熊大	Bear
力量型扣杀手	Power spiker
盼盼	Panda
稳如泰山的防守	Rock-solid defense
雪球	Snowy
反应敏捷	Lightning reflexes
灰灰	Grey
神出鬼没	Seems to be everywhere
旺财	Lucky
跑得飞快	Fast as the wind
柴柴	Shiba
永不放弃	Never gives up
兔兔	Bunny
跳得最高	Highest jumper
栗子	Chestnut
二传好手	Great setter
猴哥	Monkey
花样百出	Full of tricks
小黄	Ducky
嘎嘎嘎	Quack quack quack
绿头	Mallard
水上飘	Floats on air
大吉	Rooster
大吉大利	Lucky day
小鹿	Fawn
优雅步伐	Graceful footwork
河马	Hippo
憨憨拦网	Goofy blocker
犀牛	Rhino
冲撞王	Charging king
麋鹿	Moose
长臂拦网	Long-armed blocker
鳄鳄	Croc
咬住不放	Never lets go
红影	Red Ninja
疾风般的突击	A lightning strike
蓝影	Blue Ninja
冷静的二传	A calm setter
紫影	Purple Ninja
神秘的拦网手	A mysterious blocker
黑影	Black Ninja
暗夜扣杀	Spikes from the dark
铁壁	Iron Wall
拦网更容易得分，不容易被撞倒	Blocks score more often and the body is harder to knock down
疾风	Gale
Nice! 击球后短暂加速	A brief speed boost after a Nice! hit
鹰眼	Eagle Eye
击球时机判定窗口更宽	A wider timing window
怪力	Might
扣杀更难被拦网拍死	Spikes break through blocks more often
灵巧	Agile
扑救更远，起身更快	Longer dives and quicker recovery
鼓舞	Morale
队伍热度积累更快	Builds team hype faster
稳健	Steady
普通击球更精准	Plain hits are more accurate
准备!	Ready!
早了!	Too early!
晚了!	Too late!
快速扣杀!	QUICK!
扣杀!	SPIKE!
吊球	Tip
触网	Net touch
发球失误	Service fault
得分!	Point!
出界	Out
赛点	Match Point
比赛结束!	Game Set!
练习结束!	Session over!
垫球	Bump
垫球接发 ×3	Receive with bumps ×3
球落到[b]脚下的圈[/b]里时按 [b]击球键[/b]，时机圈缩到最小时最准!	When the ball drops into the [b]ring at your feet[/b], press [b]Hit[/b]. It is most accurate when the timing ring is smallest!
传球	Set
传球 ×3	Set ×3
让队友先接球，你站在[b]网前[/b]，球飞过来时按 [b]击球键[/b] 传球	Let your partner receive first. Stand [b]near the net[/b] and press [b]Hit[/b] to set when the ball arrives
扣球	Spike
扣球 ×3	Spike ×3
队友传球后，球在高处时按 [b]击球键[/b]，会自动[b]起跳扣杀[/b]	After your partner sets, press [b]Hit[/b] while the ball is high and you will [b]jump and spike[/b] automatically
完美时机	Perfect Timing
打出 3 次 Nice!	Land 3 Nice! hits
击球圈缩到[b]最小[/b]的那一刻按键，就是 [b]Nice![/b]	Press the button the moment the ring is [b]smallest[/b] and that is a [b]Nice![/b]
连续对打	Keep It Going
连续 8 次触球	8 touches in a row
多接球、多传球，[b]不要急着扣杀[/b]，把回合打长	Keep receiving and setting. [b]Don't rush the spike[/b], make the rally long
球拖尾	Ball Trail
比赛用球	Match Ball
球场主题	Court Theme
%d 分钟	%d min
%d 小时 %d 分	%d h %d min
生涯	Career
概览	Overview
收藏	Collection
成就	Achievements
返回	Back
经验 %d / %d	XP %d / %d
已满级!	Max level!
比赛	Matches
%d 场	%d
胜场	Wins
胜率	Win rate
得分	Points
拦网得分	Block points
Nice! 击球	Nice! hits
强力扣球	Power spikes
最长回合	Longest rally
%d 次	%d
撞晕次数	Knock-downs
热血时刻	Fever Time
游玩时间	Play time
今日任务	Daily Missions
%d / %d 完成	%d / %d done
连续登录 %d 天  ·  全部经验 ×%.2f  (连续 5 天达到上限 ×1.25)	%d-day login streak  ·  all XP ×%.2f  (caps at ×1.25 after 5 days)
下一个解锁	Next Unlock
所有装扮都已解锁!	Everything is unlocked!
Lv.%d 解锁  ·  还差 %d 经验	Unlocks at Lv.%d  ·  %d XP to go
我的纪录	My Records
%d 次触球 (%s)	%d touches (%s)
%d 次触球	%d touches
尚未参加	Not played yet
通过小组赛	Cleared the group stage
进入决赛	Reached the final
冠军!	Champion!
已毕业	Graduated
未完成	Not finished
装扮收藏	Collection
点击已解锁的装扮即可装备;升级解锁更多。拖尾只在你方击球时显示。	Click an unlocked item to equip it; level up to unlock more. The trail only shows on your team's hits.
使用中	Equipped
点击装备	Click to equip
Lv.%d 解锁	Lv.%d
%s — 达到 Lv.%d 解锁（还差 %d 经验）	%s — unlocks at Lv.%d (%d XP to go)
已解锁 %d / %d	Unlocked %d / %d
锦标赛 · %s  (%d/%d)	Tournament · %s  (%d/%d)
发球	Serve
成就解锁: %s	Achievement: %s
%s   +%d 经验	%s   +%d XP
每日任务完成!	Daily mission complete!
升级! Lv.%d	Level up! Lv.%d
继续比赛来解锁更多拖尾 / 球 / 球场	Keep playing to unlock more trails, balls and courts
拦网	Block
热血时刻!	FEVER TIME!
次触球	touches
最佳 0	Best 0
教学完成!	Tutorial complete!
全部完成	All done
[color=#e0307f]教学完成![/color]  马上结算奖励…	[color=#e0307f]Tutorial complete![/color]  Tallying your rewards…
毕业!	Graduated!
失误!  %d 连击	Miss!  %d in a row
%d 连击!	%d in a row!
最佳 %d	Best %d
%s达成!	%s earned!
回合连续 %d 次触球  +%d 经验	%d touches in one rally  +%d XP
暂停	Paused
继续比赛	Resume
音乐	Music
音效	Sound
自动跑位辅助	Auto-positioning
击球时机提示圈	Timing ring
切换镜头 (C)	Switch camera (C)
重新开始本局	Restart match
更改比赛设置	Match settings
退出到主菜单	Quit to menu
左侧滑动移动  ·  右侧按钮 击球 / 跳 / 扑  ·  点击对面场地设定落点	Left: drag to move  ·  Right: Hit / Jump / Dive  ·  Tap the far court to set your target
左摇杆	L Stick
移动	Move
跳跃	Jump
右摇杆	R Stick
瞄准	Aim
%s / 左键	%s / L-Click
%s / 右键	%s / R-Click
鼠标	Mouse
开始!	Start!
锦标赛 · %s	Tournament · %s
先得 %d 分获胜!	First to %d points wins!
连击 %d	Rally %d
早	Early
你的时机…	Your timing was…
有点早!	a bit early!
有点晚!	a bit late!
排球  ·  %s	Volleyball  ·  %s
胜利!	Victory!
A 队获胜!	Team A wins!
B 队获胜!	Team B wins!
再接再厉!	Better luck next time!
按 %s 抛球，再按一次击球（先按跳跃可跳发）	Press %s to toss, then again to hit (press Jump first for a jump serve)
击球!	Hit!
球到最高点时按 %s	Press %s at the top of the toss
下一步: 垫球	Next: Bump
下一步: 传球	Next: Set
下一步: 扣球	Next: Spike
下一步: 扑救	Next: Dive
圈内球靠近时按 %s	Press %s as the ball reaches the ring
起跳后在最高点按 %s 扣杀	Jump, then press %s at the top to spike
按 扑救键 飞身救球	Press Dive to fly for it
下一步: 拦网	Next: Block
在网前按 %s 起跳，举手拦网	Press %s at the net to jump and block
跳	Jump
下一步	Next
下一步:	Next:
击球键	Hit button
%s / 鼠标左键	%s / Left Click
先按 [p]击球键[/p] 把球抛起，球到 [t]最高点[/t] 时再按一次击球。先按跳跃键还能 [p]跳发球[/p]!	Press [p]Hit[/p] to toss the ball, then press it again at the [t]top[/t]. Press Jump first for a [p]jump serve[/p]!
时机	Timing
球上的圆圈缩到 [t]最小[/t] 的那一刻按键，就是 [p]Nice![/p]：球更快、更准。	Press when the ring on the ball is [t]smallest[/t] for a [p]Nice![/p]: faster and more accurate.
垫传扣	Bump-Set-Spike
每队最多触球 [p]3 次[/p]：垫球 → 传球 → 扣球，同一个人不能连续触球。	A team gets [p]3 touches[/p]: bump → set → spike, and nobody can touch twice in a row.
对方把球传高时，在网前 [p]起跳[/p]，手臂伸过网就能把球 [t]拦回去[/t]。	When the other side sets high, [p]jump[/p] at the net and reach over to [t]block it back[/t].
连续的 Nice! 会攒满 [p]热血条[/p]：判定变宽，扣球更有力，球还会拖着火焰!	Chained Nice! hits fill the [p]fever bar[/p]: a wider window, stronger spikes and a flaming ball!
垫、传、扣 [p]三次全是 Nice![/p]，就能打出几乎拦不住的 [t]强力扣球[/t]。	Land [p]Nice! on all three[/p] touches for a nearly unblockable [t]power spike[/t].
够不到的低球，按 [p]扑救键[/p] 飞身去接；落点圈会告诉你球落在哪里。	For low balls out of reach, press [p]Dive[/p]. The ring shows where it lands.
扣球时把瞄准点放在 [p]靠近球网[/p] 的位置，球就会变成轻轻的 [t]吊球[/t]。	Aim [p]close to the net[/p] when you spike and it becomes a soft [t]tip[/t].
快速扣球	Quick Spike
在队友传球之前就 [p]起跳[/p]，传球会变成又低又快的 [t]QUICK[/t] 球。	[p]Jump[/p] before your partner sets and the set turns into a low, fast [t]QUICK[/t] ball.
别撞人	Mind Your Partner
跑动时撞到队友会被弹开，撞得狠还会 [p]摔倒[/p]。叫位置、留空间。	Running into your partner knocks you apart, and hard hits make you [p]fall[/p]. Call the ball and leave room.
鼠标指向对方场地的 [t]落点[/t]，球就打向那里；手柄用 [p]右摇杆[/p]。	Point the mouse at a [t]spot[/t] on the other court and the ball goes there; on a gamepad use the [p]right stick[/p].
自动跑位	Auto-positioning
开启 [p]自动跑位辅助[/p] 后，球来时角色会自己跑向落点，你只管 [t]击球时机[/t]。	With [p]auto-positioning[/p] on your character runs to the landing spot and you only worry about the [t]timing[/t].
小技巧 · %s	Tip · %s
正在准备比赛…	Getting the match ready…
该按键原本属于「%s」，两者已互换	That key was bound to "%s", so the two were swapped
选择	Select
确定	OK
方向键 / 鼠标	Arrows / Mouse
Enter / 点击	Enter / Click
排球	Volleyball
Volleyball · 2v2 · 键鼠 / 手柄 / 触屏	Volleyball · 2v2 · Keyboard / Gamepad / Touch
开始比赛	Play
练习场	Practice
生涯  ·  装扮  ·  成就	Career  ·  Style  ·  Awards
操作说明	Guide
设置	Settings
退出	Quit
F11 全屏	F11 Fullscreen
%d/%d  ·  连续 %d 天	%d/%d  ·  %d-day streak
教练带你一步步学会\n垫球、传球和扣球\n完成可得 100 经验	A coach walks you through\nbumping, setting and spiking\nFinish it for 100 XP
推荐新手先来这里	Start here if you are new
和发球机连续对打\n接球失误 3 次就结束\n铜 10 · 银 25 · 金 50	Rally against a ball machine\nThree misses and it's over\nBronze 10 · Silver 25 · Gold 50
最佳 %d 次 (%s)	Best %d (%s)
最佳 %d 次	Best %d
欢迎回来!  连续登录 %d 天	Welcome back!  %d-day login streak
今日 3 个新任务已刷新   全部经验 ×%.2f	3 new daily missions   all XP ×%.2f
欢迎来到排球!	Welcome to Volleyball!
第一次玩?  先花 2 分钟跟着教练学会垫球、传球和扣球吧。\n完成教学有额外经验奖励,还能解锁更多球拖尾和球场!	First time? Spend two minutes with the coach learning to bump, set and spike.\nFinishing the tutorial gives bonus XP and unlocks more trails and courts!
开始新手教学	Start tutorial
直接开打	Jump in
(随时可以在「练习场」重新进入教学)	(You can replay the tutorial any time from Practice)
选择模式	Choose a mode
你 + 电脑队友  VS  电脑二人组	You + a CPU partner  VS  two CPU players
两位玩家同一队，一起对战电脑	Two players on one team against the CPU
两位玩家各带一名电脑，同屏对抗	Two players, each with a CPU partner, head to head
比赛设置	Match Settings
电脑难度	CPU strength
比赛分数	Points to win
7 分	7 pts
11 分	11 pts
15 分	15 pts
精彩回放	Instant replay
选择角色	Choose character
玩家1	Player 1
玩家2	Player 2
电脑	CPU
你	You
玩家1  选择角色	Player 1  Choose a character
速度	Speed
弹跳	Jump
力量	Power
随机	Random
玩家2  选择角色（队友）	Player 2  Choose a character (partner)
玩家2  选择角色（对手）	Player 2  Choose a character (opponent)
特性「%s」 %s	Trait "%s"  %s
队伍阵容	Line-up
随机换队	Shuffle CPU
开始比赛!	Start match!
开始锦标赛!	Start tournament!
A 队	Team A
B 队	Team B
玩家	Player
对手	Opponent
电脑 ⇄	CPU ⇄
音乐音量	Music volume
音效音量	Sound volume
画面质量	Graphics
低 (手机)	Low (phone)
中	Medium
高	High
触屏控制	Touch controls
自动	Auto
开启	On
关闭	Off
落点提示	Landing hint
简洁	Minimal
标准	Standard
左手模式（触屏按键镜像）	Left-handed mode (mirror touch buttons)
镜头震动	Camera shake
触觉震动（手机 / 手柄）	Haptics (phone / gamepad)
击球时机提示圈（球上的缩小圆环）	Timing ring (the shrinking ring on the ball)
全屏	Fullscreen
按键设置	Key Bindings
制作与素材	Credits
引擎	Engine
角色 / 忍者	Characters / Ninjas
Cubebrush「Simple Character Pack」及忍者模型（开发者提供的素材包）	Cubebrush "Simple Character Pack" and ninja models (asset packs supplied by the developer)
球场 / 体育场	Court / Stadium
「低面体育场套件」(4182) 及开发者提供的球模型	"Low-poly Stadium Kit" (4182) and the ball model supplied by the developer
音效 / 音乐	Sound / Music
全部为程序合成（tools/gen_audio.py）	All procedurally synthesized (tools/gen_audio.py)
图标	Icons
程序绘制，部分动作图标由 Gemini 生成后抠图	Drawn in code; some action icons were generated with Gemini and cut out
界面字体	UI Font
字魂趣圆黑（试用版，商用前需替换为已授权字体）	Zihun Quyuanhei (trial version; replace with a licensed font before commercial use)
灵感	Inspiration
界面节奏与操作提示的参考来自「任天堂 Switch Sports」排球的公开演示；所有素材均为原创实现，不使用任何官方资源	The pacing of the UI and control prompts were studied from public footage of Nintendo Switch Sports volleyball; everything here is an original implementation and uses no official assets
按键设置 (玩家1 键盘)	Key Bindings (Player 1 keyboard)
点一下按键，再按想要的新按键；Esc 取消。鼠标：左键击球，右键跳跃（固定）	Click an action, then press the new key; Esc cancels. Mouse: left button hits, right button jumps (fixed)
恢复默认	Reset
已恢复默认按键	Keys reset to default
按下新按键…	Press a new key…
操作说明 & 小技巧	How to Play & Tips
键盘 + 鼠标	Keyboard + Mouse
手柄	Gamepad
触屏	Touch
规则 & 技巧	Rules & Tips
节奏 & 成长	Rhythm & Growth
回放	Replay
轻触跳过	Tap to skip
按任意键跳过	Press any key to skip
练习结束	Session Over
挑战结束	Challenge Over
晋级!	Advance!
止步于此…	Knocked out…
败北…	Defeat…
获得经验	XP Earned
（本次不计入成长记录）	(This session is not saved to your progress)
成就 / 任务 / 奖励  +%d XP	Achievements / Missions / Bonus  +%d XP
新解锁	New Unlocks
拖尾	Trail
球	Ball
球场	Court
本场成就	Achievements
已完成	Done
ACE 发球	Aces
扣杀	Spikes
强力扣球 / 热血	Power spikes / Fever
回合数	Rallies
累计触球	Total touches
教学清单	Tutorial steps
再来一局	Play Again
下一轮: %s	Next round: %s
再次挑战	Try Again
重新挑战本轮	Retry this round
更换角色	Change Character
主菜单	Main Menu
已满级	Max level
扑	Dive
开	On
关	Off
新秀	Rookie
开始游戏	Start Game
下一步：选择你的角色	Next: choose your character
声音	Sound
调整音乐与音效	Music and sound effects
画面	Display
画质、全屏、镜头	Quality, fullscreen, camera
操作	Controls
按键、触屏、提示	Keys, touch, hints
语言	Language
单人 · 双人合作 · 双人对决	Solo · Co-op · Versus
三轮淘汰赛，夺冠拿大量经验	Three rounds, one title
新手教学 · 回合挑战	Tutorial · Rally Challenge
等级 · 装扮 · 成就 · 每日任务	Levels · Style · Awards · Daily missions
未解锁	Locked
声音与提示	Sound & Hints
%s!	%s!
%s ×%.2f	%s ×%.2f
"""

const HOWTO := [
"""[b][color=#1668c9]Player 1[/color][/b]
  Move  [b]W A S D[/b]　　Hit (bump / set / spike / serve)  [b]J[/b] or [b]Left Mouse Button[/b]
  Jump (jump / block)  [b]K[/b] / [b]Space[/b] / [b]Right Mouse Button[/b]　　Dive  [b]L[/b] / [b]Shift[/b]
  Aim  [b]Mouse pointer[/b] on a spot of the other court; in solo you can also aim with the [b]arrow keys[/b]　　Pause  [b]Esc[/b]

[b][color=#c42473]Player 2 (same keyboard)[/color][/b]
  Move  [b]Arrow keys[/b]　　Hit  [b]Numpad 1[/b] or [b],[/b]　　Jump  [b]Numpad 2[/b] or [b].[/b]　　Dive  [b]Numpad 3[/b] or [b]/[/b]
  Aim  [b]Numpad 8 4 5 6[/b]

[b]The Hit button is contextual[/b]: low ball → bump; ball overhead → set; in the air → spike; when serving, the first press tosses and the second hits.
If the ball is very high, just press Hit and your character jumps for the spike by itself.""",
"""[b]Gamepad (P1 = pad 1, P2 = pad 2)[/b]
  Move  [b]Left stick / D-pad[/b]　　Hit  [b]A[/b] or [b]RB / RT[/b]　　Jump  [b]B[/b] or [b]LB[/b]　　Dive  [b]X[/b] or [b]LT[/b]
  Aim  [b]Right stick[/b] (push where you want the ball to land on the other court; release for a smart landing)
  Pause  [b]Start[/b]

[b]Tips[/b]
  · The glowing ring on the floor is your "hit range". Press Hit when the ball is inside the ring and it lights up for a PERFECT.
  · To send the first touch straight over the net, aim forward with the right stick.""",
"""[b]Touch controls[/b]
  · Hold and drag anywhere on the left side: a [b]floating stick[/b] moves your character
  · Bottom right: the big [b]Hit[/b] button / [b]Jump[/b] / [b]Dive[/b]
  · Tap the other half of the court to place a [b]target marker[/b] (cleared after your hit; without one you get a smart landing)
  · Settings has a [b]left-handed mode[/b] (mirrored buttons)
  · With "Auto-positioning" on, your character runs to the landing spot when you leave the stick alone, so you only need to nail the timing!""",
"""[b]Basic rules[/b]
  · 2 vs 2. A team gets at most [b]3 touches[/b] (bump → set → spike) and nobody touches twice in a row.
  · A ball that lands inside the other court scores; out-of-bounds counts against the last team to touch it. First to [b]7 / 11 / 15[/b] points with a 2-point lead wins.
  · The team that scores serves; when serve changes, partners take turns.

[b]Tips[/b]
  · [b]Quick spike[/b]: jump before your partner finishes the set. The set turns into a low, fast "QUICK" ball that goes straight to you.
  · [b]Block[/b]: when the other side sets high, jump at the net; reach over and you can send it back (KILL BLOCK scores outright).
  · [b]Dive[/b]: use Dive for low balls you can't reach; the ring shows where it will land.
  · [b]Tip[/b]: aim close to the net when you spike for a soft tip over the block.
  · [b]Jump serve[/b]: after the toss press Jump first and hit in the air for more speed but less control.""",
"""[b]Timing (Nice!)[/b]
  · When the ball enters your hit range a shrinking ring appears on it: press Hit when it is smallest for a [b]Nice![/b], faster and more accurate.
  · Chained Nice! hits fill the [b]fever bar[/b] and start [b]Fever Time[/b]: a wider window, stronger spikes and a flaming ball!
  · Nice! on bump, set and spike = a [b]power spike[/b] (the ball turns pink and is nearly unblockable).

[b]Character traits[/b]  Every character has a trait (shown when you pick): some run faster, some block better. Pick what suits you.

[b]Don't collide![/b]  Running into someone knocks you apart, and a hard hit makes you fall and see stars for a moment. The CPU gets dizzy too.

[b]Progression[/b]
  · Every match and practice earns XP and levels, unlocking new ball trails / balls / court themes you can equip under "Career".
  · 3 random missions every day, a login streak boosts XP, and there are 20 achievements to collect.
  · "Tournament" runs three rounds (group stage → semifinal → final) with a big XP bonus for the title.
  · Rally Challenge in "Practice" awards bronze / silver / gold medals."""
]
