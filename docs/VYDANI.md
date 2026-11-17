# Jak vydat novou verzi Clear View

Hra má vestavěné automatické aktualizace. Při každém spuštění se podívá sem na GitHub,
a když tu najde novější vydání, nabídne hráči **Aktualizovat teď**. Hra si stáhne novou verzi,
sama se restartuje a ukáže okno **Co je nového** s textem, který napíšeš do popisu vydání.

## Postup (asi 2 minuty, všechno na webu)

1. Nahraj změny ve hře do repozitáře (větev `main`).
2. Otevři **[Releases → Draft a new release](../../releases/new)**.
3. **Choose a tag** → napiš nové číslo verze s „v“ na začátku, vyšší než minule
   (např. `v0.8.0`, malá oprava `v0.8.1`) → *Create new tag*.
4. **Release title**: třeba `Clear View 0.8`.
5. Do popisu napiš novinky. Přesně tenhle text uvidí hráči v okně „Co je nového“. Funguje:
   ```
   ## Novinky
   - **Nová oblast:** přístav s jeřáby
   - Robot si sám dojede pro vodu

   ## Opravy
   - Žebřík už nepadá skrz střechu
   ```
6. Klikni na **Publish release**. Nic dalšího nenahráváš.

Během 5–10 minut GitHub sám sestaví hru pro Windows a přiloží k vydání `ClearView-windows.zip`
(průběh je vidět v záložce **Actions**). Číslo verze ve hře se nastaví samo podle tagu.
Dokud tam zip není, hry aktualizaci nenabízí.

## Když se něco nepovede

* **V Actions svítí červený křížek:** otevři ho a podívej se na chybu. Opravu nahraj do `main`
  a v Actions → *Sestavit vydání* → *Run workflow* zadej stejný tag (např. `v0.8.0`).
  Zip se k vydání přiloží znovu.
* **Překlep v novinkách:** vydání jde upravit (Edit). Hráči, kteří už aktualizovali, ale uvidí starý text.
* **Vydání omylem:** smaž ho (Delete). Hry nabízejí vždy jen poslední vydání, které není *pre-release*.
* Vydání označené jako **pre-release** hry ignorují. Hodí se na vyzkoušení před ostrým vydáním.

## Jak to funguje uvnitř

* Kód: `scripts/autoload/updater.gd` (kontrola, stažení, výměna exe) a `scripts/ui/update_dialog.gd` (okna).
* Verze hry je v `project.godot` → `config/version`. Při vydání ji nastaví workflow
  `.github/workflows/release.yml` podle tagu.
* Aktualizace: zip se stáhne, `ClearView.exe` z něj se uloží vedle běžícího exe, běžící se přejmenuje
  na `ClearView.old.exe` a nové jde na jeho místo. Pak se nová verze spustí a stará se ukončí.
  `ClearView.old.exe` smaže až další spuštění. Uložená hra (`%APPDATA%\Godot\app_userdata\…`) zůstává.
* Když hra nemůže do své složky zapisovat (např. leží v Program Files), otevře místo toho stránku vydání.
* Kontrolu aktualizací jde vypnout v Nastavení. V editoru Godotu a v testech se nespouští.
