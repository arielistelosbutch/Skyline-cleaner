class_name ToolData
extends Resource
## Datová definice čisticího nástroje nebo přípravku. Nový nástroj = nový .tres.
##
## kind "rag"   = ruční nástroj, kterým se drhne po skle (hadr, houbička, stěrka)
## kind "spray" = přípravek ve rozprašovači (voda, saponát, odmašťovač)

@export var id := ""
@export var display_name := ""
@export_multiline var description := ""
@export_enum("rag", "spray") var kind := "rag"
## Vzhled nástroje: "rag" hadr, "sponge" houbička, "squeegee" stěrka, "bottle" lahev.
@export_enum("rag", "sponge", "squeegee", "bottle", "brush") var visual := "rag"
@export var color := Color(0.85, 0.72, 0.42)

@export_group("Obchod")
@export var price := 0
@export var required_level := 1
## Potřebná pověst (hvězdy) pro nákup.
@export var required_rep := 1
@export var shop_order := 0

@export_group("Ruční nástroj")
## "round" = kulatá kontaktní plocha, "blade" = lišta stěrky.
@export_enum("round", "blade") var shape := "round"
## Poloměr kontaktní plochy se sklem v metrech (u stěrky jen pro dosah).
@export var radius := 0.07
## Šířka lišty stěrky v metrech.
@export var blade_width := 0.25
## Hloubka styku lišty se sklem (jak dlouho pixel „pod lištou" zůstane).
@export var blade_depth := 0.02
## Kolik špíny odstraní jeden metr tahu při plném kontaktu.
@export var strength := 5.0
## Jak moc odolné nečistoty (zaschlé kapky, trus) zpomalují čištění.
@export var tough_penalty := 6.0
## Násobek účinnosti na mokrém skle (1 + wet_bonus * vlhkost).
@export var wet_bonus := 3.0
## Účinnost na suchém skle (stěrka nasucho skoro nečistí).
@export var dry_mult := 1.0
## Násobky účinnosti podle typu nečistoty (pořadí viz DirtTypes).
@export var kind_mult := PackedFloat32Array([1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0])
## Malé jednorázové setření pod nástrojem při přitlačení (bez pohybu).
@export var initial_press := 0.05
## Bonus za dlouhý souvislý tah (0 = žádný, 1 = plný).
@export var stroke_bonus := 0.0
## Jak důkladně nástroj stírá vodu ze skla (stěrka 1).
@export var dries := 0.0
## Houbička: drží vodu a roztírá ji (a s ní i přípravek) po skle.
@export var spreads := 0.0
## Jak rychle se nástroj (hadr, houbička) zanáší špinavou vodou. Zanesený čistí hůř,
## dokud ho hráč nevyždímá [R] nebo nevymáchá ve vodě. 0 = nezanáší se (stěrka, kartáč).
@export var soil_rate := 1.0
## Teleskopická tyč: o kolik metrů výš (i do stran) dosáhneš.
@export var reach_bonus := 0.0
## Elektrický nástroj (talent Technický génius zvyšuje výkon).
@export var electric := false
## Rotační hlava (elektrický kartáč): kolik metrů „tahu" za sekundu odvede sama,
## když je přitlačená – čistí i bez drhnutí myší, stačí s ní pomalu jezdit po skle.
@export var spin := 0.0
## Elektrický stěrač s vlastní nádržkou: kolik sekund jízdy po skle vydrží sám
## dávkovat přípravek (bez stříkání [F]). 0 = nástroj nádržku nemá.
@export var auto_dose := 0.0
## Skládací mop: od ruky po délku tyče. Natažený čistí slaběji (násobek při plném vysunutí).
@export var fold := false
@export var fold_mult := 1.0

@export_group("Přípravek")
## Poloměr nástřiku v metrech.
@export var spray_radius := 0.17
## Jak moc rozpouští mastnotu (0..1).
@export var grease_power := 0.3
## Násobek účinku vlhkosti na běžnou špínu (1 = obyčejná voda se saponátem).
@export var dissolve := 1.0
## Rychlost odpařování (1 = normální, menší = vydrží déle mokré).
@export var evaporation := 1.0


func km(kind_id: int) -> float:
	if kind_id < kind_mult.size():
		return kind_mult[kind_id]
	return 1.0
