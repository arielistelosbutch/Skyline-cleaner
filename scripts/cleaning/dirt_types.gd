class_name DirtTypes
extends RefCounted
## Typy nečistot a jejich chování při čištění.
##
## Každý pixel masky má jeden převažující typ (kind). Typ určuje, jak špína
## reaguje na suchý nástroj, na vodu a na chemii. Barvu a vzhled každého
## typu kreslí shader glass_dirt.gdshader (kanál B masky = typ).

enum { DUST, DROPS, MUD, BIRD, GREASE, POLLEN, HEAVY }
const COUNT := 7

const NAMES := ["Prach", "Zaschlé kapky", "Bláto", "Ptačí trus", "Mastnota", "Pyl", "Silná špína"]

## Celkové zpomalení mytí nasucho (bez vody / saponátu). Nasucho to jde,
## ale znatelně pomaleji – hráč má důvod chodit doplňovat nádržku.
const DRY_SCALE := 0.4
## Jak dobře jde špína dolů suchým nástrojem (1 = normálně, před DRY_SCALE).
const DRY := [1.0, 1.0, 0.12, 1.0, 0.3, 1.25, 0.35]
## Násobek bonusu za vlhkost skla (voda / saponát).
const WATER_GAIN := [1.0, 1.0, 1.7, 1.0, 0.1, 0.6, 1.3]
## Násobek účinku rozpouštědla (odmašťovací síla chemie).
const CHEM_GAIN := [0.0, 0.0, 0.4, 0.3, 5.0, 0.0, 1.0]

## Nápověda, když nástroj na daném typu skoro nečistí.
const HINTS := [
	"",
	"Zaschlé kapky povolí, když je navlhčíš [F].",
	"Bláto je potřeba nejdřív namočit – saponát [F] nebo mokrá houbička.",
	"Ptačí trus je odolný – namoč ho [F] a drhni opakovaně.",
	"Mastnotu voda nerozpustí. Použij saponát, nejlépe odmašťovač [Q] a [F].",
	"",
	"Silná špína: namoč ji [F]. Vrchní krusta jde dolů ztuha, spodní vrstva už snadno.",
]


static func name_of(kind: int) -> String:
	return NAMES[clampi(kind, 0, COUNT - 1)]
