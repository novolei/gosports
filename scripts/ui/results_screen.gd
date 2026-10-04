extends Node
## Match results: winners celebrate on the court, losers sulk. A reward card counts up the XP (play / points / Nice! ...
## x win / difficulty / teamwork bonuses), fills the level bar, reveals unlocked cosmetics, achievements and today's
## missions. Variants for the practice modes and the tournament.

var stage: Stage
var ui: CanvasLayer
var _root: Control
var _reward: Dictionary = {}
var _rows: Array = []                  # reward line controls, revealed one by one
var _chips: Array = []
var _total_label: Label
var _bonus_label: Label
var _lv_circle: Label
var _lv_title: Label
var _bar: ProgressBar
var _bar_text: Label
var _unlock_cards: Array = []
var _shown_level := 1
var _tick_acc := 0.0
var _last_xp := 0
var _again: Button

# dark scoreboard palette (light text on a deep teal board instead of a white web card)
const T := Color(0.96, 0.98, 1.0)         # primary text
const T2 := Color(0.62, 0.78, 0.88)       # secondary text
const ACC := Color("ffe14a")              # accent / headings
const GOOD := Color("7dffb0")             # positive values
const BOARD := Color(0.06, 0.2, 0.32, 0.9)
const TRACK := Color(0.02, 0.1, 0.18, 0.55)


## dev preview (--screen=results): a made-up finished match with a reward computed on a throw-away profile
func _demo_data() -> Dictionary:
	var prof := Profile.new("user://profile_demo.json")
	prof.xp = 380
	prof.ensure_daily("2026-10-05")
	prof.bump("power_spikes")
	prof.mission_progress("perfects", 20)
	var stats := {"aces": [2, 1], "spikes": [7, 5], "blocks": [1, 0], "perfects": [14, 6], "longest": 17,
			"power_spikes": [1, 0], "knockdowns": [0, 1], "fever": [1, 0], "spike_points": [4, 2]}
	var reward := prof.finish_match({"won": true, "score": [11, 8], "difficulty": 2, "mode": "solo", "time": 420.0, "deuce": true,
			"stats": stats, "spike_points": 4})
	if Game.profile == null:
		Game.profile = prof
	return {"winner": 0, "score": [11, 8], "stats": stats, "mode": "solo", "reward": reward, "team_a": Game.team_a, "team_b": Game.team_b}


func setup(data: Dictionary) -> void:
	if data.is_empty() or not data.has("stats") and not data.has("practice"):
		data = _demo_data()
	stage = Stage.new()
	add_child(stage)
	ui = CanvasLayer.new()
	ui.layer = 5
	add_child(ui)
	var winner: int = data.get("winner", 0)
	var ids_a: Array = data.get("team_a", Game.team_a)
	var ids_b: Array = data.get("team_b", Game.team_b)
	stage.look(Vector3(1.4, 2.2, 8.2), Vector3(1.4, 1.1, 1.5), true)
	stage.sway = 1.4
	var win_ids: Array = ids_a if winner == 0 else ids_b
	var lose_ids: Array = ids_b if winner == 0 else ids_a
	var practice: bool = data.has("practice")
	for i in 2:
		var r := stage.add_rig(Roster.by_id(win_ids[i]), Vector3(-1.4 + i * 2.8, 0, 3.4), PI + (0.25 if i == 0 else -0.25), "cheer")
		r.scale = Vector3.ONE * float(Roster.by_id(win_ids[i])["scale"]) * 1.25
	for i in 2:
		var r2 := stage.add_rig(Roster.by_id(lose_ids[i]), Vector3(-3.0 + i * 6.0, 0, -0.8), PI + (0.3 if i == 0 else -0.3), "cheer" if practice else "sad")
		r2.scale = Vector3.ONE * float(Roster.by_id(lose_ids[i])["scale"]) * 1.0
	Sfx.crowd(false)
	var human_good := (winner == 0) or Game.mode == "versus" or practice
	Sfx.jingle("jingle_win" if human_good else "jingle_lose")
	_reward = data.get("reward", {})
	_prepare_tournament(data, winner)
	_build_ui(data, winner)
	if Game.main != null and Game.main.dev.has("log"):
		print("[results] mode=%s winner=%d score=%s xp=%s tournament_round=%d" % [Game.mode, winner, data.get("score", []), str(_reward.get("xp", "-")), int(Game.tournament["round"])])
	if Game.main != null and Game.main.dev.has("quit_on_results"):
		print("RESULTS SHOWN winner=", winner, " score=", data.get("score", []))
		await get_tree().create_timer(1.0).timeout
		get_tree().quit()
		return
	await get_tree().process_frame
	var vfx := Vfx.new()
	stage.add_child(vfx)
	await get_tree().process_frame
	vfx.confetti(Vector3(0, 0, 3.0), 120)
	if not _reward.is_empty():
		_play_reward()
	if Game.main != null and Game.main.dev.has("resultshot"):
		get_tree().create_timer(float(Game.main.dev.get("resultdelay", 7.0))).timeout.connect(func():
			get_viewport().get_texture().get_image().save_png(str(Game.main.dev["resultshot"]))
			get_tree().quit())
	if Game.main != null and Game.main.dev.has("autonext"):
		await get_tree().create_timer(float(Game.main.dev["autonext"])).timeout
		_again.pressed.emit()


## tournament: the final win pays a bonus and a trophy (added on top of the match reward)
func _prepare_tournament(data: Dictionary, winner: int) -> void:
	if Game.mode == "tournament" and Game.profile != null and Game.profile_enabled:
		var reached := int(Game.tournament["round"]) + (1 if winner == 0 else 0)          # 1 group stage cleared .. 3 champion
		if reached > int(Game.profile.flags.get("tournament_best", 0)):
			Game.profile.flags["tournament_best"] = reached
			Game.profile.save()
	if Game.mode != "tournament" or winner != 0 or _reward.is_empty() or Game.profile == null or not Game.profile_enabled:
		return
	if int(Game.tournament["round"]) < Game.TOURNAMENT_ROUNDS.size() - 1:
		return
	var r := Game.profile.grant_xp(150)
	Game.profile.bump("tournaments")
	_reward["bonus_xp"] = int(_reward["bonus_xp"]) + 150
	_reward["total_xp"] = Game.profile.xp
	_reward["level_after"] = r["level_after"]
	_reward["unlocks"] = (_reward["unlocks"] as Array) + (r["unlocks"] as Array)
	_reward["champion"] = true


# ------------------------------------------------------------------ layout
func _panel(pos: Vector2, size: Vector2, col := BOARD) -> Control:
	var b := GW.board(size, col, Color(1, 1, 1, 0.9), 0.02)
	b.position = pos
	return b


## small slanted section ribbon (replaces bold heading text)
func _sec(parent: Control, text: String, pos: Vector2, width := 250.0) -> void:
	var r := GW.ribbon(text, width, 56.0, UIKit.TEAL, 30)
	r.position = pos
	parent.add_child(r)


func _lbl(parent: Control, text: String, pos: Vector2, size: Vector2, fsize := 28, col := T, align := HORIZONTAL_ALIGNMENT_LEFT, outline := 0, ocol := Color.WHITE) -> Label:
	var l := UIKit.label(text, fsize, col, outline, ocol, align)
	l.position = pos
	l.size = size
	parent.add_child(l)
	return l


func _build_ui(data: Dictionary, winner: int) -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.add_child(_root)
	var mode: String = data.get("mode", Game.mode)
	var practice: bool = data.has("practice")
	var head_text := "胜利!"
	var col := UIKit.YELLOW
	if practice:
		if mode == "training":
			head_text = "教学完成!" if (data["practice"] as Dictionary).get("completed", false) else "练习结束"
		else:
			var medal := Profile.medal_for(int((data["practice"] as Dictionary).get("best", 0)))
			head_text = "%s!" % medal["name"] if not medal.is_empty() else "挑战结束"
			col = medal.get("color", Color("c8fff0")) if not medal.is_empty() else Color("c8fff0")
	elif mode == "versus":
		head_text = "A 队获胜!" if winner == 0 else "B 队获胜!"
	elif mode == "tournament":
		head_text = "冠军!" if (winner == 0 and _reward.get("champion", false)) else ("晋级!" if winner == 0 else "止步于此…")
	else:
		head_text = "胜利!" if winner == 0 else "败北…"
	if winner != 0 and not practice and mode != "versus":
		col = Color("9ab4e8")
	var head := UIKit.label(head_text, 140, col, 26, UIKit.INK)
	head.set_anchors_preset(Control.PRESET_CENTER_TOP)
	head.position = Vector2(-500, 8)
	head.size = Vector2(1000, 170)
	_root.add_child(head)
	UIKit.pop_in(head, 0.3, 0.5)
	# the three section titles of the board are ribbons, not bold text
	# big card on the right
	var card := _panel(Vector2(880, 178), Vector2(980, 770))
	_root.add_child(card)
	_build_reward_column(card)
	_build_info_column(card, data, mode, practice)
	_build_buttons(mode, winner)
	card.modulate.a = 0.0
	card.create_tween().tween_property(card, "modulate:a", 1.0, 0.35)


func _build_reward_column(card: Control) -> void:
	_sec(card, "获得经验", Vector2(24, 16))
	if _reward.is_empty():
		_lbl(card, "（本次不计入成长记录）", Vector2(34, 80), Vector2(420, 40), 24, T2)
		return
	var y := 84.0
	for ln in _reward["lines"]:
		var row := Control.new()
		row.position = Vector2(34, y)
		row.size = Vector2(430, 34)
		card.add_child(row)
		_lbl(row, String(ln["name"]), Vector2(0, 0), Vector2(310, 34), 25, T)
		_lbl(row, "+%d" % int(ln["value"]), Vector2(310, 0), Vector2(120, 34), 27, GOOD, HORIZONTAL_ALIGNMENT_RIGHT)
		row.modulate.a = 0.0
		_rows.append(row)
		y += 36.0
	# multiplier chips
	var chips := HFlowContainer.new()
	chips.position = Vector2(34, y + 8.0)
	chips.size = Vector2(430, 40)
	chips.add_theme_constant_override("h_separation", 8)
	chips.add_theme_constant_override("v_separation", 6)
	card.add_child(chips)
	for m in _reward["mults"]:
		var chip := Panel.new()
		chip.custom_minimum_size = Vector2(0, 36)
		chip.add_theme_stylebox_override("panel", UIKit.style_box(Color("ffe08a"), 18, 0, Color.WHITE, 4, 12))
		var cl := UIKit.label("%s ×%.2f" % [m["name"], float(m["mult"])], 20, Color(0.45, 0.25, 0.02))
		cl.position = Vector2(0, 0)
		cl.size = Vector2(136, 34)
		chip.custom_minimum_size = Vector2(136, 34)
		chip.add_child(cl)
		chips.add_child(chip)
		chip.modulate.a = 0.0
		_chips.append(chip)
	var chip_rows := ceili(float((_reward["mults"] as Array).size()) / 3.0)
	var ty := y + 12.0 + float(chip_rows) * 42.0
	_total_label = _lbl(card, "+%d XP" % int(_reward["xp"]), Vector2(34, ty), Vector2(430, 70), 56, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, 12, Color("e0902a"))
	_total_label.modulate.a = 0.0
	var extra := int(_reward.get("bonus_xp", 0))
	_bonus_label = _lbl(card, ("成就 / 任务 / 奖励  +%d XP" % extra) if extra > 0 else "", Vector2(34, ty + 68.0), Vector2(430, 30), 22, ACC)
	_bonus_label.modulate.a = 0.0
	# level bar
	var ly := ty + 108.0
	var circ := Panel.new()
	circ.position = Vector2(34, ly)
	circ.size = Vector2(92, 92)
	circ.add_theme_stylebox_override("panel", UIKit.style_box(Color("3aa8ff"), 46, 5, Color.WHITE, 8))
	circ.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(circ)
	_lv_circle = UIKit.label("", 40, Color.WHITE, 8, Color(0.05, 0.25, 0.5))
	_lv_circle.set_anchors_preset(Control.PRESET_FULL_RECT)
	circ.add_child(_lv_circle)
	_lv_title = _lbl(card, "", Vector2(142, ly - 2.0), Vector2(320, 36), 26, T)
	_bar = ProgressBar.new()
	_bar.position = Vector2(142, ly + 40.0)
	_bar.size = Vector2(318, 26)
	_bar.show_percentage = false
	_bar.add_theme_stylebox_override("background", UIKit.style_box(TRACK, 13, 2, Color(1, 1, 1, 0.5)))
	_bar.add_theme_stylebox_override("fill", UIKit.style_box(Color("ffb02e"), 13))
	card.add_child(_bar)
	_bar_text = _lbl(card, "", Vector2(142, ly + 66.0), Vector2(318, 28), 20, T2, HORIZONTAL_ALIGNMENT_RIGHT)
	var start_total := int(_reward["total_xp"]) - int(_reward["xp"]) - int(_reward.get("bonus_xp", 0))
	_last_xp = start_total
	_shown_level = int(Profile.level_info(start_total)["level"])
	_set_level_display(start_total)
	# unlock cards (appear when their level is reached)
	var ux := 34.0
	var uy := ly + 116.0
	var unlocks: Array = _reward["unlocks"]
	if not unlocks.is_empty():
		_sec(card, "新解锁", Vector2(24, uy - 10.0), 190.0)
		uy += 54.0
	var shown := 0
	for u in unlocks:
		if shown >= 3:
			break
		var it := Profile.item(String(u["kind"]), String(u["id"]))
		var uc := Panel.new()
		uc.position = Vector2(ux, uy)
		uc.size = Vector2(140, 104)
		uc.add_theme_stylebox_override("panel", UIKit.style_box(Color(0.12, 0.3, 0.44, 0.95), 22, 3, it.get("swatch", Color.WHITE), 6))
		uc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(uc)
		var sw := Panel.new()
		sw.position = Vector2(50, 8)
		sw.size = Vector2(40, 40)
		sw.add_theme_stylebox_override("panel", UIKit.style_box(it.get("swatch", Color.WHITE), 20, 3, Color.WHITE, 3))
		uc.add_child(sw)
		var kn := {"trail": "拖尾", "ball": "球", "court": "球场"}
		_lbl(uc, String(u["name"]), Vector2(0, 50), Vector2(140, 30), 22, T, HORIZONTAL_ALIGNMENT_CENTER)
		_lbl(uc, "%s · Lv.%d" % [kn.get(String(u["kind"]), ""), int(u["level"])], Vector2(0, 76), Vector2(140, 26), 18, T2, HORIZONTAL_ALIGNMENT_CENTER)
		uc.modulate.a = 0.0
		uc.set_meta("level", int(u["level"]))
		_unlock_cards.append(uc)
		ux += 150.0
		shown += 1


func _build_info_column(card: Control, data: Dictionary, mode: String, practice: bool) -> void:
	var x0 := 510.0
	if practice:
		_build_practice_stats(card, data, x0)
	else:
		_build_match_stats(card, data, x0)
	var y := 340.0
	_sec(card, "本场成就", Vector2(x0 - 10.0, y - 6.0), 250.0)
	y += 56.0
	var achs: Array = _reward.get("achievements", [])
	if achs.is_empty():
		_lbl(card, "—", Vector2(x0, y), Vector2(300, 34), 24, T2)
		y += 38.0
	for a in achs:
		if y > 490.0:
			break
		var b := _StarBadge.new()
		b.position = Vector2(x0, y)
		b.size = Vector2(38, 38)
		card.add_child(b)
		_lbl(card, "%s  +%d" % [a["name"], int(a.get("xp", 0))], Vector2(x0 + 48.0, y), Vector2(380, 38), 24, T)
		y += 38.0
	y = max(y + 18.0, 520.0)
	_sec(card, "今日任务", Vector2(x0 - 10.0, y - 6.0), 250.0)
	y += 56.0
	for m in Game.profile.daily["list"] if Game.profile != null else []:
		var done: bool = m["done"]
		_lbl(card, String(m["text"]), Vector2(x0, y), Vector2(330, 30), 22, T2 if done else T)
		var pb := ProgressBar.new()
		pb.position = Vector2(x0, y + 30.0)
		pb.size = Vector2(300, 12)
		pb.show_percentage = false
		pb.max_value = float(m["goal"])
		pb.value = minf(float(m["progress"]), float(m["goal"]))
		pb.add_theme_stylebox_override("background", UIKit.style_box(TRACK, 6))
		pb.add_theme_stylebox_override("fill", UIKit.style_box(Color("4fd16b") if done else UIKit.BLUE, 6))
		card.add_child(pb)
		_lbl(card, "已完成" if done else "%d/%d" % [int(m["progress"]), int(m["goal"])], Vector2(x0 + 310.0, y + 20.0), Vector2(120, 30), 20, GOOD if done else T2, HORIZONTAL_ALIGNMENT_RIGHT)
		y += 54.0


func _build_match_stats(card: Control, data: Dictionary, x0: float) -> void:
	var score: Array = data.get("score", [0, 0])
	var stats: Dictionary = data.get("stats", {})
	var sr := Control.new()
	sr.position = Vector2(x0, 14)
	sr.size = Vector2(430, 100)
	card.add_child(sr)
	_lbl(sr, str(score[0]), Vector2(0, 0), Vector2(170, 100), 84, UIKit.BLUE, HORIZONTAL_ALIGNMENT_RIGHT, 12, UIKit.INK)
	_lbl(sr, ":", Vector2(170, 0), Vector2(90, 100), 70, T, HORIZONTAL_ALIGNMENT_CENTER)
	_lbl(sr, str(score[1]), Vector2(260, 0), Vector2(170, 100), 84, UIKit.PINK, HORIZONTAL_ALIGNMENT_LEFT, 12, UIKit.INK)
	var rows := [
		["最长回合", "%d 次触球" % int(stats.get("longest", 0))],
		["ACE 发球", "%d  :  %d" % [stats["aces"][0], stats["aces"][1]]],
		["扣杀", "%d  :  %d" % [stats["spikes"][0], stats["spikes"][1]]],
		["拦网", "%d  :  %d" % [stats["blocks"][0], stats["blocks"][1]]],
		["Nice! 击球", "%d  :  %d" % [stats["perfects"][0], stats["perfects"][1]]],
	]
	if int(stats.get("power_spikes", [0, 0])[0]) + int(stats.get("fever", [0, 0])[0]) > 0:
		rows.append(["强力扣球 / 热血", "%d  /  %d" % [stats["power_spikes"][0], stats["fever"][0]]])
	var y := 120.0
	for r in rows:
		_lbl(card, r[0], Vector2(x0, y), Vector2(220, 34), 25)
		_lbl(card, r[1], Vector2(x0 + 200.0, y), Vector2(230, 34), 25, ACC, HORIZONTAL_ALIGNMENT_RIGHT)
		y += 32.0


func _build_practice_stats(card: Control, data: Dictionary, x0: float) -> void:
	var pr: Dictionary = data["practice"]
	if pr.get("mode", "rally") == "rally":
		_lbl(card, "最长回合", Vector2(x0, 14), Vector2(430, 40), 30, ACC)
		_lbl(card, "%d" % int(pr["best"]), Vector2(x0, 50), Vector2(250, 100), 90, UIKit.BLUE, HORIZONTAL_ALIGNMENT_LEFT, 12, UIKit.INK)
		_lbl(card, "次触球", Vector2(x0 + 190.0, 100), Vector2(160, 40), 28, T2)
		var mr := HUD_MedalRowProxy.new()
		mr.position = Vector2(x0, 150)
		mr.size = Vector2(440, 70)
		mr.best = int(pr["best"])
		card.add_child(mr)
		_lbl(card, "回合数", Vector2(x0, 240), Vector2(220, 34), 25)
		_lbl(card, "%d" % int(pr["rallies"]), Vector2(x0 + 200.0, 240), Vector2(230, 34), 25, ACC, HORIZONTAL_ALIGNMENT_RIGHT)
		_lbl(card, "累计触球", Vector2(x0, 276), Vector2(220, 34), 25)
		_lbl(card, "%d" % int(pr["total"]), Vector2(x0 + 200.0, 276), Vector2(230, 34), 25, ACC, HORIZONTAL_ALIGNMENT_RIGHT)
	else:
		_lbl(card, "教学清单", Vector2(x0, 14), Vector2(430, 40), 30, ACC)
		var y := 62.0
		for it in TrainingCoach.ITEMS:
			_lbl(card, "· " + String(it["text"]), Vector2(x0, y), Vector2(440, 34), 23)
			y += 40.0


func _build_buttons(mode: String, winner: int) -> void:
	var row := HBoxContainer.new()
	row.position = Vector2(880, 962)
	row.size = Vector2(980, 90)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 20)
	_root.add_child(row)
	var primary_text := "再来一局"
	var primary: Callable = func(): Game.start_match()
	if mode == "tournament":
		if winner == 0 and int(Game.tournament["round"]) < Game.TOURNAMENT_ROUNDS.size() - 1:
			var nxt: Dictionary = Game.TOURNAMENT_ROUNDS[int(Game.tournament["round"]) + 1]
			primary_text = "下一轮: %s" % nxt["name"]
			primary = func(): Game.tournament_next()
		elif winner == 0:
			primary_text = "再次挑战"
			primary = func(): Game.tournament_start()
		else:
			primary_text = "重新挑战本轮"
	_again = UIKit.button(primary_text, Vector2(380, 80), UIKit.GREEN, 36)
	_again.pressed.connect(primary)
	row.add_child(_again)
	var pick := UIKit.button("更换角色", Vector2(240, 70), UIKit.BLUE, 30)
	pick.pressed.connect(func(): Game.goto("select"))
	row.add_child(pick)
	var menu := UIKit.button("主菜单", Vector2(220, 70), UIKit.PINK, 30)
	menu.pressed.connect(func(): Game.goto("menu"))
	row.add_child(menu)
	_again.grab_focus()


# ------------------------------------------------------------------ the reward count-up
func _set_level_display(xp_now: int) -> void:
	var info := Profile.level_info(xp_now)
	_lv_circle.text = str(int(info["level"]))
	_lv_title.text = "Lv.%d  %s" % [int(info["level"]), String(info["title"])]
	_bar.max_value = 1.0
	_bar.value = float(info["ratio"])
	_bar_text.text = "%d / %d" % [int(info["into"]), int(info["need"])] if int(info["level"]) < Profile.MAX_LEVEL else "已满级"


func _set_xp(v: float) -> void:
	var xp_now := int(v)
	var info := Profile.level_info(xp_now)
	var lv := int(info["level"])
	_set_level_display(xp_now)
	_tick_acc += float(xp_now - _last_xp)
	_last_xp = xp_now
	if _tick_acc >= 12.0:
		_tick_acc = 0.0
		Sfx.play("xp_tick", -10.0, 1.0 + 0.002 * float(xp_now % 100), 0.03)
	if lv > _shown_level:
		_shown_level = lv
		Sfx.play("levelup", -2.0)
		_lv_circle.pivot_offset = _lv_circle.size * 0.5
		var tw := _lv_circle.create_tween()
		_lv_circle.scale = Vector2(1.6, 1.6)
		tw.tween_property(_lv_circle, "scale", Vector2.ONE, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		for uc in _unlock_cards:
			if int(uc.get_meta("level")) <= lv and uc.modulate.a < 0.5:
				uc.modulate.a = 1.0
				UIKit.pop_in(uc, 0.4, 0.4)
				Sfx.play("ui_confirm", -4.0, 1.2)


func _play_reward() -> void:
	await get_tree().create_timer(0.55).timeout
	for r in _rows:
		if not is_inside_tree():
			return
		(r as Control).modulate.a = 1.0
		UIKit.pop_in(r, 0.7, 0.2)
		Sfx.play("xp_tick", -6.0, 1.0, 0.04)
		await get_tree().create_timer(0.2).timeout
	for c in _chips:
		(c as Control).modulate.a = 1.0
		UIKit.pop_in(c, 0.5, 0.25)
		Sfx.play("ui_click", -8.0, 1.3)
		await get_tree().create_timer(0.16).timeout
	_total_label.modulate.a = 1.0
	UIKit.pop_in(_total_label, 0.5, 0.35)
	_bonus_label.modulate.a = 1.0
	Sfx.play("ui_confirm", -3.0)
	await get_tree().create_timer(0.5).timeout
	var start_total := int(_reward["total_xp"]) - int(_reward["xp"]) - int(_reward.get("bonus_xp", 0))
	var end_total := int(_reward["total_xp"])
	var tw := create_tween()
	tw.tween_method(_set_xp, float(start_total), float(end_total), clampf(0.8 + float(end_total - start_total) / 220.0, 0.9, 2.8)).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	await tw.finished
	_set_xp(float(end_total))
	for uc in _unlock_cards:
		if uc.modulate.a < 0.5 and int(uc.get_meta("level")) <= _shown_level:
			uc.modulate.a = 1.0
			UIKit.pop_in(uc, 0.4, 0.4)


## round gold star on a gold disc (achievement)
class _StarBadge:
	extends Control

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5 - 1.0
		draw_circle(c, r, Color.WHITE)
		draw_circle(c, r - 3.0, Color("ffc93c"))
		var star := PackedVector2Array()
		for i in 10:
			var a := -PI / 2.0 + PI * float(i) / 5.0
			var rr := r * (0.58 if i % 2 == 0 else 0.26)
			star.append(c + Vector2(cos(a), sin(a)) * rr)
		draw_colored_polygon(star, Color.WHITE)


## the medal row of the rally challenge (same look as the HUD)
class HUD_MedalRowProxy:
	extends Control
	var best := 0

	func _draw() -> void:
		var font: Font = ThemeDB.fallback_font
		if get_theme_default_font():
			font = get_theme_default_font()
		for i in Profile.MEDALS.size():
			var m: Dictionary = Profile.MEDALS[i]
			var c := Vector2(30.0 + float(i) * 130.0, 28.0)
			var got := best >= int(m["goal"])
			draw_circle(c + Vector2(0, 3), 26.0, Color(0, 0, 0, 0.18))
			draw_circle(c, 26.0, Color.WHITE)
			draw_circle(c, 22.0, m["color"] if got else Color(0.8, 0.83, 0.9, 0.9))
			draw_string(font, c + Vector2(-60.0, 58.0), "%s %d" % [Loc.t(String(m["name"])), int(m["goal"])], HORIZONTAL_ALIGNMENT_CENTER, 120.0, 20, T)
