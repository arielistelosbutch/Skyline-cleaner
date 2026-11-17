class_name ContractData
extends Resource
## Datová definice zakázky. Nové zakázky = nové .tres soubory.

@export var id := ""
@export var title := ""
@export var building_type := ""
@export var location := ""
@export_multiline var description := ""
@export var dirt_level_text := "Lehké"
@export var recommended_equipment := ""
@export var reward_money := 0
@export var reward_xp := 0
@export var bonus_goal := ""
@export var window_ids: PackedStringArray = []
## Bod na mapě (x, z ve světových souřadnicích) a vstup na pozemek.
@export var map_position := Vector2.ZERO
## Od které úrovně hráče se zakázka nabízí.
@export var required_level := 1
## Volitelný bonus za rychlost: dokončení do N minut práce = bonus (0 = bez bonusu).
@export var bonus_time_min := 0.0
@export var bonus_money := 0
## Opakovaná zakázka (pravidelný úklid) – podíl původní odměny.
@export var repeat_factor := 0.6
## Profil špíny (u poptávek z vesnice) – pro popis druhů nečistot před přijetím.
@export var dirt_profile_id := ""
## Zakázka „celá budova": bonus XP za každé patro umyté kolem dokola (0 = bez bonusu).
## Patro se pozná z id okna (…_p8_2, …_z8_1, …_l8_3 → 8. patro).
@export var floor_bonus_xp := 0
