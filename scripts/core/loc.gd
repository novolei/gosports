class_name Loc
extends RefCounted
## Localisation. The code base is written in Chinese (the source language); English is a Translation whose
## _get_message() first looks the exact text up and then tries the %d / %s templates, so even strings that were
## formatted before reaching a Label ("连击 5") are translated. Controls translate their text automatically (auto_translate),
## everything else (draw_string, Label3D ...) calls Loc.t() / tr().

const LANGS := ["auto", "zh", "en"]
const LANG_NAMES := ["Auto / 自动", "中文", "English"]

static var lang := "zh"
static var _en: EnTranslation = null


## apply Game.settings["language"] (call at start-up and whenever the setting changes)
static func apply(setting := "auto") -> void:
	var want := setting
	if want == "auto":
		want = "zh" if OS.get_locale_language().begins_with("zh") else "en"
	lang = want
	if _en != null:
		TranslationServer.remove_translation(_en)
		_en = null
	if lang == "en":
		_en = EnTranslation.new()
		_en.locale = "en"
		TranslationServer.add_translation(_en)
		TranslationServer.set_locale("en")
	else:
		TranslationServer.set_locale("zh")


static func is_en() -> bool:
	return lang == "en"


## explicit translation for code paths that do not go through a Control (draw_string, 3D labels, string building)
static func t(zh: String) -> String:
	if lang != "en":
		return zh
	return TranslationServer.translate(zh)


class EnTranslation:
	extends Translation
	var _exact := {}
	var _tmpl: Array = []          # [{re: RegEx, en: String}]
	var _cache := {}

	func _init() -> void:
		for line in LocEn.TABLE.replace("\r", "").split("\n", false):
			var p := line.split("\t")
			if p.size() < 2:
				continue
			var k := String(p[0]).replace("\\n", "\n")
			var v := String(p[1]).replace("\\n", "\n")
			_exact[k] = v
			if "%" in k:
				var re := RegEx.new()
				if re.compile(_pattern(k)) == OK:
					_tmpl.append({"re": re, "en": v, "len": k.length()})
		_tmpl.sort_custom(func(a, b): return int(a["len"]) > int(b["len"]))

	const _SPECIAL := [".", "^", "$", "|", "?", "*", "+", "(", ")", "[", "]", "{", "}", "\\"]

	static func _pattern(k: String) -> String:
		var out := "^"
		var i := 0
		while i < k.length():
			var c := k[i]
			if c == "%" and i + 1 < k.length():
				var rest := k.substr(i, 4)
				if rest.begins_with("%.2f") or rest.begins_with("%.1f"):
					out += "(-?\\d+(?:\\.\\d+)?)"
					i += 4
					continue
				var n := k[i + 1]
				if n == "d":
					out += "(-?\\d+)"
					i += 2
					continue
				if n == "s":
					out += "(.+?)"
					i += 2
					continue
				if n == "%":
					out += "%"
					i += 2
					continue
			if _SPECIAL.has(c):
				out += "\\"
			out += c
			i += 1
		return out + "$"

	func _get_message(src_message: StringName, _context: StringName) -> StringName:
		var s := String(src_message)
		if s == "":
			return &""
		if _cache.has(s):
			return _cache[s]
		var r := _translate(s)
		if _cache.size() > 4000:
			_cache.clear()
		_cache[s] = StringName(r)
		return StringName(r)

	func _translate(s: String) -> String:
		if _exact.has(s):
			return _exact[s]
		var stripped := s.strip_edges()
		if stripped != s and _exact.has(stripped):
			return s.replace(stripped, _exact[stripped])
		for t in _tmpl:
			var m: RegExMatch = (t["re"] as RegEx).search(s)
			if m == null:
				continue
			var en: String = t["en"]
			var out := ""
			var gi := 1
			var i := 0
			while i < en.length():
				if en[i] == "%" and i + 1 < en.length():
					var rest := en.substr(i, 4)
					var width := 2
					if rest.begins_with("%.2f") or rest.begins_with("%.1f"):
						width = 4
					elif not (en[i + 1] == "d" or en[i + 1] == "s" or en[i + 1] == "%"):
						out += en[i]
						i += 1
						continue
					if en[i + 1] == "%":
						out += "%"
					else:
						var cap := m.get_string(gi) if gi <= m.get_group_count() else ""
						gi += 1
						out += _translate(cap) if en[i + 1] == "s" else cap
					i += width
					continue
				out += en[i]
				i += 1
			return out
		# several clauses joined with " / ", " · " ... : translate piecewise
		for sep in [" · ", " / ", "  ·  ", "  "]:
			if sep in s:
				var parts := s.split(sep)
				var any := false
				var res: PackedStringArray = []
				for p in parts:
					var tp := _translate(p) if p != "" else p
					if tp != p:
						any = true
					res.append(tp)
				if any:
					return sep.join(res)
		return s
