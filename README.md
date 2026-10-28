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
- **Riaprire con una scorciatoia da tastiera** (senza plugin): crea un collegamento sul desktop o nel menu Start con destinazione

  ```
  "C:\Program Files\Rainmeter\Rainmeter.exe" !ToggleConfig "Raintile" "Raintile.ini"
  ```

  poi *Proprietà* > *Tasto di scelta rapida* (es. `Ctrl+Alt+Spazio`). Con `!ToggleConfig` lo stesso tasto apre e chiude il launcher.

## Configurazione

Tutto si modifica da due file (anche dal menu del tasto destro della skin):

| File | Contenuto |
| --- | --- |
| `@Resources\Settings.inc` | schermo, griglia (`NX`, `NY`, `ScrollDir`), menu (`MenuMode`), spaziature, colori, font |
| `@Resources\Tiles.ini` | categorie (ordine, icona, testo) e tile |

Le immagini vanno in `@Resources\Images\` (oppure si usa un percorso assoluto).

Esempio di tile:

```ini
[Diablo]
Category=Giochi
Background=diablo4.jpg
Icon=
Label=
Command=steam://rungameid/2344520
```

Icona della categoria nel menu (cosa mostrare si sceglie con `MenuMode=IconText|Icon|Text` in `Settings.inc`; una categoria senza icona mostra sempre il testo):

```ini
[Category:Giochi]
Icon=gamepad.png
Label=Giochi
```

`Command` accetta un programma (con argomenti), un URL o protocollo (`steam://`, `https://`, `ms-settings:`), un percorso, oppure bang di Rainmeter tra parentesi quadre (`[!ActivateConfig "..."]`).

Dopo aver salvato: tasto destro > *Aggiorna skin*. Se cambi `NX`, `NY`, `MenuMode` o le categorie, la griglia viene rigenerata da sola (vedi sotto).

## Come funziona (e perché è leggera)

- **Nessun ciclo di aggiornamento** (`Update=-1`): la skin non fa nulla finché non clicchi, scorri o passi col mouse. A riposo usa 0% di CPU.
- **Numero fisso di meter**: esistono solo gli NX × NY slot visibili, a prescindere da quante tile hai. Scorrere o cambiare categoria cambia soltanto le opzioni degli slot esistenti.
- **Solo le differenze**: lo script ricorda l'ultimo valore impostato su ogni meter e manda a Rainmeter solo quello che è cambiato.
- **Tiles.ini viene letto una volta**, al caricamento della skin.
- **Griglia generata**: i meter di menu e slot stanno in `@Resources\Generated\Grid.inc`, scritto da `Raintile.lua`. Se `NX`, `NY`, `MenuMode` o le categorie cambiano, lo script lo riscrive e ricarica la skin. Non va modificato a mano.
- **Dimensioni calcolate una volta**: la misura delle tile è una formula su `ScreenW`/`ScreenH` risolta al caricamento; il menu viene misurato e centrato una sola volta dopo il primo disegno.

Consiglio per le prestazioni: usa immagini di sfondo già ridimensionate più o meno alla dimensione della tile (JPG per gli sfondi, PNG per le icone). Immagini 4K costano memoria senza alcun beneficio visivo.

## Struttura

```
Raintile.ini                 skin principale (stili, sfondo, scrollbar)
@Resources/
  Settings.inc               impostazioni
  Tiles.ini                  categorie e tile
  State.inc                  ultima categoria aperta (scritto dalla skin)
  Scripts/Raintile.lua       logica: lettura tile, rendering, scroll, avvio
  Generated/Grid.inc         meter generati automaticamente
  Images/                    sfondi e icone
```

## Limiti noti

- Rainmeter non estrae le icone dagli `.exe`: l'icona va fornita come immagine.
- Usa nomi di categorie ed etichette senza lettere accentate: lo script legge `Tiles.ini` come UTF-8 e Rainmeter potrebbe mostrarle in modo errato.
