[Variables]
; --- Griglia -----------------------------------------------------------------
; Tile visibili: NX colonne x NY righe.
; Cambiando NX o NY la griglia viene rigenerata e la skin ricaricata da sola.
NX=4
NY=2
; Direzione di scorrimento: V (verticale, per righe) oppure H (orizzontale, per colonne)
ScrollDir=V
; Righe/colonne fatte scorrere per ogni scatto della rotellina
ScrollStep=1

; --- Dimensioni (pixel) --------------------------------------------------------
TileW=320
TileH=250
Gap=16
; Margini esterni: PadX deve lasciare spazio alla scrollbar verticale,
; PadY a quella orizzontale.
PadX=20
PadY=14
; Altezza della barra delle categorie
MenuH=40
; Spazio tra i pulsanti delle categorie
MenuGap=4
IconSize=72
LabelPad=12
ScrollBarSize=4
Radius=10

; --- Aspetto -------------------------------------------------------------------
; 1 = mostra l'etichetta della tile (se definita in Tiles.ini), 0 = nascondi
ShowLabels=1
FontFace=Segoe UI
MenuFontSize=12
LabelFontSize=13
BgColor=8,8,12,170
TileColor=36,36,44,255
HoverColor=255,255,255,25
AccentColor=0,210,180,255
ActiveCategoryColor=0,210,180,60
TextColor=240,240,245,255
TextDimColor=150,150,160,255
ScrollTrackColor=255,255,255,25
ScrollThumbColor=0,210,180,200
