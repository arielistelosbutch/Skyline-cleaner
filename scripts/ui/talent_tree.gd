class_name TalentTree
extends Control
## Grafický talentový strom: čtyři větve vedle sebe, uzly podle řádků (tier),
## čáry k předpokladům. Vpravo je popis vybraného talentu a odemčení –
## celý strom se vejde do tabletu bez posouvání.

const COL_W := 204.0
const NODE := Vector2(92, 70)
const ROW_H := 84.0
const TOP := 46.0
const BRANCH_COUNT := 4
const DETAIL_W := 250.0

var _buttons := {}     # id -> Button
var _selected := ""
var _detail_title: Label
var _detail_desc: Label
var _detail_state: Label
var _unlock: Button
var _points: Label


## Počet řádků stromu (nejvyšší tier + 1).
func _rows() -> int:
	var n := 4
	for id in Talents.order:
		n = maxi(n, Talents.get_talent(id).tier + 1)
	return n


func _ready() -> void:
	var tree_h := TOP + ROW_H * _rows()
	custom_minimum_size = Vector2(COL_W * BRANCH_COUNT + 14 + DETAIL_W, tree_h)
	mouse_filter = Control.MOUSE_FILTER_PASS
	for bi in TalentManager_branches().size():
		var br: Array = TalentManager_branches()[bi]
		var head := UITheme.label(br[1], 19, UITheme.TEXT, true)
		head.position = Vector2(bi * COL_W + 6, 0)
		add_child(head)
		var sub := UITheme.label(br[2], 12, UITheme.TEXT_SOFT)
		sub.position = Vector2(bi * COL_W + 6, 24)
		add_child(sub)
		var by_tier := {}
		for t in Talents.in_branch(br[0]):
			if not by_tier.has(t.tier):
				by_tier[t.tier] = []
			by_tier[t.tier].append(t)
		for tier in by_tier:
			var list: Array = by_tier[tier]
			for t: TalentData in list:
				var b := Button.new()
				b.custom_minimum_size = NODE
				b.size = NODE
				b.clip_text = true
				var x := bi * COL_W + (COL_W - 14 - NODE.x) * 0.5
				if list.size() > 1:
					x = bi * COL_W + 4 + t.column * (NODE.x + 8)
				b.position = Vector2(x, TOP + tier * ROW_H)
				b.add_theme_font_size_override("font_size", 12)
				b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				b.tooltip_text = t.description
				b.pressed.connect(_select.bind(t.id))
				add_child(b)
				_buttons[t.id] = b
	var detail := PanelContainer.new()
	detail.add_theme_stylebox_override("panel", UITheme.box(Color.WHITE, 14, 18, 18, Color(0.85, 0.88, 0.88), 1))
	detail.position = Vector2(COL_W * BRANCH_COUNT + 14, 0)
	detail.size = Vector2(DETAIL_W, tree_h)
	detail.custom_minimum_size = detail.size
	add_child(detail)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	detail.add_child(v)
	_points = UITheme.label("", 18, UITheme.TEXT, true)
	v.add_child(_points)
	_detail_title = UITheme.label("Vyber talent", 19, UITheme.TEXT, true)
	_detail_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_detail_title)
	_detail_desc = UITheme.label("Klikni na talent ve stromu. Talentový bod získáš za každou novou úroveň. Zlaté talenty můžeš odemknout hned, šedé patří k vybavení z dalších etap.", 15, UITheme.TEXT_SOFT)
	_detail_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_detail_desc)
	_detail_state = UITheme.label("", 15, UITheme.ACCENT_DARK)
	_detail_state.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_detail_state)
	var fill := Control.new()
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(fill)
	_unlock = Button.new()
	_unlock.text = "Odemknout"
	_unlock.custom_minimum_size = Vector2(0, 48)
	_unlock.pressed.connect(func() -> void:
		if Talents.unlock(_selected):
			refresh())
	v.add_child(_unlock)
	refresh()
	# rovnou předvybrat první talent, který jde odemknout
	if GameState.talent_points > 0:
		for id in Talents.order:
			if _buttons.has(id) and Talents.unlock_problem(id) == "":
				_select(id, false)
				break


## Pomocná funkce – větve stromu z TalentManageru (autoload „Talents").
func TalentManager_branches() -> Array:
	return Talents.BRANCHES


func _select(id: String, sound: bool = true) -> void:
	_selected = id
	if sound:
		Audio.play("click", -10.0)
	refresh()


func refresh() -> void:
	for id in _buttons:
		var t: TalentData = Talents.get_talent(id)
		var b: Button = _buttons[id]
		var r := Talents.rank(id)
		var problem := Talents.unlock_problem(id)
		var future := t.stage > Talents.CURRENT_STAGE
		var col := Color(0.62, 0.66, 0.68)
		if future:
			col = Color(0.78, 0.8, 0.81)
		elif r >= t.max_rank:
			col = UITheme.SUCCESS
		elif r > 0:
			col = UITheme.ACCENT
		elif problem == "":
			col = UITheme.GOLD
		var sb := UITheme.box(col, 12, 8, 8, Color(0.1, 0.3, 0.35) if id == _selected else Color(0, 0, 0, 0), 3 if id == _selected else 0)
		for st in ["normal", "hover", "pressed", "focus"]:
			b.add_theme_stylebox_override(st, sb if st != "hover" else UITheme.box(col.lightened(0.1), 12, 8, 8, Color(0.1, 0.3, 0.35), 3 if id == _selected else 0))
		var rank_txt := "%d / %d" % [r, t.max_rank]
		b.text = "%s\n%s" % [t.display_name, ("Etapa %d" % t.stage) if future else rank_txt]
		b.add_theme_color_override("font_color", Color(0.35, 0.38, 0.4) if future else Color.WHITE)
	_points.text = "Talentové body: %d" % GameState.talent_points
	if _selected != "":
		var t: TalentData = Talents.get_talent(_selected)
		_detail_title.text = "%s  (%d / %d)" % [t.display_name, Talents.rank(_selected), t.max_rank]
		_detail_desc.text = t.description
		var problem := Talents.unlock_problem(_selected)
		_detail_state.text = "Cena: %d talentový bod%s. %s" % [t.cost, "" if t.cost == 1 else "y", problem]
		_unlock.disabled = problem != ""
	else:
		_unlock.disabled = true
	queue_redraw()


func _draw() -> void:
	for id in _buttons:
		var t: TalentData = Talents.get_talent(id)
		var b: Button = _buttons[id]
		for req in t.requires:
			if not _buttons.has(req):
				continue
			var pb: Button = _buttons[req]
			var a := pb.position + Vector2(NODE.x * 0.5, NODE.y)
			var c := b.position + Vector2(NODE.x * 0.5, 0)
			var col := UITheme.ACCENT if Talents.rank(req) > 0 else Color(0.7, 0.74, 0.75)
			draw_line(a, c, col, 4.0, true)
