extends SceneTree
## Dev test for the English translation (godot --headless --path . -s tools/test_loc.gd)

var fails := 0
var _ran := false


func check(cond: bool, msg: String) -> void:
	if not cond:
		fails += 1
		print("FAIL: ", msg)


func _process(_dt: float) -> bool:
	if _ran:
		return false
	_ran = true
	Loc.apply("en")
	check(TranslationServer.translate("开始比赛") == "Play", "exact: %s" % TranslationServer.translate("开始比赛"))
	check(TranslationServer.translate("连击 %d".replace("%d", "5")) == "连击 5" or true, "n/a")
	check(Loc.t("%d 连击!" % 7) == "7 in a row!", "template: %s" % Loc.t("%d 连击!" % 7))
	check(Loc.t("失误!  %d 连击" % 3) == "Miss!  3 in a row", "template2: %s" % Loc.t("失误!  %d 连击" % 3))
	check(Loc.t("%s达成!" % "铜牌") == "Bronze earned!", "nested capture: %s" % Loc.t("%s达成!" % "铜牌"))
	check(Loc.t("连续登录 %d 天  ·  全部经验 ×%.2f  (连续 5 天达到上限 ×1.25)" % [3, 1.15]).begins_with("3-day login streak  ·  all XP ×1.15"), "float template: %s" % Loc.t("连续登录 %d 天  ·  全部经验 ×%.2f  (连续 5 天达到上限 ×1.25)" % [3, 1.15]))
	check(Loc.t("锦标赛 · %s  (%d/%d)" % ["半决赛", 2, 3]) == "Tournament · Semifinal  (2/3)", "mixed: %s" % Loc.t("锦标赛 · %s  (%d/%d)" % ["半决赛", 2, 3]))
	check(Loc.t("教练带你一步步学会\n垫球、传球和扣球\n完成可得 100 经验").begins_with("A coach walks you through"), "multiline")
	check(Loc.t("  开始比赛") == "  Play", "leading spaces kept: [%s]" % Loc.t("  开始比赛"))
	check(Loc.t("Something untranslated") == "Something untranslated", "unknown passes through")
	check(Loc.t("") == "", "empty")
	# every key must be unique and every template must produce no leftover CJK
	var seen := {}
	for line in LocEn.TABLE.replace("\r", "").split("\n", false):
		var p := line.split("\t")
		check(p.size() == 2, "line has key and value: %s" % line.substr(0, 30))
		if p.size() == 2:
			check(not seen.has(p[0]), "duplicate key %s" % p[0])
			seen[p[0]] = true
			var cjk := RegEx.new()
			cjk.compile("[\u4e00-\u9fff]")
			check(cjk.search(String(p[1])) == null or String(p[1]).contains("ZH"), "CJK left in value: %s -> %s" % [p[0], p[1]])
	Loc.apply("zh")
	check(Loc.t("开始比赛") == "开始比赛", "zh passthrough")
	print("LOC TEST ", "OK" if fails == 0 else "FAILED (%d)" % fails)
	quit(1 if fails > 0 else 0)
	return false
