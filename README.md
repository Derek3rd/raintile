# Raintile

Skin per [Rainmeter](https://www.rainmeter.net/) che sostituisce le icone del desktop con un launcher a tile **a schermo intero**:

- un menu centrato in alto con le **categorie** (Giochi, App, Link, Sistema, ...), mostrate come icona, testo o entrambi
- una griglia di **NX × NY tile** visibili che si ridimensionano da sole per riempire lo schermo, con scorrimento **verticale o orizzontale** tramite la rotellina
- ogni tile ha **sfondo**, **icona**, **etichetta** e **comando**

## Installazione

1. Clona o copia questa cartella in `Documenti\Rainmeter\Skins\Raintile`
2. In Rainmeter: *Aggiorna tutto*, poi carica `Raintile\Raintile.ini`
3. La skin si posiziona da sola nell'angolo in alto a sinistra e copre lo schermo (`ScreenX/Y/W/H` in `Settings.inc`; usa `WORKAREA` invece di `SCREENAREA` per lasciare libera la barra delle applicazioni)
4. Consigliato: tasto destro sulla skin > *Impostazioni* > *Posizione* > *Sul desktop*, così resta sotto le finestre come le icone

## Chiudere e riaprire

- **Chiudere**: la X in alto a destra. Di default scarica la skin (`CloseAction=[!DeactivateConfig]` in `Settings.inc`); con `[!Hide]` la nasconde soltanto.
- **Esc** chiude il launcher (serve il plugin HotKey installato; tasto in `CloseHotKey`). Finché il launcher è caricato il tasto viene intercettato in tutto il sistema: per questo, con `CloseOnLaunch=1` (predefinito), il launcher si chiude dopo aver avviato una tile.
- **Riaprire con una scorciatoia da tastiera** (senza plugin): crea un collegamento sul desktop o nel menu Start con destinazione

  ```
  "C:\Program Files\Rainmeter\Rainmeter.exe" !ToggleConfig "Raintile" "Raintile.ini"
  ```

  poi *Proprietà* > *Tasto di scelta rapida* (es. `Ctrl+Alt+Spazio`). Con `!ToggleConfig` lo stesso tasto apre e chiude il launcher.

## Avvio di una tile

Al click la tile si espande fino a riempire lo schermo (con sfondo e logo a piena risoluzione), resta visibile per `LaunchHold` ms e poi il launcher si chiude. Il comando parte subito, all'inizio dell'animazione. Impostazioni in `Settings.inc`:

| Variabile | Default | Effetto |
| --- | --- | --- |
| `LaunchAnimation` | `1` | `0` = nessuna animazione, chiusura immediata |
| `LaunchAnimFrames` | `15` | passi dell'espansione da 16 ms (15 ≈ 250 ms) |
| `LaunchHold` | `1500` | ms a schermo intero prima di chiudere |
| `LaunchLogoSize` | 1/3 dell'altezza | dimensione finale del logo |

L'animazione usa il plugin ActionTimer (incluso in Rainmeter) e gira solo durante l'avvio: a riposo la skin resta senza aggiornamenti.

## Animazioni

Tutte disattivabili in `Settings.inc` e attive solo mentre qualcosa si muove (un solo "orologio" ActionTimer che lo script ferma appena tutto è fermo):

| Variabile | Animazione |
| --- | --- |
| `AnimOpen` | all'apertura le tile compaiono una dopo l'altra, salendo in dissolvenza |
| `AnimCategory` | al cambio categoria le tile ricompaiono e la pillola del menu scivola sulla nuova voce |
| `AnimHover` | il riquadro di evidenziazione scivola da una tile all'altra e compare/sparisce in dissolvenza |
| `AnimScroll` | scorrimento fluido con la rotellina |
| `AnimLogoZoom` | il logo della tile sotto il mouse si ingrandisce (`HoverLogoScale`, default 1.25); quello appena lasciato torna alla misura normale |

Regolazioni: `AnimAppearFrames` (durata della comparsa di ogni tile, passi da 16 ms), `AnimStagger` (ritardo tra una tile e la successiva), `AnimSlide` (pixel di salita), `AnimSmooth` (morbidezza di hover, pillola e scorrimento: 0.1 lento, 1 istantaneo).

Lo scorrimento fluido usa una riga (o colonna) di tile in più e l'opzione `Container` per tagliarle ai bordi della griglia: serve **Rainmeter 4.5 o successivo**.

## Configurazione

| Dove | Cosa |
| --- | --- |
| `@Resources\Settings.inc` | schermo, griglia (`NX`, `NY`, `ScrollDir`), menu (`MenuMode`), chiusura, colori, font |
| `@Resources\Categories\*.ini` | **un file per categoria**: voce del menu e tile |
| `@Resources\Images\<categoria>\` | immagini della categoria |

Le categorie sono i file presenti in `Categories\`: per aggiungerne una basta creare un nuovo `.ini` (es. `Emulatori.ini`) e aggiornare la skin.

### File di categoria

```ini
[Category]
Name=Giochi        ; testo nel menu (default: nome del file)
Icon=              ; default: Images\Games\icon.png
Order=1            ; posizione nel menu (default: ordine alfabetico)

[Diablo]
Command=steam://rungameid/2344520
```

Ogni sezione diversa da `[Category]` è una tile, nell'ordine del file.

### Immagini

Per la categoria `Games.ini` la struttura è:

```
Images\Games\
  icon.png                 icona nel menu
  background\Diablo.jpg    sfondo della tile [Diablo]
  logo\Diablo.png          logo centrato della tile [Diablo]
```

Di default ogni tile cerca le immagini col **proprio nome** (estensioni `.png`, `.jpg`, `.jpeg`, `.bmp`). Per usare nomi diversi:

| Chiave | Effetto |
| --- | --- |
| `Image=diablo4` | altro nome per entrambe: `background\diablo4.*` e `logo\diablo4.*` |
| `Background=d4_key_art` | sfondo specifico (estensione facoltativa, anche percorso assoluto) |
| `Logo=d4_logo.png` | logo specifico |

Le altre chiavi della tile sono `Command`, `Label` (testo in basso; una tile senza immagini mostra il proprio nome) e `Color` (colore di fondo senza sfondo).

`Command` accetta un programma (con argomenti), un collegamento `.lnk`/`.url`, un URL o protocollo (`steam://`, `https://`, `ms-settings:`), una cartella, oppure bang di Rainmeter tra parentesi quadre.

Dopo aver salvato: tasto destro > *Aggiorna skin*.

## Come funziona (e perché è leggera)

- **Nessun ciclo di aggiornamento** (`Update=-1`): la skin non fa nulla finché non clicchi, scorri o passi col mouse. A riposo usa 0% di CPU.
- **Numero fisso di meter**: esistono solo gli NX × NY slot visibili, a prescindere da quante tile hai. Scorrere o cambiare categoria cambia soltanto le opzioni degli slot esistenti.
- **Solo le differenze**: lo script ricorda l'ultimo valore impostato su ogni meter e manda a Rainmeter solo quello che è cambiato.
- **I file di categoria vengono letti una volta**, al caricamento. L'elenco dei file è memorizzato, così la skin si disegna subito; la cartella viene ricontrollata in background (plugin RunCommand, incluso in Rainmeter) e, se è cambiata, la skin si ricarica da sola.
- **Griglia generata**: i meter di menu e slot stanno in `@Resources\Generated\Grid.inc`, scritto da `Raintile.lua`. Se `NX`, `NY`, `MenuMode` o le categorie cambiano, lo script lo riscrive e ricarica la skin. Non va modificato a mano.
- **Dimensioni calcolate una volta**: la misura delle tile è una formula su `ScreenW`/`ScreenH` risolta al caricamento; il menu viene misurato e centrato una sola volta dopo il primo disegno.
- **Ridisegni ridotti al minimo**: ogni ridisegno di una skin a schermo intero costa, quindi l'evidenziazione della tile sotto il mouse è un solo riquadro gestito dallo script, che ridisegna solo quando cambia davvero tile (`TileHover=0` la disattiva). Scorrendo si aggiornano solo le tile, non il menu. La dissolvenza di apertura e chiusura è disattivata (`FadeDuration=0`, che la skin copia nelle sue impostazioni in `Rainmeter.ini`: vale dal caricamento successivo).
- **Miniature automatiche** (`Thumbnails=1`): Rainmeter decodifica ogni immagine a piena risoluzione quando una tile la mostra e la ridimensiona a ogni disegno. Per questo la skin crea in background (`Scripts\Thumbs.ps1`, PowerShell a bassa priorità) una copia di sfondi e loghi alla misura esatta in cui vengono mostrati, in `Generated\Thumbs\`, e carica quelle. Al primo avvio dopo aver aggiunto immagini si vedono gli originali per qualche secondo, poi la skin passa alle miniature da sola. Se cambi un'immagine, la risoluzione o `NX`/`NY`, le miniature vengono rifatte; quelle non più usate vengono cancellate.

## Struttura

```
Raintile.ini                 skin principale (stili, sfondo, scrollbar)
@Resources/
  Settings.inc               impostazioni
  Categories/*.ini           un file per categoria (voce di menu + tile)
  State.inc                  ultima categoria aperta (scritto dalla skin)
  Scripts/Raintile.lua       logica: lettura tile, rendering, scroll, avvio
  Scripts/Thumbs.ps1         creazione delle miniature
  Generated/Grid.inc         meter generati automaticamente
  Generated/Thumbs/          miniature (si possono cancellare: vengono rifatte)
  Images/<categoria>/        icon.png, background/, logo/
```

## Limiti noti

- Rainmeter non estrae le icone dagli `.exe`: l'icona va fornita come immagine.
- Usa nomi di categorie ed etichette senza lettere accentate: lo script legge i file di categoria come UTF-8 e Rainmeter potrebbe mostrarle in modo errato.
