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

; --- Prestazioni ----------------------------------------------------------------
; 1 = usa miniature di sfondi e loghi alla misura esatta delle tile (create in
; background in Generated\Thumbs\ la prima volta), 0 = immagini originali
Thumbnails=1

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
