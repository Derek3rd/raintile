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
; Tile visibili: NX colonne x NY righe. Le tile si ridimensionano da sole per
; riempire lo schermo. Cambiando NX o NY la griglia viene rigenerata e la skin
; ricaricata in automatico.
NX=4
NY=2
; Direzione di scorrimento: V (verticale, per righe) oppure H (orizzontale, per colonne)
ScrollDir=V
; Righe/colonne fatte scorrere per ogni scatto della rotellina
ScrollStep=1

; --- Spaziature (pixel) --------------------------------------------------------
Gap=18
; Margini esterni: PadX ospita la scrollbar verticale, PadY quella orizzontale.
PadX=40
PadY=24
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

; --- Chiusura -----------------------------------------------------------------
; Azione della X in alto a destra. [!DeactivateConfig] scarica la skin
; (zero memoria finche' e' chiusa); [!Hide] la nasconde soltanto.
CloseAction=[!DeactivateConfig]
CloseSize=14
; Tasto che chiude il launcher (plugin HotKey). Finche' il launcher e' caricato
; il tasto viene intercettato in tutto il sistema.
CloseHotKey=ESCAPE
; 1 = chiude il launcher dopo aver avviato una tile (libera anche CloseHotKey
; per le altre applicazioni), 0 = resta aperto
CloseOnLaunch=1

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
; Comparsa di ogni tile in passi da 16 ms, ritardo tra una tile e la
; successiva (passi) e salita in pixel
AnimAppearFrames=12
AnimStagger=2
AnimSlide=30
; Morbidezza di hover, pillola e scorrimento: 0.1 = lento, 1 = istantaneo
AnimSmooth=0.3

; --- Prestazioni ----------------------------------------------------------------
; 1 = usa miniature di sfondi e loghi alla misura esatta delle tile (create in
; background in Generated\Thumbs\ la prima volta), 0 = immagini originali
Thumbnails=1
; 1 = evidenzia la tile sotto il mouse (un ridisegno a ogni cambio di tile)
TileHover=1
; Durata in ms della dissolvenza all'apertura/chiusura (0 = istantanea).
; Viene copiata in Rainmeter.ini e vale dal caricamento successivo.
FadeDuration=0

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
