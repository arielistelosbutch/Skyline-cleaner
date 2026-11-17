class_name TalentData
extends Resource
## Datová definice talentu. Nový talent = nový .tres v data/talents/.
## effect říká, kterou herní hodnotu talent mění, values = hodnota pro každou úroveň.

@export var id := ""
@export var display_name := ""
@export_multiline var description := ""
@export_enum("zrucnost", "technika", "podnikani", "robotika") var branch := "zrucnost"
## Řádek ve stromu (0 = první).
@export var tier := 0
## Sloupec v rámci větve (0 = vlevo, 1 = vpravo) – jen pro rozložení stromu.
@export var column := 0
@export var cost := 1
@export var max_rank := 1
@export var requires: PackedStringArray = []
## Klíč účinku: clean_mult, blade_width, complete_threshold, carry, spray_radius,
## reward, price, xp, … (viz TalentManager).
@export var effect := ""
@export var values := PackedFloat32Array([1.0])
## Etapa vývoje, ve které je talent skutečně funkční (> 2 = zatím připravujeme).
@export var stage := 2
