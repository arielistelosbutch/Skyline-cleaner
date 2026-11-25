# Clear View – Window Cleaning Simulator

Relaxační 3D simulátor mytí oken z pohledu první osoby. Godot **4.7** (GDScript), renderer Forward+.

Klidná hra bez stresu: začínáš s hadrem a kbelíkem na vesnici, bereš zakázky přes tablet, kupuješ lepší nářadí
(stěrky, teleskopické tyče, žebřík, lano, plošinu) a postupně se dostaneš přes předměstí a město až k mrakodrapům,
kde ti pomáhají roboti a drony. Hrací doba zhruba 8 hodin, hra je celá v češtině.

## Jak hrát

**Windows:** v sekci [Releases](../../releases) stáhni nejnovější `ClearView-windows.zip`, rozbal ho a spusť
`ClearView.exe`. Nic se neinstaluje. Windows může při prvním spuštění ukázat „Systém Windows ochránil váš počítač“,
protože hra není podepsaná – klikni na *Další informace* → *Přesto spustit*.
Další verze si hra stáhne sama: při spuštění nabídne **Aktualizovat teď** a po restartu ukáže, co je nového.
Jak vydat novou verzi: [docs/VYDANI.md](docs/VYDANI.md).

**Ze zdrojáků (jakýkoli systém):** stáhni [Godot 4.7.2](https://godotengine.org/download/archive/4.7.2-stable/),
otevři v něm složku s projektem (Import → `project.godot`) a spusť hru klávesou F5.
Při prvním otevření editor naimportuje projekt – to je v pořádku.

Doporučeno: myš a klávesnice, grafická karta s podporou Vulkanu (renderer Forward+).
Hra se sama uloží po každé dokončené zakázce; ručně uložíš F5 (nebo v menu Esc), načteš F9.

## Ovládání

| Klávesa | Akce |
|---|---|
| WASD | pohyb |
| Myš | rozhlížení |
| Shift | rychlejší chůze |
| Mezerník | skok (např. na židli); na žebříku slézt (z výšky sleze hráč po příčkách sám); u kotvy / na zemi odepnout lano |
| E | interakce / zahájit a ukončit mytí okna / zvednout a položit židli nebo kbelík / opřít žebřík / vylézt na žebřík |
| podržet E | zvednout opřený žebřík nebo kbelík |
| W / S na žebříku a laně | nahoru / dolů (pustíš = zastavíš se v té výšce) |
| A / D na laně | posun do stran podél fasády (omezený rozsah) |
| Levé tlačítko | začít mýt okno; v pracovním režimu přitlačit hadr |
| Pravé tlačítko | ukončit pracovní režim |
| F | nastříkat přípravek (v pracovním režimu na místo nástroje) |
| Q | přepnout přípravek (saponát / odmašťovač / profesionální přípravek) |
| Kolečko | přepnout vybavení v ruce; v pracovním režimu přepíná ruční nástroj (hadr, houba, stěrka); při nesení židle ji otáčí |
| LMB na žebříku | zvednout a nést žebřík |
| B | položit nesenou židli |
| R | najít nářadí (modré šipky nad žebříky, židlí a kbelíkem); v pracovním režimu vyždímat hadr / houbičku |
| G | přiložit robota na okno, na které se díváš (Etapa 5) |
| T | talenty v tabletu |
| Tab | pracovní tablet |
| Esc | pauza a nastavení |
| F5 / F9 | rychlé uložení / načtení |

### Tutoriál – okna vlastní firmy
Nová hra začíná na základně u garáže. Úkoly tutoriálu jsou vlevo nahoře (TUTORIÁL · krok x / 9):
pohyb, tablet a přijetí zakázky **Okna vlastní firmy** (3 okna garáže, 120 Kč), pracovní režim, saponát [F],
drhnutí, vymáchání hadru v kýblu, bláto (boční okno) a židle (vysoké okénko vedle vrat). Na konci tutoriál pošle
hráče za první zákaznicí, paní Novákovou. Kroky se samy přeskočí, když je hráč udělá v jiném pořadí.
Tutoriál jde přeskočit v menu pauzy [Esc]. Starší uložení ho nespustí (zakázka garáže je u nich hotová a jde
přijmout jako pravidelný úklid). Kód: `scripts/ui/tutorial.gd`, stav `GameState.tutorial_step`.

### Pracovní režim čištění
1. Přijď k oknu (max. ~2 m), podívej se na něj a stiskni **E** nebo **LMB**.
2. Kamera se přiblíží a před sebou uvidíš ruku s hadrem.
3. **Myš hýbe hadrem po skle** (ne kamerou). Kamera hadr jemně sleduje.
4. **Drž LMB a pohybuj myší** – špína mizí jen tam, kudy hadr projel.
   Samotné držení bez pohybu nečistí.
5. **F** = saponát: namočená špína jde dolů ~4× snáz, stékající kapky vyrývají čisté stopy.
6. **A/D** = přešlápnutí podél velkého okna. Horní část vysokých oken vyžaduje židli.
7. Při 98 % (s talentem Dokonalý lesk 95 %) se okno samo doleští, zazní zvonek a okno se zatřpytí.

### Nástroje (Etapa 2)
| Nástroj | Jak se s ním pracuje |
|---|---|
| Starý hadr | malá plocha, všechny směry; na odolnou špínu slabý |
| Mikrovláknový hadr | širší a silnější, výrazně lepší na mastnotu |
| Houbička | nasaje vodu a přípravek a roztírá je po suchém skle; nasucho čistí slabě; dobrá na bláto |
| Gumová stěrka 25 / 35 cm | lišta se natáčí kolmo ke směru tahu; čistí jen **mokré** sklo, sklo za sebou vysouší; dlouhý souvislý tah = bonus, ostrá otočka ho vynuluje |
| Saponát | běžné namočení skla |
| Odmašťovač | silný na mastnotu (otisky, kuchyňský film) |
| Profesionální přípravek | větší nástřik, déle drží vlhkost, víc povoluje odolnou špínu |

### Typy nečistot
Prach, zaschlé kapky, ptačí trus (jako v Etapě 1), **bláto** (nasucho skoro nejde, s vodou ano),
**mastnota** (voda nestačí, potřebuje odmašťovač), **pyl** (jde dobře i nasucho, mokrý se roztírá),
**silná špína** (tvrdá krusta navrchu, pod ní měkčí vrstva). Druhy špíny na okně ukáže nápověda při začátku mytí
a seznam u zakázky v tabletu. Když nástroj skoro nečistí, hra po chvíli poradí proč.

### Obchod, inventář, talenty
* Obchod **Smíšené zboží** na návsi (zelená značka na mapě): [E] u pultu. Tablet ukazuje stejný katalog jen k prohlížení.
* Inventář v tabletu: výběr aktivního nástroje.
* Talenty v tabletu: 1 bod za každou novou úroveň, tři větve (Zručnost, Technika, Podnikání).
  Talenty z pozdějších etap jsou vidět, ale zatím nejdou odemknout.
* Hotovou zakázku lze přijmout znovu jako **pravidelný úklid** (okna se znovu zašpiní, 60 % odměny).
* Bonus za rychlost je nepovinný – čas se počítá jen když je zakázka aktivní.

### Poptávky z vesnice a pověst
* Devět domů na vsi jsou zákazníci. V tabletu (Zakázky → Poptávky z vesnice) visí 2–4 poptávky:
  různé situace (běžné mytí, po bouřce, ptáci na stromě, jarní pyl, mastná okna, roky nemyto),
  různý rozsah (přední okna, tři okna, celý dům) a někdy nepovinný bonus, když zákazník spěchá.
* Po přijetí se okna domu zašpiní podle situace. Po dokončení přijde nová poptávka. Nechtěnou poptávku lze odmítnout.
* Za každou hotovou práci roste **pověst** (★ až ★★★★★). Vyšší pověst = víc poptávek najednou,
  náročnější a lépe placené situace (mastnota od ★★, zanedbaná okna od ★★★), +5 % k odměnám za každou hvězdu
  a lepší vybavení v obchodě (profesionální přípravek a tryska od ★★, stěrka 35 cm od ★★★).
* Stálý zákazník (už jsi u něj pracoval) přidá 10 %.

### Práce ve výškách (Etapa 3)
* **Předměstí Javorov** (Oblast II) – jezdí se tam autobusem z návsi (jízdní řád u zastávky), od úrovně 4.
  Patrové rodinné domy, moderní vila, kavárna, obchody s byty, bytový dům (4 podlaží) a škola (3 podlaží).
  Všechny budovy mají za okny zařízené místnosti (obývák, ložnice, kuchyň, kavárna, pekárna, květinářství,
  třídy, kabinet, schodiště…) s patry, lampou a teplým světlem. Každé patro má dispozici: přední a zadní řada
  pokojů, mezi nimi chodba, do které vedou dveře z pokojů (úzké pokoje mají dveře do sousedního), boční okna
  jsou na konci chodby a ve vícepatrových domech je v chodbě schodiště. Je to low-poly kulisa bez kolizí, dovnitř se nechodí.
  Žebříky, které neneseš, jedou autobusem s tebou a leží u zastávky.
* **Žebřík** (malý 4,2 m, výsuvný 6 m): kup v obchodě, objeví se opřený o garáž. LMB = zvednout, u zdi
  E/LMB = opřít (zelený náhled = jde to), E = vylézt, W/S = nahoru/dolů, zastavíš se kdekoli.
  Z žebříku se myje jako obvykle (E), dosah se počítá od nohou. Slézt jde jen dole (mezerník).
* **Lano a úvazek**: na střeše bytového domu / školy (schodiště u vchodu) jsou kotvicí body. E = připnout,
  S/W = dolů/nahoru, A/D = do stran (±2,4 m, s talentem víc). Délka lana 30 m. Odepnout se jde nahoře u kotvy
  nebo dole na zemi. Nejde o fyzikální simulaci lana – hráč „visí“ na rovině fasády, je to stabilní.
* **Bezpečnost**: pád z výšky přes 3,2 m hráče nezraní – hra ho vrátí na poslední bezpečné místo.
  Uložení na žebříku / laně uloží místo u paty žebříku / na střeše.
* **Nové vybavení**: teleskopická tyč s mopem a se stěrkou (+1,7 m dosahu), elektrický kartáč (silná špína,
  trus, bláto), tlakový rozprašovač (nástřik oken až na 7 m, např. patro ze země), speciální prostředek na odolné nečistoty.
* **Nádržka rozprašovače**: rozprašovač má omezený počet nástřiků (základ 30, tlakový rozprašovač +15,
  zádová nádrž +30, talent Velká nádržka ×1,5 / ×2). Doplňuje se u vody (kohoutek, sud, kýbl v garáži) spolu
  s vymácháním nástroje. Mýt jde i nasucho, ale zhruba 2–3× pomaleji; HUD ukazuje „nádržka x / y“.
  Talent Automatický zavlažovač oken je v stromu připravený, ale funkční bude až v Etapě 4.
* **Hledání oken a nutné vybavení**: nad každým neumytým oknem aktivní zakázky je žlutá značka ▼ (vidět i přes zeď).
  Oranžová značka s popiskem (žebřík, dlouhý žebřík, lano) = na okno se svým vybavením zatím nedosáhneš.
  Tablet u každé zakázky ukazuje „Nutné vybavení“ (počítá se z výšky oken a dosahu) s ✔ máš / ✖ chybí a při
  přijetí zakázky bez potřebného vybavení přijde upozornění. Skoro hotové okno (95,5 %+) se při odchodu dočistí samo.
* **Talenty Etapy 3**: Dlouhý dosah (tyče ×1,2), Výškový specialista (rychlejší lano, větší rozsah do stran),
  Technický génius (elektrické nástroje ×1,25).

### Roboti na okna (Etapa 5)
* **Firma = hráč + roboti** (žádní zaměstnanci). V obchodě (kategorie Technologie) jsou **Robot Mini**
  (úroveň 9, pověst ★★★★, 3 200 Kč), **Robot Pro** (úroveň 11, ★★★★★, 7 800 Kč) a **Robot Max** (úroveň 13, ★★★★★, 14 500 Kč).
  Firma může mít **až 4 roboty** v libovolné kombinaci; stejné modely se číslují (Robot Mini 1, 2…).
  **Výměna**: u lepšího modelu je v obchodě tlačítko „Vyměnit za …“ – nejslabší horší robot se vrátí za polovinu
  jeho ceny a doplatíš rozdíl. Nový robot je nabitý a u tebe. [G] přikládá nejdřív nejlepší nabitý model.
* **[G]** = přiložit robota na okno rozpracované zakázky. Robot si sklo sám nastříká a projíždí ho po řádcích
  (čisté řádky jen rychle přejede), dokud okno není hotové nebo dokud nedojde baterie. Mezitím můžeš mýt jiné okno.
  Robot Mini umyje běžné okno bungalovu asi za 1,5–2 minuty na jedno nabití; silnou špínu a trus zvládá hůř –
  když už nepostupuje, zastaví se a okno dočistíš ručně.
* **[E] na robota** = sundat ho (jde k tobě). Kontrolka: modrá = myje, zelená = hotovo, červená = vybitý, oranžová = dál to nezvládne.
* **Nabíjecí stojany**: v garáži na základně a na boku poboček obchodu na Předměstí a ve Městě.
  Stojan má 4 místa. [E] u stojanu = dát roboty nabíjet, znovu [E] = vzít si je. Mini se nabije za 60 s, Pro za 75 s, Max za 80 s.
* **Tablet → Roboti**: stav, baterie a kde který robot je; s talentem tlačítko přivolání.
* **Strom Robotika** (4. větev talentů): Rychlé nabíjení, Větší baterie, Pečlivá podložka (odolnější špína),
  Dálkové přivolání, Turbo režim a na konci pro radost
  **Přísavné rukavice** – zamiř na zeď budovy a stiskni [E], vylezeš po ní (nahoře na střechu, dole seskočíš;
  do stran jen ±2 m). V Podnikání teď funguje Servisní smlouva (roboti −15 %) a Automatizace (roboti ×1,25).
* **Opravy po testu Etapy 4**: do koše plošiny jde nastoupit i zespodu tam, kde zůstal stát (dole na chodníku);
  lana vedou z kladek na výložníku do navijáků v koši; tablet ukazuje zakázky jen z oblasti, kde jsi
  (rozpracované vždy, přepínač „Všechny oblasti“).

### Firemní dodávka a základna (Etapa 5)
* V obchodě v kategorii **Firma**: **Dílna v garáži** (úroveň 6, ★★, 12 000 Kč) – garáž dostane regály, nářadí
  a světlo, stojan v garáži nabíjí 2× rychleji. **Firemní hala** (úroveň 10, ★★★★, 30 000 Kč, nejdřív dílna) – nová
  budova vedle garáže s velkými vraty, stojanem s rychlonabíjením 3× a nástěnkou zakázek ze všech oblastí;
  všechny odměny za zakázky +5 %. **Firemní dodávka** (úroveň 7, ★★★, 26 000 Kč) – parkuje u základny.
* **Tablet → Firma a dodávka**: tlačítka Základna / Náves / Předměstí / Město odvezou hráče odkudkoli (jen když
  zrovna nevisí na laně nebo nestojí na žebříku). Karta Základna ukazuje stav, rychlost nabíjení a bonus.
* **Nabíjecí stojan na dodávce** (zadní dveře, 4 roboti): roboti se v něm nabíjejí i za jízdy a jedou s dodávkou.
  Cestou autobusem ani dodávkou se roboti, které neseš, nedobíjejí (talent Nabíjení na cestách byl zrušen,
  starší uložení dostane talentový bod zpět; Turbo režim teď navazuje na Větší baterii).
* **Žebříky na střeše dodávky**: dodávka přijede s tebou do cíle (zaparkuje u ulice kousek od místa, kde
  vystoupíš) a žebříky z jiných oblastí vezou na střešním nosiči (2 místa). [E] u dodávky = sundat žebřík
  ze střechy, s žebříkem v ruce [E] na dodávku = naložit. Kde dodávka stojí, se ukládá.
  Autobusem jezdí žebříky dál na zastávku; ve Městě už nezapadají do chodníku.
* Oprava: vrata garáže měla neviditelné sklo, takže se do garáže (ke stojanu) nedalo vejít. Teď je to volný průchod;
  nápis CLEAR VIEW nad vraty je v jednom řádku, aby ho nezakrývala střecha.

### Velkoměsto a drony (Etapa 6)
* **Velkoměsto Horizont** (Oblast IV, od úrovně 14) – autobusem z návsi i z Města (další sloupek zastávky)
  nebo dodávkou. Bulvár se čtyřmi mrakodrapy: Věž Aurora (18 pater), Horizont Tower (28 pater, art-deco koruna),
  obchodní centrum OC Horizont s výlohami a Rezidence Panorama (14 pater). Pobočka obchodu, voda, náměstí s fontánou.
* **Výtahy**: u vchodu mrakodrapu [E] = výtahem na střechu, nahoře domek se schodištěm vede zpět dolů. Na střeše
  je závěsná plošina, která sjede až na chodník (s **Turbo navijáky** z obchodu 2× rychleji).
* **Létající drony**: v obchodě (Technologie) nejdřív **Depo dronů** (15 000 Kč, stojí na náměstí), pak drony
  **Vážka**, **Albatros** a **Sokol** (do 3, každý rychlejší a s větší výdrží). S autopilotem drony samy létají
  nad ulicí k oknům rozpracované zakázky ve Velkoměstě – od nejvyšších pater dolů –, myjí je, a když jim dochází
  baterie, vrátí se do depa nabít a pak pokračují. Hráč mezitím myje nižší patra nebo jede plošinou.
  Okno, na kterém dron neuspěje (trus, silná špína), přeskočí a ohlásí; v tabletu jde přeskočená okna zkusit znovu.
* **Tablet → Drony**: stav depa, zapnutí/vypnutí autopilotu (vypnutí = drony domů), karty dronů s baterií a stavem.
* **6 velkých zakázek** (6 500 – 42 000 Kč): výlohy OC, Aurora nižší a vyšší patra, OC pásová okna, Panorama
  vyšší patra a **finále – Horizont Tower, vrchní patra**. Po finále přijde zakončení kariéry (statistika).
  Velkoměsto má i vlastní poptávky na vstupní haly.
* **Talenty Robotiky (Etapa 6)**: Rychlé vrtule (drony rychleji létají), Výdržné baterie (delší práce),
  Přesné trysky (silnější mytí dronem); Rychlé nabíjení platí i pro drony.
* **Celá budova kolem dokola**: zakázka *Rezidence Panorama – celá budova* (úroveň 17, 75 000 Kč, 7 500 XP) –
  182 oken od 1. do 13. patra na všech čtyřech stranách, na každé straně střechy je závěsná plošina (1. a 2. patro
  jde i ze žebříku). Za každé patro umyté kolem dokola **+300 XP bonus** (statistika „patra kolem dokola“).
  Drony létají i k bočním a zadním oknům – letovou hladinu zvednou nad střechu, ať neletí skrz budovu.
  Nově přijatá zakázka začíná od nuly: okna umytá dřív v jiné zakázce se zase zašpiní.
* **Drony**: v obchodě je jde prodat za polovinu ceny nebo vyměnit za lepší model (starý se odečte z ceny);
  při mytí stříkají vodu (proudy kapek a mlha) a visí o 0,4 m dál od fasády (delší mycí rameno).
  Kabel stojanu na dodávce vede do karoserie.
* Mapa: popisky značek se už nepřekrývají (posunou se pod sebe, u kraje doleva).
* **Opravy po testu Etapy 6**: na plošině se místo „lano 43 / 30 m“ ukazuje výška nad zemí; text „V ruce /
  Přípravek“ vpravo dole se při dlouhém názvu rozšiřuje doleva a nepřetéká z obrazovky; pobočka obchodu ve
  Velkoměstě už nestojí v budově; koš plošiny visí o 0,5 m dál od fasády (neprojíždí římsy a parapety),
  na okna z něj dosáhneš stejně; dodávka na základně parkuje o kus dál od haly, aby byl přístup ke stojanu.

### Závěrečná etapa (Etapa 7)
* **Zrcadlová skla mrakodrapů**: Aurora a Horizont Tower mají skoro zrcadlová skla (odrážejí město a oblohu),
  OC a Panorama napůl; každá věž má vlastní tón (modrozelený, bronzový…). Vstupní haly zůstaly průhledné.
  Špinavé zrcadlové okno je vidět, umyté se leskne.
* **Větší město v pozadí**: dva prstence výškových budov (40–240 m) kolem Velkoměsta, část zrcadlových,
  část kamenných s římsami a stupňovitými korunami. Jsou jen kulisa, nedá se k nim dojít.
* **Živé město**: v Brodci jezdí auta, sem tam autobus a dvoučlánková tramvaj (staví na zastávce 8 s),
  v Horizontu auta v obou směrech. Vozidla nemají kolizi, ale před hráčem v pruhu zastaví a počkají.
  Stará stojící tramvaj s rozbitými okny je pryč.
* **Dodávka**: čelní sklo leží na šikmém čele kabiny a nevyčnívá; dodávka stojí vždy zaparkovaná.
* **Ptáci**: hejna krouží kolem Aurory, Horizont Tower a Panoramy. Občas (asi jednou za 1,5–3 minuty) jeden
  slétne k rozdělanému oknu aktivní zakázky blízko hráče a kápne na něj (na hotová okna nikdy). Trus se uloží.
* **Bouřka**: zhruba každých 20–30 minut hraní (poprvé po 12–18 minutách, od úrovně 2) se zatáhne, prší a hřmí
  (déšť se pod střechou nezobrazuje). Když přejde, ozvou se až 2 zákazníci s poptávkou „Po bouřce“ navíc
  (o 20 % lépe placenou). Rozdělaná okna bouřka nekazí.
* Bouřku i ptačí trus jde vypnout v **Nastavení**.
* **Ruce a nástroje**: ruka je v pracovní rukavici (šedá s modrou dlaní, oranžová manžeta) s klouby prstů;
  v ruce se nástroj opravdu drží (prsty kolem rukojeti). Nové modely rozprašovače, stěrky (žlab, guma, koncovky,
  rukojeť s kroužky), kartáče (chomáče štětin), houbičky a hadru.
* **Úchopy (po testu)**: u elektrického kartáče se při mytí točí jen kotouč se štětinami, tělo strojku a ruka stojí.
  Ruka svírá teleskopickou tyč, skládací mop, rukojeť stěrky i tělo kartáče (prsty kolem rukojeti).
* **Výkon**: maska špíny okna (desítky ms na okno) se generuje ve vedlejším vlákně, ne v hlavním – při chůzi
  kolem oken a ve Velkoměstě už hra nezasekává. Shadery všech oblastí se zkompilují při načítání.
* **Načítací obrazovka** s průběhem stavby oblastí a střídajícími se tipy.
* **Opravy po 3. testu**: drony ve Velkoměstě míří mycí hlavou ke sklu (dřív byly otočené o 180°); plošina
  sjetá úplně dolů stojí na chodníku a podlaha koše jím neprojde; kola aut, autobusů a dodávky už neproblikávají
  (pneumatika bez náhodného posunu vrcholů, poklice je tenký disk vně pneumatiky); příčka mezi místnostmi se
  posune k nejbližšímu kraji bočního okna, místo aby vedla přes něj; židle u psacích stolů a stolů kuchyně,
  kavárny a třídy jsou otočené ke stolu (ve třídě žáci sedí čelem k tabuli).

### Rotační kartáče a vyvážení nástrojů (12. 11.)
* **Rotační kartáč na teleskopické tyči** (`brush_tele`, 2 600 Kč, úroveň 7, pověst ★★★): točí se a myje sám,
  hráč ho jen přitlačí [LMB] a pomalu s ním jezdí po skle – žádné drhnutí ze strany na stranu. Dosah +1,7 m,
  hlava 20 cm, počítá se jako teleskopická tyč (dosah na vysoká okna). Talent Technický génius ho posílí.
* **Ruční elektrický kartáč** se teď taky točí a myje sám (ToolData.spin), má o něco větší hlavu (18 cm).
* Na mokrém skle od točícího se kartáče odletují kapky. V obchodě je u nástrojů vidět „točí se a myje sám“ a dosah.
* **Vyvážení** (měřeno skriptem `scripts/tests/tool_bench.gd` – čas umytí okna 1 × 1,2 m na 90 % pro každý nástroj
  a typ špíny): elektrický stěrač s nádržkou byl za 1 450 Kč pomalejší než stěrka za 520 Kč → síla 7 → 9,
  odolná špína 5 → 3,2, mokré sklo 3,5 → 5. Elektrický kartáč díky rotaci ~30 % rychlejší. Ostatní nástroje
  vyšly v pořádku (hadr < mikrohadr < houbička/mopy < stěrky, kartáče nejlepší na silnou špínu).
* **Nastavení → Grafika**: vyhlazování hran (vypnuto / FXAA / MSAA 2× / 4×), rozlišení 3D 50–100 % (dopočítá
  FSR – plynulejší hra na slabším PC) a celá obrazovka.

### Atmosféra, příroda a vzhled firmy (12. 11.)

* **Denní doba** (`scripts/world/atmosphere.gd`): herní hodina = 60 s, noc 22–5 h běží 4× rychleji. Slunce putuje po obloze, zlatá hodinka barví oblohu i mraky, v noci svítí okna domů a pouliční lampy (skupina `street_lights`). Na HUD je „Den N · čas · období".
* **Roční období** (2 herní dny každé): jaro s okvětními lístky, léto, podzim s barevnými stromy a padajícím listím, zima s holými stromy, sněhem na trávě, kopcích a střechách a jinovatkou na skle ráno a v noci. V zimě se bouřka mění ve sněhovou vánici. Obojí jde vypnout v Nastavení.
* **Déšť po skle**: při bouřce stékají po oknech kapky (`rain_glass`), po dešti sklo pomalu oschne. Čisté sklo víc odráží oblohu.
* **Terén a tráva** (`scripts/world/terrain.gd`): mírně zvlněné louky a vyšší hřbety na okrajích venkova, kolem domů, cest a polí zůstává rovina. Hustá kývající se tráva (`shaders/foliage.gdshader`), stromy a květiny stojí na terénu.
* **Fotorežim [P]**: volná kamera bez HUD do 40 m od hráče, kolečko = zoom, T/G = posun času, Enter/F12 uloží snímek do `user://fotky`.
* **Vzhled firmy** (`scripts/world/cosmetics.gd`, tablet → Firma): lak dodávky, polep (pruh a nápis) a pracovní oblečení (barva rukávů). Každou barvu koupíš jednou, pak přepínáš zdarma.
* Globální parametry shaderů jsou v `project.godot` v sekci `[shader_globals]`.

### Město (Etapa 4)
* **Město Brodec** (Oblast III) – autobusem z návsi i z Předměstí (druhý sloupek zastávky), od úrovně 8.
  Hlavní třída a náměstí s obchodním domem (výlohy), činžovními domy, hotelem a výškovou budovou Meridian.
* **Pobočky obchodu s vybavením** stojí v Předměstí i ve Městě – stejný sortiment a ceny jako na návsi,
  pro nákup se už nemusí jezdit zpátky.
* **Schodiště ze střechy**: na střechách s kotvicími body je domek se schodištěm (E = sejít dolů).
* **Závěsná plošina** (od úrovně 8, licence v obchodě): E = nastoupit, W/S = nahoru/dolů, A/D = do stran,
  mytí z plošiny jako z lana. Dole i nahoře se dá vystoupit.
* **7 zakázek na výškových budovách** (výlohy, patra činžáků, hotel, Meridian – nižší a vyšší patra), Město má vlastní poptávky.
* **Nové vybavení**: elektrický stěrač s nádržkou (sám dávkuje přípravek, má vlastní zásobník, doplňuje se u vody),
  skládací mop (+1,7 m, při plném vysunutí slabší).
* **Talenty Etapy 4**: Automatický zavlažovač oken (na laně/plošině sám nastříká okno), Městský profík (mytí ×1,1),
  Městské kontakty (městské zakázky +15 %), Servisní smlouva (levnější roboti, připraveno na Etapu 5).
* Firma = hráč + roboti (Etapa 5) a létající drony s depem (Etapa 6), žádní zaměstnanci.

## Struktura projektu

```
scenes/main.tscn            vstupní scéna (vše ostatní staví skripty)
scripts/main.gd             sestavení světa, hráče a UI
scripts/autoload/           globální systémy: Events, GameState, ContractManager,
                            WindowRegistry, SaveManager, Audio, Settings, WorldMap, InputSetup,
                            Talents (TalentManager), Shop
scripts/cleaning/           DirtMask (maska špíny), DirtTypes, DirtProfile, CleanableWindow, ToolData (Resource)
scripts/player/             Player, CleaningController (pracovní režim), HandRig, HeldItems
scripts/interact/           Chair, Ladder (žebřík), RopeAnchor (kotvicí bod), SuspendedPlatform, ClimbGrip, SimpleInteractable
scripts/robots/             WindowRobot (robot na okna), RobotFleet (správa robotů), RobotCharger (stojan)
scripts/contracts/          ContractData (Resource)
scripts/world/              Countryside (oblast Venkov + autobus), Suburb (Předměstí), HouseBuilder, Nature, Props
scripts/core/               MeshBuilder (low-poly meshe), Mats (sdílené materiály)
scripts/ui/                 HUD, Tablet, MapView, Notifications, UIRoot, SettingsPanel, ShopPanel, TalentTree
scripts/tests/autotest.gd   automatický test hlavní herní smyčky
shaders/                    glass_dirt (sklo + špína), ground, clouds
data/tools/*.tres           definice nástrojů (nový nástroj = nový .tres)
data/contracts/*.tres       definice zakázek (nová zakázka = nový .tres)
data/dirt/*.tres            profily špíny (kolik které nečistoty má okno)
data/talents/*.tres         talenty (cena, předpoklady, účinek)
scripts/talents/            TalentData (Resource)
```

### Jak funguje mytí oken
* Každé okno má vlastní `DirtMask` (~110 px/m): pole špíny, odolnosti a vlhkosti (poloviční rozlišení).
* Maska se generuje procedurálně ze seedu podle `window_id` (prach, šmouhy po dešti, zaschlé kapky, ptačí trus),
  takže se ukládá jen rozpracovaný stav.
* Tah hadru = řada překrývajících se otisků po dráze mezi snímky, odebrané množství je úměrné ujeté dráze.
* Textura se nahrává na GPU jen když se maska změnila. Vzdálená okna (> 40 m) masku vůbec nemají,
  shader pak kreslí levnou procedurální náhradu.
* Procento čistoty = 1 − zbývající špína / počáteční špína.

### Ukládání
`user://savegame.json` s klíčem `version` (aktuálně 9, starší uložení se automaticky převedou) a migrací v `SaveManager._migrate()`.
Ukládá se pozice hráče, peníze, XP, úroveň, inventář, statistiky, historie, stav zakázek,
pozice židle a žebříků, odemčené oblasti a maska každého rozpracovaného okna (komprimovaná). Automatické uložení po dokončení zakázky.

## Automatický test

```
godot --headless --path . -- --autotest
```
Projde: pohyb, zamčené okno bez zakázky, pracovní režim, přiblížení kamery, přitlačení bez pohybu,
tah myší (čistí se jen dráha), omezení dosahu, saponát, židli (zvednout/položit/vyšší dosah),
uložení/načtení rozpracovaného okna, dokončení všech oken, odměnu, XP, historii, autosave a tablet.
Etapa 2: typy nečistot na nových oknech, bláto/mastnota/silná špína/stěrka/houba (porovnání nástrojů),
stěrka v pracovním režimu, obchod (ceny, úroveň, peníze), talenty a jejich účinky, dokončení všech nových zakázek,
pravidelný úklid, uložení v2 a migrace uložení z Etapy 1.
Etapa 3: Předměstí (okna, zakázky, zamčení pod úrovní 4), autobus, mapa oblasti, poptávky z Předměstí,
žebřík (koupě, cesta autobusem, nesení, opření o zeď, lezení W/S, zastavení, mytí horního okna, seskok jen dole,
uložení a načtení), teleskopická tyč, elektrický kartáč, talenty, speciální chemie, tlakový rozprašovač,
kotva a lano (bez setu nejde, spouštění, zastavení, rozsah do stran, mytí ve 3. patře, odepnutí nahoře a dole),
bezpečný návrat po pádu ze střechy a migrace uložení v2 → v3. Opravy: žádné okno není zakryté zdí (paprsek zvenku
na 5 místech skla), za každým oknem zakázek Předměstí je zařízená místnost, nádržka (spotřeba, prázdná, doplnění,
kapacita z vybavení a talentu, uložení), mytí nasucho je pomalejší než po nástřiku.
Etapa 4: Město (zamčení pod úrovní 8, autobus), pobočky obchodu, schodiště ze střech, poptávky, nutné vybavení,
plošina (nastoupení, pohyb, mytí, zavlažovač, vystoupení), dokončení všech 7 městských zakázek, Městské kontakty,
Servisní smlouva, elektrický stěrač a skládací mop, migrace uložení v3 → v4.
Etapa 5: nástup do plošiny zespodu, lana a navijáky, tablet podle oblasti, roboti (obchod, podmínky, přiložení [R],
mytí, vybití, přerušená zakázka, sundání, stojany, nabíjení, talenty, přivolání, uložení
a načtení), migrace v4 → v5, přísavné rukavice (zeď garáže, výstup na střechu), 4 roboti (nákup, číslování, maximum,
stojan na 4), výměna Mini → Max (doplatek, protiúčet), uložení 4 robotů, migrace v5 → v6, základna (dílna,
hala, rychlonabíjení, bonus k odměnám, vstup do garáže a haly), dodávka (cesty, dobití robotů, uložení).
Etapa 6: Velkoměsto (zamčení pod úrovní 14, cesta, okna dosažitelná plošinou), výtahy, depo a drony (koupě,
podmínky, let, mytí, nabíjení, přeskočení, dva drony na různých oknech, vypnutí autopilotu, uložení a načtení),
talenty dronů, turbo navijáky, všech 6 zakázek včetně finále, migrace v6 → v7; stojan na dodávce (přístup na všech
parkovištích, robot jede s dodávkou), zrušené dobíjení cestou a vrácení bodu (migrace v7 → v8), plošina dál od zdi,
pobočka mimo budovu.
Celá budova (182 oken, 4 plošiny, dosah, patro z id, bonus za patro, trasa dronu nad střechou), prodej a výměna dronů,
sprška dronu.
Etapa 7: doprava (jízda, zastavení před hráčem, odstup, návrat na začátek, tramvaj na zastávce, bez kolize),
ptáci (mimo budovy, trus na rozdělaném okně, uložení, ne na hotové okno, přílet a návrat), bouřka (zatažení, déšť,
poptávky po bouřce, vyjasnění). Dron v otočeném depu míří ke sklu. Tutoriál (kroky, zakázka garáže, přeskočení, uložení, migrace v8 → v9). Aktuálně 603 OK, 0 FAIL. Snímky: `CLEARVIEW_SET=tut`, `base`, `lad`, `metro`, `7`, `9` (opravy 3. kola).

## Stav – Etapa 7
Hotovo: zrcadlová a tónovaná skla mrakodrapů, panorama velkoměsta v pozadí, projíždějící auta, autobusy a tramvaj
(Brodec, Horizont), opravené čelní sklo dodávky, hejna ptáků s trusem na rozdělaných oknech, bouřky s poptávkami
„Po bouřce“, přepínače v Nastavení, ruka v pracovní rukavici a nové modely nástrojů.
Příčky mezi místnostmi se už nenapojují doprostřed bočních oken (ověřeno snímky, ne automatickým testem).
Otočení židlí a poloha příček nemají automatický test, jen kontrolu na snímcích (`CLEARVIEW_SET=9`).
**Zatím nejsou implementované:** bonusové budovy inspirované slavnými stavbami, obtížnost Perfekcionista,
déšť jako mechanika (méně saponátu, šmouhy), skutečné nahrané zvuky (vše je syntetizované), lidé na ulicích.
Známá omezení: vozidla nemají kolizi a na konci ulice se objeví znovu na začátku; ptáci nemají kolizi;
časovač bouřky se neukládá (po načtení začne znovu); déšť padá i do průjezdů a pod stromy (schová se jen pod střechou).

## Stav – Etapa 6
Hotovo: Velkoměsto Horizont se 4 mrakodrapy (288 oken k mytí, Rezidence Panorama kolem dokola), výtahy na střechy, plošina až na chodník, turbo
navijáky, depo a 3 létající drony s autopilotem, sekce Drony v tabletu, 6 velkých zakázek včetně finále,
3 nové talenty Robotiky, statistika oken umytých drony, mapa bez překrývání popisků, nabíjecí stojan na dodávce,
uložení v8.
**Zatím nejsou implementované:** bonusové budovy inspirované skutečnými stavbami z celého světa, počasí,
obtížnost Perfekcionista, oprava grafiky interiérů a celková úprava vzhledu (Etapa 7); skutečné zvuky,
model ruky a lepší modely nástrojů (backlog).
Známá omezení: drony létají jen ve Velkoměstě a z jednoho depa; drony nemají kolize (proletí i hráčem);
kolem dokola se myje jen Rezidence Panorama, u ostatních mrakodrapů jen přední fasády; dodávka nemá animaci jízdy.

## Stav – Etapa 5
Hotovo: roboti na okna Mini, Pro a Max (až 4 ve firmě, výměna slabších za lepší), nabíjecí stojany na 4 roboty (základna a pobočky), sekce Roboti v tabletu, firemní dodávka, dílna a firemní hala, strom Robotika
se 7 talenty včetně Přísavných rukavic, Servisní smlouva a Automatizace pro roboty, statistika oken umytých roboty,
uložení v6, opravy plošiny a filtr zakázek podle oblasti.
**Zatím nejsou implementované:** létající drony s depem, Velkoměsto a mrakodrapy (Etapa 6), lešení, počasí
a obtížnost Perfekcionista (v plánu), oprava grafiky interiérů (stěny vidět v oknech) a celková úprava vzhledu
(závěrečná etapa); skutečné zvuky, model ruky a lepší modely nástrojů (backlog).
Známá omezení: robot se přikládá jen na okno rozpracované zakázky; Přísavné rukavice nehlídají konec zdi
do stran (rozsah je jen ±2 m); robot nemá vlastní zvuk; dodávka
neodjíždí jako animace (cesta je okamžitá jako autobus) a stojí jen u základny; kosmetika firmy zatím není.

## Poznámky z testování (2026-11-14)
* **Kompas** nahoře místo mapy: zlatá značka vede k přijaté zakázce (vzdálenost pod kompasem), u budovy se rozsvítí šipky ▼ nad špinavými okny. Mapa [M] je pryč.
* **[R] najít nářadí** (modré šipky a značky na kompasu), robot je na **[G]**, talenty na **[T]**.
* Výrazná karta nové úrovně, svítící upozornění na nerozdaný talentový bod pod úrovní (zhasne po otevření stromu), strom talentů bez posouvání.
* Hadr a houbička se zanáší špinavou vodou (čistí až o třetinu hůř), **[R] při mytí vyždímá**, vymáchání ve vodě vyčistí úplně. Lepší nástroje se zanáší pomaleji (ToolData.soil_rate).
* **Kbelík s uchem** (90 Kč): nosí se jako židle, voda na 6 vymáchání, u sudu / kohoutku se sám naplní. Ubylo sudů u chaty, skleníku, na Předměstí a ve městě.
* **Prst** (vybavení v ruce, vždy k dispozici): kreslení do prachu na skle.
* Autobus přijíždí a odjíždí (BusRide), zatmívačka při nástupu.
* Opravy: lavička u chaty, kapky deště stékají dolů, blikání jemných vzorů na skle (pyl ve skleníku), výraznější nástřik, barvy tlačítek zakázek, rady se žebříkem místo židle, nástroj nezajíždí do skla, žebřík [podrž E], pomalejší růst rychlosti mytí (Pevná ruka 6/12 %, Mistr čistoty 12 %, mikrohadr 5.4, stěrka 35 cm 10.5).

## Stav – Etapa 4
Hotovo: Město Brodec, autobus z návsi i Předměstí, pobočky obchodu, schodiště ze střech, závěsná plošina s licencí,
7 městských zakázek, elektrický stěrač, skládací mop, talenty Etapy 4, uložení v4. Opravy Předměstí: chodníčky ke dveřím,
parkoviště, schodiště v interiérech jen do patra nad sebou s otvorem ve stropě, okno vily za obkladem.
**Zatím nejsou implementované:** roboti a strom Robotika (Etapa 5), létající drony s depem (Etapa 6), lešení,
počasí a obtížnost Perfekcionista (v plánu); skutečné zvuky, model ruky a lepší modely nástrojů (backlog).

## Stav – Etapa 3
Hotovo: Předměstí Javorov s 8 budovami a 62 omyvatelnými okny, autobus mezi oblastmi, mapa po oblastech,
5 příběhových zakázek (patrový dům, kavárna, vila, bytový dům, škola), poptávky od 4 zákazníků z Předměstí,
žebříky, kotvicí body a slaňování, teleskopické tyče, elektrický kartáč, tlakový rozprašovač, speciální chemie,
talenty Etapy 3, uložení v3, interiéry budov, nádržka rozprašovače s doplňováním.

## Stav – Etapa 2
Hotovo: nástroje, typy nečistot, obchod, inventář, talenty (Etapa 2), 4 nové zakázky (chata, skleník, výlohy obchodu, statek s chlévem),
pravidelný úklid, uložení v2. **Zatím nejsou implementované:** žebříky, teleskopické tyče, lešení, plošiny, Předměstí a další oblasti,
roboti, drony (v tabletu a obchodě označené „připravujeme“ / „brzy“).
