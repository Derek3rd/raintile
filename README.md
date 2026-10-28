# Raintile

Skin per [Rainmeter](https://www.rainmeter.net/) che sostituisce le icone del desktop con un launcher a tile:

- una barra in alto con le **categorie** (Giochi, App, Link, Sistema, ...)
- una griglia di **NX × NY tile** visibili, con scorrimento **verticale o orizzontale** tramite la rotellina
- ogni tile ha **sfondo**, **icona**, **etichetta** e **comando**

## Installazione

1. Clona o copia questa cartella in `Documenti\Rainmeter\Skins\Raintile`
2. In Rainmeter: *Aggiorna tutto*, poi carica `Raintile\Raintile.ini`
3. Consigliato: tasto destro sulla skin > *Impostazioni* > *Posizione* > *Sul desktop*, così resta sotto le finestre come le icone

## Configurazione

Tutto si modifica da due file (anche dal menu del tasto destro della skin):

| File | Contenuto |
| --- | --- |
| `@Resources\Settings.inc` | griglia (`NX`, `NY`, `ScrollDir`), dimensioni, colori, font |
| `@Resources\Tiles.ini` | elenco categorie e tile |

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

`Command` accetta un programma (con argomenti), un URL o protocollo (`steam://`, `https://`, `ms-settings:`), un percorso, oppure bang di Rainmeter tra parentesi quadre (`[!ActivateConfig "..."]`).

Dopo aver salvato: tasto destro > *Aggiorna skin*. Se cambi `NX`, `NY` o l'elenco delle categorie, la griglia viene rigenerata da sola (vedi sotto).

## Come funziona (e perché è leggera)

- **Nessun ciclo di aggiornamento** (`Update=-1`): la skin non fa nulla finché non clicchi, scorri o passi col mouse. A riposo usa 0% di CPU.
- **Numero fisso di meter**: esistono solo gli NX × NY slot visibili, a prescindere da quante tile hai. Scorrere o cambiare categoria cambia soltanto le opzioni degli slot esistenti.
- **Solo le differenze**: lo script ricorda l'ultimo valore impostato su ogni meter e manda a Rainmeter solo quello che è cambiato.
- **Tiles.ini viene letto una volta**, al caricamento della skin.
- **Griglia generata**: i meter di menu e slot stanno in `@Resources\Generated\Grid.inc`, scritto da `Raintile.lua`. Se `NX`, `NY` o le categorie cambiano, lo script lo riscrive e ricarica la skin. Non va modificato a mano.

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
