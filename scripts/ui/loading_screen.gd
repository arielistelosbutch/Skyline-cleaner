class_name LoadingScreen
extends CanvasLayer
## Načítací obrazovka při startu hry (Etapa 7): název, průběh stavby oblastí a tipy.
## Tip se každých pár sekund vymění; obrazovka na konci plynule zmizí.

const TIPS := [
	"Bláto a zaschlé kapky povolí, když je nejdřív namočíš saponátem [F].",
	"Stěrka táhne vodu i se špínou – nejlepší je až po namočení skla.",
	"Mastné okno? Voda nestačí, vezmi odmašťovač [Q] a pak hadr.",
	"Ptačí trus je odolný. Namoč ho a drhni opakovaně na jednom místě.",
	"Okno umyté na 95 % se při odchodu samo dočistí – nehledej poslední šmouhu.",
	"Neumytá okna zakázky mají nad sebou žlutou značku.",
	"Žebřík opřeš o zeď klávesou [E], nahoru a dolů lezeš klávesami W a S.",
	"Kompas nahoře tě dovede k přijaté zakázce. U budovy pak šipky ▼ ukážou špinavá okna.",
	"Talentové body dostaneš s každou úrovní – mrkni do tabletu [Tab].",
	"Robot na okna se přikládá klávesou R. Myje sám, ty mezitím můžeš jinde.",
	"Drony ve Velkoměstě začnou nejvyššími patry, ty se pusť do těch nízkých.",
	"Po bouřce se ozvou zákazníci s ušpiněnými okny – a lépe platí.",
	"Dodávkou se přesuneš rovnou k zakázce a roboti se v ní nabíjí.",
	"Kolečkem myši přepínáš vybavení v ruce, i přímo u okna.",
	"Stálí zákazníci přidají 10 % – vyplatí se k nim vracet.",
	"Spěchající zákazník přidá bonus, když to stihneš v čase. Nemusíš.",
	"Bouřky a ptačí trus jdou vypnout v Nastavení.",
]

var _bar: ProgressBar
var _step: Label
var _tip: Label
var _root: Control
var _tip_i := 0
var _tip_t := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.11, 0.2, 0.26)
	_root.add_child(bg)
	# jemný pruh „čistého skla“ přes obrazovku
	var shine := ColorRect.new()
	shine.color = Color(1, 1, 1, 0.04)
	shine.anchor_left = 0.55
	shine.anchor_right = 0.75
	shine.anchor_bottom = 1.0
	_root.add_child(shine)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.custom_minimum_size = Vector2(720, 0)
	box.position = Vector2(-360, -150)
	box.add_theme_constant_override("separation", 14)
	_root.add_child(box)
	var title := UITheme.label("CLEAR VIEW", 64, Color(0.95, 0.98, 1.0), true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var sub := UITheme.label("Window Cleaning Simulator", 22, Color(0.6, 0.85, 0.9))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sub)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 30)
	box.add_child(gap)
	_bar = ProgressBar.new()
	_bar.custom_minimum_size = Vector2(720, 18)
	_bar.show_percentage = false
	_bar.min_value = 0.0
	_bar.max_value = 1.0
	var fill := StyleBoxFlat.new()
	fill.bg_color = UITheme.ACCENT
	fill.set_corner_radius_all(9)
	var back := StyleBoxFlat.new()
	back.bg_color = Color(1, 1, 1, 0.12)
	back.set_corner_radius_all(9)
	_bar.add_theme_stylebox_override("fill", fill)
	_bar.add_theme_stylebox_override("background", back)
	box.add_child(_bar)
	_step = UITheme.label("Načítám…", 18, Color(0.8, 0.88, 0.9))
	_step.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_step)
	var gap2 := Control.new()
	gap2.custom_minimum_size = Vector2(0, 24)
	box.add_child(gap2)
	_tip = UITheme.label("", 20, Color(0.95, 0.9, 0.7))
	_tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip.custom_minimum_size = Vector2(720, 60)
	box.add_child(_tip)
	_tip_i = _rng.randi() % TIPS.size()
	_show_tip()
	set_progress(_p, _what)


func _show_tip() -> void:
	_tip.text = "Tip: " + TIPS[_tip_i % TIPS.size()]


var _p := 0.0
var _what := "Načítám…"


func set_progress(v: float, what: String) -> void:
	_p = clampf(v, 0.0, 1.0)
	_what = what
	if _bar:
		_bar.value = _p
		_step.text = _what


func _process(delta: float) -> void:
	_tip_t += delta
	if _tip_t > 5.0:
		_tip_t = 0.0
		_tip_i += 1
		_show_tip()


## Plynule zmizí a smaže se.
func finish() -> void:
	set_progress(1.0, "Hotovo")
	var tw := create_tween()
	tw.tween_property(_root, "modulate:a", 0.0, 0.5)
	tw.tween_callback(queue_free)
