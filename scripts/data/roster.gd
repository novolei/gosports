class_name Roster
extends RefCounted
## The 24 playable characters: 20 cartoon animals / people (Cubebrush "Simple Character Pack")
## and 4 ninjas (Male Ninja Modular Pack, cute series).

const CUBE_DIR := "res://assets/characters/cube/"
const NINJA_DIR := "res://assets/characters/ninja/"

## kind "cube": model + outfit texture (+ optional hair texture for the human models)
static func _cube(id: String, nm: String, model: String, tex: String, hair := "", blurb := "") -> Dictionary:
	return {
		"id": id, "name": nm, "kind": "cube", "blurb": blurb,
		"model": CUBE_DIR + "models/%s.fbx" % model,
		"tex": CUBE_DIR + "textures/%s.png" % tex,
		"hair": (CUBE_DIR + "textures/%s.png" % hair) if hair != "" else "",
		"scale": 0.6,
	}


## kind "ninja": body + head + face + optional hair / head gear, all authored in the same model space
static func _ninja(id: String, nm: String, body: String, outfit: String, head: String, skin: String, face: String,
		hair: String, hair_tint: Color, gear: String, gear_tex: String, blurb := "") -> Dictionary:
	return {
		"id": id, "name": nm, "kind": "ninja", "blurb": blurb,
		"model": NINJA_DIR + "fbx/%s.fbx" % body,
		"tex": NINJA_DIR + "tex/%s.png" % outfit,
		"head": NINJA_DIR + "fbx/%s.fbx" % head,
		"skin": NINJA_DIR + "tex/%s.png" % skin,
		"face": NINJA_DIR + "tex/%s.png" % face,
		"hair": (NINJA_DIR + "fbx/%s.fbx" % hair) if hair != "" else "",
		"hair_tex": NINJA_DIR + "tex/hair_%s.png" % ("light" if hair_tint.get_luminance() > 0.45 else "dark"),
		"hair_tint": hair_tint,
		"gear": (NINJA_DIR + "fbx/%s.fbx" % gear) if gear != "" else "",
		"gear_tex": (NINJA_DIR + "tex/%s.png" % gear_tex) if gear_tex != "" else "",
		"scale": 1.0,
	}


static func all() -> Array[Dictionary]:
	var r: Array[Dictionary] = []
	r.append(_cube("m", "小M", "Human", "Tex_Human_A_Casual_A", "Tex_Hair_Black_Sidesweep_A", "元气满满的队长"))
	r.append(_cube("baobao", "阿宝", "Human", "Tex_Human_B_Casual_B", "Tex_Hair_Black_Sidesweep_C", "弹跳力惊人"))
	r.append(_cube("sakura", "小樱", "Human", "Tex_Human_C_Casual_F", "Tex_Hair_Blonde_Sidesweep", "发球超准"))
	r.append(_cube("bear", "熊大", "Bear", "Tex_Bear_A_Casual_A", "", "力量型扣杀手"))
	r.append(_cube("panda", "盼盼", "Bear", "Tex_Panda_Casual_D", "", "稳如泰山的防守"))
	r.append(_cube("snow", "雪球", "Cat", "Tex_Cat_A_Casual_A", "", "反应敏捷"))
	r.append(_cube("tabby", "灰灰", "Cat", "Tex_Cat_B_Casual_B", "", "神出鬼没"))
	r.append(_cube("wang", "旺财", "Dog", "Tex_Dog_A_Casual_A", "", "跑得飞快"))
	r.append(_cube("shiba", "柴柴", "Dog", "Tex_Dog_C_Casual_F", "", "永不放弃"))
	r.append(_cube("tutu", "兔兔", "Rabbit", "Tex_Rabbit_A_Casual_A", "", "跳得最高"))
	r.append(_cube("chestnut", "栗子", "Rabbit", "Tex_Rabbit_B_Casual_B", "", "二传好手"))
	r.append(_cube("monkey", "猴哥", "Monkey", "Tex_Monkey_A_Casual_A", "", "花样百出"))
	r.append(_cube("duckling", "小黄", "Duck", "Tex_Duck_Casual_F", "", "嘎嘎嘎"))
	r.append(_cube("mallard", "绿头", "Duck", "Tex_Mallard_Casual_E", "", "水上飘"))
	r.append(_cube("rooster", "大吉", "Chicken", "Tex_Chicken_Casual_A", "", "大吉大利"))
	r.append(_cube("fawn", "小鹿", "Deer", "Tex_Deer_A_Casual_D", "", "优雅步伐"))
	r.append(_cube("hippo", "河马", "Hippo", "Tex_Hippo_Casual_A", "", "憨憨拦网"))
	r.append(_cube("rhino", "犀牛", "Rhino", "Tex_Rhino_Casual_C", "", "冲撞王"))
	r.append(_cube("moose", "麋鹿", "Moose", "Tex_Moose_Casual_B", "", "长臂拦网"))
	r.append(_cube("croc", "鳄鳄", "Croc", "Tex_Croc_A_Casual_C", "", "咬住不放"))
	r.append(_ninja("ninja_red", "红影", "Male_Ninja_02", "fair_red", "Head_01", "fair_aqua", "face_male_02_brown",
			"", Color.BLACK, "Hood_Ninja", "fair_red", "疾风般的突击"))
	r.append(_ninja("ninja_blue", "蓝影", "Male_Ninja_01", "tan_blue", "Head_02", "tan_aqua", "face_male_01_black",
			"Hair_For_Hat", Color(0.58, 0.58, 0.58), "Ninja_Hat", "fair_blue", "冷静的二传"))
	r.append(_ninja("ninja_purple", "紫影", "Male_Ninja_03", "fair_purple", "Head_01", "fair_aqua", "face_male_03_blonde",
			"Hair_02", Color(1, 0.86, 0.11), "Hood_Mystery", "fair_purple", "神秘的拦网手"))
	r.append(_ninja("ninja_black", "黑影", "Male_Ninja_02", "tan_black", "Head_02", "tan_aqua", "face_male_02_grey",
			"Hair_03", Color(0.88, 0.88, 0.88), "Ninja_Mask", "fair_black", "暗夜扣杀"))
	return r


## speed, jump, power multipliers (1.0 = average). Displayed as bars on the select screen.
const STATS := {
	"m": [1.0, 1.0, 1.0], "baobao": [0.98, 1.12, 1.0], "sakura": [1.0, 1.0, 1.08],
	"bear": [0.92, 0.95, 1.15], "panda": [0.9, 0.96, 1.08], "snow": [1.1, 1.02, 0.92], "tabby": [1.08, 1.0, 0.95],
	"wang": [1.12, 0.98, 0.95], "shiba": [1.04, 1.0, 1.04], "tutu": [1.02, 1.14, 0.92], "chestnut": [1.0, 1.04, 0.96],
	"monkey": [1.06, 1.08, 0.94], "duckling": [1.0, 1.0, 1.0], "mallard": [1.0, 1.03, 1.0], "rooster": [1.02, 1.02, 1.02],
	"fawn": [1.08, 1.06, 0.92], "hippo": [0.9, 0.92, 1.1], "rhino": [0.94, 0.92, 1.14], "moose": [0.98, 1.0, 1.06],
	"croc": [0.96, 0.96, 1.12], "ninja_red": [1.1, 1.06, 1.0], "ninja_blue": [1.02, 1.0, 1.04],
	"ninja_purple": [1.04, 1.1, 1.0], "ninja_black": [1.08, 1.04, 1.08],
}


## one passive perk per character (applied in Athlete / MatchDirector)
const PERKS := {
	"iron": {"name": "铁壁", "desc": "拦网更容易得分，不容易被撞倒"},
	"gale": {"name": "疾风", "desc": "Nice! 击球后短暂加速"},
	"eagle": {"name": "鹰眼", "desc": "击球时机判定窗口更宽"},
	"might": {"name": "怪力", "desc": "扣杀更难被拦网拍死"},
	"agile": {"name": "灵巧", "desc": "扑救更远，起身更快"},
	"morale": {"name": "鼓舞", "desc": "队伍热度积累更快"},
	"steady": {"name": "稳健", "desc": "普通击球更精准"},
}
const PERK_OF := {
	"m": "steady", "baobao": "morale", "sakura": "eagle", "bear": "iron", "panda": "morale", "snow": "gale", "tabby": "agile",
	"wang": "gale", "shiba": "steady", "tutu": "agile", "chestnut": "steady", "monkey": "agile", "duckling": "morale",
	"mallard": "steady", "rooster": "eagle", "fawn": "gale", "hippo": "iron", "rhino": "iron", "moose": "might", "croc": "might",
	"ninja_red": "gale", "ninja_blue": "eagle", "ninja_purple": "agile", "ninja_black": "might",
}


static func perk_info(perk: String) -> Dictionary:
	return PERKS.get(perk, {"name": "", "desc": ""})


static func by_id(id: String) -> Dictionary:
	for c in all():
		if c["id"] == id:
			var st: Array = STATS.get(id, [1.0, 1.0, 1.0])
			c["stats"] = {"speed": st[0], "jump": st[1], "power": st[2]}
			c["perk"] = PERK_OF.get(id, "")
			return c
	return all()[0]


static func index_of(id: String) -> int:
	var a := all()
	for i in a.size():
		if a[i]["id"] == id:
			return i
	return 0
