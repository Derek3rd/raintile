[Variables]
; --- Schermo -------------------------------------------------------------------
; Il launcher occupa tutto lo schermo. Per lasciare libera la barra delle
; applicazioni usa WORKAREA al posto di SCREENAREA; per un altro monitor
; aggiungi @N (es. #SCREENAREAWIDTH@2#).
ScreenX=#SCREENAREAX#
ScreenY=#SCREENAREAY#
ScreenW=#SCREENAREAWIDTH#
ScreenH=#SCREENAREAHEIGHT#

; --- Griglia -----------------------------------------------------------------
; Tile visibili di default: NX colonne x NY righe. Ogni categoria puo' avere
; la sua griglia (NX=, NY= nella sezione [Category] del suo file). Le tile si
; ridimensionano da sole per riempire lo schermo.
NX=4
NY=2
; Direzione di scorrimento: V (verticale, per righe) oppure H (orizzontale, per colonne)
ScrollDir=V
; Righe/colonne fatte scorrere per ogni scatto della rotellina
ScrollStep=1
; 1 = scroll infinito: dopo l'ultima riga ricomincia la prima (solo nelle
; categorie con piu' tile di quante ne stanno sullo schermo); 0 = si ferma
InfiniteScroll=1

; --- Spaziature (pixel) --------------------------------------------------------
Gap=18
; Margini esterni: PadX ospita la scrollbar verticale, PadY quella orizzontale.
PadX=40
PadY=24
; Lato del riquadro del logo nelle tile (per categoria: IconSize= in [Category])
IconSize=96
LabelPad=14
ScrollBarSize=4

; --- Menu categorie --------------------------------------------------------------
; MenuMode: IconText (icona + testo), Icon (solo icona), Text (solo testo).
; Una categoria senza icona mostra comunque il testo.
MenuMode=IconText
MenuH=44
MenuIconSize=24
; Spazio tra icona e testo di una voce
MenuIconGap=8
; Margine interno della "pillola" di ogni voce e spazio tra le voci
MenuItemPad=16
MenuGap=6
MenuRadius=22
; Trasparenza delle icone delle categorie non attive (0-255)
MenuIconDimAlpha=150

; --- Apertura e chiusura -------------------------------------------------------
; Il launcher si carica una volta (all'avvio di Rainmeter) e poi viene solo
; mostrato e nascosto. Per aprirlo/chiuderlo da una scorciatoia:
;   Rainmeter.exe !CommandMeasure MeasureScript "Toggle()" "Raintile"
; Combinazione di tasti che apre e chiude il launcher (plugin HotKey): tasti
; separati da spazio, es. CTRL ALT G, WIN SPACE, CTRL SHIFT F1
OpenHotKey=CTRL ALT G
; Azione della X in alto a destra (default: nasconde il launcher).
; Con [!DeactivateConfig] invece lo scarica dalla memoria.
CloseAction=[!CommandMeasure MeasureScript "Hide()"]
CloseSize=14
; Tasto che chiude il launcher (plugin HotKey), registrato solo mentre il
; launcher e' visibile. Vuoto = nessun tasto.
CloseHotKey=ESCAPE
; Navigazione da tastiera, attiva solo a launcher visibile (plugin HotKey):
; 1 = attiva, 0 = disattiva. Ogni azione ha due tasti (nomi del plugin HotKey:
; lettere, UP DOWN LEFT RIGHT, SPACE, ENTER, TAB, ...)
KeyboardNav=1
NavUp=W
NavUp2=UP
NavDown=S
NavDown2=DOWN
NavLeft=A
NavLeft2=LEFT
NavRight=D
NavRight2=RIGHT
; Avvia la tile evidenziata
NavConfirm=SPACE
NavConfirm2=ENTER
; Categoria precedente / successiva
NavPrevCategory=Q
NavNextCategory=E
; Apre la ricerca
NavSearch=F
; 1 = nasconde il launcher dopo aver avviato una tile, 0 = resta aperto
CloseOnLaunch=1
; 1 = si nasconde quando perde il focus: clic fuori dalla sua finestra (es.
; sul secondo schermo) o un altro programma in primo piano
AutoHide=1
; 1 = all'avvio di Rainmeter il launcher resta nascosto fino alla scorciatoia
StartHidden=0
; Livello della finestra quando viene mostrato: 1 = sopra le altre finestre,
; -2 = sul desktop, vuoto = non cambiarlo
ShowZPos=1

; --- Avvio di una tile ----------------------------------------------------------
; 1 = al click la tile si espande a schermo intero, resta visibile per
; LaunchHold ms e poi il launcher si chiude (se CloseOnLaunch=1); 0 = subito
LaunchAnimation=1
; Passi dell'espansione, 16 ms l'uno (15 = circa 250 ms)
LaunchAnimFrames=15
LaunchHold=1500
; Lato del riquadro del logo a fine espansione
LaunchLogoSize=(Floor(#ScreenH#/3))
; Testo al centro per le tile senza logo
LaunchFontSize=48

; --- Animazioni ------------------------------------------------------------------
; Ognuna si disattiva con 0. Girano solo mentre qualcosa si muove.
; Apertura: le tile compaiono una dopo l'altra
AnimOpen=1
; Cambio categoria: le tile ricompaiono e la pillola del menu scivola
AnimCategory=1
; Hover: il riquadro scivola da una tile all'altra, con dissolvenza
AnimHover=1
; Scorrimento fluido con la rotellina
AnimScroll=1
; Hover: il logo della tile sotto il mouse si ingrandisce di HoverLogoScale
AnimLogoZoom=1
HoverLogoScale=1.25
; Loghi in bianco e nero, che si colorano con il mouse sopra
LogoGreyscale=1
; Comparsa di ogni tile in passi da 16 ms, ritardo tra una tile e la
; successiva (passi) e salita in pixel
AnimAppearFrames=12
AnimStagger=2
AnimSlide=30
; Morbidezza delle animazioni: 0.05 = molto morbida e lenta, 1 = istantanea.
; AnimSmooth e' il valore di base, usato da quelle lasciate vuote.
AnimSmooth=0.3
; Scorrimento con la rotellina
AnimScrollSmooth=0.15
; Riquadro di evidenziazione che scivola tra le tile
AnimHoverSmooth=0.3
; Pillola del menu al cambio categoria
AnimPillSmooth=0.25
; Zoom e colore del logo con il mouse sopra (anche lo Zoom dello sfondo)
AnimLogoSmooth=0.2
; Le altre animazioni hanno una durata fissa in passi da 16 ms:
; AnimAppearFrames (comparsa delle tile), BgPanFrames (Pan dello sfondo),
; LaunchAnimFrames (espansione all'avvio)

; --- Sfondi delle tile ------------------------------------------------------------
; BgStyle: Crop     = ritaglio fisso al centro dell'immagine
;          Pan      = con il mouse sopra la tile scivola lentamente sull'immagine
;          Parallax = scorrendo la griglia l'immagine si muove piu' lenta della tile
;          Zoom     = con il mouse sopra lo sfondo si ingrandisce leggermente
BgStyle=Pan
; Quanto l'immagine e' piu' grande della tile (margine per scivolare)
BgOverscan=1.15
; Pan: durata della corsa in passi da 16 ms (180 = circa 3 secondi)
BgPanFrames=180
; Zoom: ingrandimento dello sfondo con il mouse sopra
BgHoverZoom=1.08

; --- Prestazioni ----------------------------------------------------------------
; 1 = usa miniature di sfondi e loghi alla misura esatta delle tile (create in
; background in Generated\Thumbs\ la prima volta), 0 = immagini originali
Thumbnails=1
; 1 = evidenzia la tile sotto il mouse (un ridisegno a ogni cambio di tile)
TileHover=1
; Durata in ms della dissolvenza all'apertura/chiusura (0 = istantanea).
; Viene copiata in Rainmeter.ini e vale dal caricamento successivo.
FadeDuration=0

; --- Gamepad (XInput: controller Xbox e compatibili) -----------------------------
; Croce/levetta sinistra = sposta, A = avvia, B = indietro/chiudi,
; LB/RB = categoria precedente/successiva, GamepadToggle = apri/chiudi.
; 1 = attivo (programma di supporto in background), 0 = disattivato
Gamepad=1
; Pulsanti da tenere premuti insieme per aprire/chiudere il launcher
; (A B X Y LB RB BACK START LS RS UP DOWN LEFT RIGHT)
GamepadToggle=BACK START
; Zona morta della levetta (0-32767) e ripetizione tenendo premuta una
; direzione: primo ritardo e intervallo, in ms
GamepadDeadZone=12000
GamepadRepeatDelay=350
GamepadRepeatRate=110

; --- Ricerca ----------------------------------------------------------------------
; Barra in alto a sinistra (o tasto NavSearch): Invio cerca in tutte le
; categorie, Esc o un clic su una categoria tornano indietro
SearchW=320
SearchPlaceholder=Cerca

; --- Import dagli store -------------------------------------------------------------
; Tasto destro sulla skin > "Importa giochi dagli store". I giochi installati
; vengono scritti in fondo al file della categoria ImportCategory, in un blocco
; che viene riscritto a ogni import; le tile scritte a mano non vengono toccate.
ImportCategory=Games
; Store da leggere, separati da |
ImportStores=Steam|Epic|GOG|Ubisoft
; 1 = importa anche in automatico, in background, a ogni caricamento della skin
ImportOnStart=0
; Chiave API gratuita di SteamGridDB (steamgriddb.com > Preferenze > API):
; scarica sfondo e logo dei giochi senza immagini locali (Epic, GOG, Ubisoft)
SteamGridDBKey=

; --- Diagnostica -----------------------------------------------------------------
; 1 = scrive nel log di Rainmeter (Gestisci > Log) cosa succede alla conferma,
; all'avvio di una tile e a mostra/nascondi, e i tasti visti dal plugin HotKey
DebugLog=0

; --- Aspetto -------------------------------------------------------------------
; 1 = mostra l'etichetta della tile (Label= nel file di categoria), 0 = nascondi
ShowLabels=1
FontFace=Segoe UI
MenuFontSize=12
LabelFontSize=14
BgColor=8,8,12,200
TileColor=36,36,44,255
HoverColor=255,255,255,25
AccentColor=0,210,180,255
ActiveCategoryColor=0,210,180,70
HoverCategoryColor=255,255,255,20
TextColor=240,240,245,255
TextDimColor=150,150,160,255
ScrollTrackColor=255,255,255,25
ScrollThumbColor=0,210,180,200

; --- Calcolati (non modificare) ------------------------------------------------
TileW=(Floor((#ScreenW#-2*#PadX#-(#NX#-1)*#Gap#)/#NX#))
TileH=(Floor((#ScreenH#-2*#PadY#-#MenuH#-#Gap#-(#NY#-1)*#Gap#)/#NY#))
