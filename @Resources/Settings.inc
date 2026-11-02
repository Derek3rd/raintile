[Variables]
; --- Screen ---------------------------------------------------------------------
; The launcher covers the whole screen. To keep the taskbar free use WORKAREA
; instead of SCREENAREA; for another monitor add @N (e.g. #SCREENAREAWIDTH@2#).
ScreenX=#SCREENAREAX#
ScreenY=#SCREENAREAY#
ScreenW=#SCREENAREAWIDTH#
ScreenH=#SCREENAREAHEIGHT#

; --- Grid -----------------------------------------------------------------------
; Default visible tiles: NX columns x NY rows. Each category can have its own
; grid (NX=, NY= in the [Category] section of its file). Tiles resize
; themselves to fill the screen.
NX=4
NY=2
; Scroll direction: V (vertical, by rows) or H (horizontal, by columns)
ScrollDir=V
; Rows/columns scrolled per mouse wheel notch
ScrollStep=1
; 1 = infinite scroll: after the last row the first comes back (only in
; categories with more tiles than fit on screen); 0 = stop at the end
InfiniteScroll=1

; --- Spacing --------------------------------------------------------------------
; Sizes are written in pixels (e.g. 40) or as a percentage of the screen
; (e.g. 2%): of the width for PadX, SearchW, MenuItemPad, MenuGap and
; MenuIconGap, of the height for all the others.
Gap=18
; Outer margins: PadX holds the vertical scrollbar, PadY the horizontal one.
PadX=40
PadY=24
; Side of the logo box in the tiles (per category: IconSize= in [Category])
IconSize=96
LabelPad=14
ScrollBarSize=4

; --- Category menu --------------------------------------------------------------
; MenuMode: IconText (icon + text), Icon (icon only), Text (text only).
; A category without an icon always shows its text.
MenuMode=IconText
MenuH=44
MenuIconSize=24
; Space between the icon and the text of an entry
MenuIconGap=8
; Inner padding of each entry's "pill" and space between entries
MenuItemPad=16
MenuGap=6
MenuRadius=22
; Opacity of the icons of inactive categories (0-255)
MenuIconDimAlpha=150
; Favorites and Recent: categories made of the tiles of the others, opened
; with the two icon buttons right of the search bar (the label shows on
; hover). Favorites: right click a tile > Add to Favorites. Recent: the
; tiles launched lately (RecentOrder=Recent) or most often (MostUsed).
ShowFavorites=1
ShowRecent=1
RecentOrder=Recent
RecentCount=12
; Filter bar above the search results: one chip per tag of the tiles (Tags=
; in the category files) and, with FilterStores=1, per store when the tiles
; come from at least two (Steam, Epic Games, GOG, ...). A click on a chip
; shows only the results that have it: of one of the selected stores, with
; all the selected tags; All shows them all again. Search finds tags too.
FilterBar=1
FilterStores=1
; Height of the chips, space between them and their inner padding
FilterH=30
FilterGap=6
FilterPad=12
FilterFontSize=10

; --- Open and close -------------------------------------------------------------
; The launcher loads once (when Rainmeter starts) and is then only shown and
; hidden. To open/close it from a shortcut:
;   Rainmeter.exe !CommandMeasure MeasureScript "Toggle()" "Raintile"
; Key combination that opens and closes the launcher (HotKey plugin): keys
; separated by spaces, e.g. CTRL ALT G, LWIN SPACE, CTRL SHIFT F1
OpenHotKey=CTRL ALT G
; Action of the X at the top right (default: hide the launcher).
; With [!DeactivateConfig] it unloads it from memory instead.
CloseAction=[!CommandMeasure MeasureScript "Hide()"]
CloseSize=14
; Key that closes the launcher (HotKey plugin), registered only while the
; launcher is visible. Empty = no key.
CloseHotKey=ESCAPE
; Keyboard navigation, only active while the launcher is visible (HotKey
; plugin): 1 = on, 0 = off. Each action has two keys (HotKey plugin names:
; letters, UP DOWN LEFT RIGHT, SPACE, ENTER, TAB, ...)
KeyboardNav=1
NavUp=W
NavUp2=UP
NavDown=S
NavDown2=DOWN
NavLeft=A
NavLeft2=LEFT
NavRight=D
NavRight2=RIGHT
; Launch the highlighted tile
NavConfirm=SPACE
NavConfirm2=ENTER
; Previous / next category
NavPrevCategory=Q
NavNextCategory=E
; Open the search
NavSearch=F
; 1 = hide the launcher after launching a tile, 0 = keep it open
CloseOnLaunch=1
; 1 = hide when it loses focus: a click outside its window (e.g. on the second
; monitor) or another program coming to the foreground
AutoHide=1
; 1 = when Rainmeter starts the launcher stays hidden until the shortcut
StartHidden=0
; Window level when it is shown: 1 = above other windows, -2 = on the
; desktop, empty = leave it as is
ShowZPos=1

; --- Tile launch ----------------------------------------------------------------
; 1 = on click the tile expands to full screen, stays visible for LaunchHold ms
; and then the launcher closes (if CloseOnLaunch=1); 0 = immediately
LaunchAnimation=1
; Expansion steps, 16 ms each (15 = about 250 ms)
LaunchAnimFrames=15
LaunchHold=1500
; Side of the logo box at the end of the expansion
LaunchLogoSize=33%
; Centre text for tiles without a logo
LaunchFontSize=48

; --- Animations -----------------------------------------------------------------
; Each one is turned off with 0. They only run while something moves.
; Open: the tiles appear one after another
AnimOpen=1
; Category change: the tiles appear again and the menu pill slides
AnimCategory=1
; Hover: the highlight box slides from tile to tile, with a fade
AnimHover=1
; Smooth mouse wheel scrolling
AnimScroll=1
; Hover: the logo of the tile under the mouse grows by HoverLogoScale
AnimLogoZoom=1
HoverLogoScale=1.25
; Greyscale logos that turn to colour under the mouse
LogoGreyscale=1
; Appearance of each tile in 16 ms steps, delay between one tile and the next
; (steps) and upward slide in pixels
AnimAppearFrames=12
AnimStagger=2
AnimSlide=30
; Animation smoothing: 0.05 = very smooth and slow, 1 = instant.
; AnimSmooth is the base value, used by those left empty.
AnimSmooth=0.3
; Mouse wheel scrolling
AnimScrollSmooth=0.15
; Highlight box sliding between tiles
AnimHoverSmooth=0.3
; Menu pill on category change
AnimPillSmooth=0.25
; Logo zoom and colour under the mouse (and the background Zoom)
AnimLogoSmooth=0.2
; The other animations have a fixed length in 16 ms steps:
; AnimAppearFrames (tiles appearing), BgPanFrames (background Pan),
; LaunchAnimFrames (launch expansion)

; --- Tile backgrounds -----------------------------------------------------------
; BgStyle: Crop     = fixed crop at the centre of the image
;          Pan      = under the mouse the tile slowly slides over the image
;          Parallax = while scrolling the image moves slower than the tile
;          Zoom     = under the mouse the background slightly grows
BgStyle=Parallax
; How much larger the image is than the tile (room to slide)
BgOverscan=1.15
; Pan: length of the slide in 16 ms steps (180 = about 3 seconds)
BgPanFrames=180
; Zoom: background zoom under the mouse
BgHoverZoom=1.08

; --- Performance ----------------------------------------------------------------
; 1 = use background and logo thumbnails at the exact tile size (created in
; the background in Generated\Thumbs\ the first time), 0 = original images
Thumbnails=1
; 1 = highlight the tile under the mouse (one redraw per tile change)
TileHover=1
; Open/close fade duration in ms (0 = instant).
; It is copied to Rainmeter.ini and applies from the next load.
FadeDuration=0

; --- Gamepad (XInput: Xbox and compatible controllers) --------------------------
; D-pad/left stick = move, A = launch, B = back/close,
; LB/RB = previous/next category, GamepadToggle = open/close.
; 1 = on (background helper), 0 = off
Gamepad=1
; Buttons to hold together to open/close the launcher
; (A B X Y LB RB BACK START LS RS UP DOWN LEFT RIGHT)
GamepadToggle=BACK START
; Stick dead zone (0-32767) and repeat while holding a direction: first delay
; and interval, in ms
GamepadDeadZone=12000
GamepadRepeatDelay=350
GamepadRepeatRate=110

; --- Search ---------------------------------------------------------------------
; Bar at the top left (or the NavSearch key): Enter searches every category,
; Esc or a click on a category goes back
SearchW=320
SearchPlaceholder=Search

; --- Games and apps ---------------------------------------------------------------
; Right click on the skin > "Add games and apps..." (or Options > Import):
; the games and apps installed on this PC are listed, and the ones you pick
; become normal tiles. Nothing is added by itself.
; Where to look, separated by |: Steam Epic GOG Ubisoft Battlenet EA Xbox
; (games) and Apps (the Start menu)
ImportStores=Steam|Epic|GOG|Ubisoft|Battlenet|EA|Xbox|Apps
; 1 = look for new games and apps in the background on every skin load: new
; ones light a dot on the gear (nothing is added). The same search finds the
; tiles of games no longer installed: they are greyed out, light the dot and
; can be removed or kept in Options > Import.
ScanOnStart=1
; Categories where games and apps go when added
ImportCategory=Games
AppsCategory=Apps
; Free SteamGridDB API key (steamgriddb.com > Preferences > API): when adding a
; game without local images, its background and logo are downloaded. Set it in
; the Options window: it is saved encrypted (dpapi:...), readable only by your
; Windows user on this PC. Written here by hand it stays in clear until the
; Options window saves.
SteamGridDBKey=

; --- Updates --------------------------------------------------------------------
; 1 = check GitHub for a new version (at most once a day): a dot on the gear
; and Options > Info show it, and install it with one click
CheckUpdates=1

; --- Diagnostics ----------------------------------------------------------------
; 1 = write to the Rainmeter log (Manage > Log) what happens on confirm, on
; tile launch and on show/hide, and the keys seen by the HotKey plugin
DebugLog=0

; --- Appearance -----------------------------------------------------------------
; 1 = show the tile label (Label= in the category file), 0 = hide it
ShowLabels=1
; Line at the top left of the tiles with the play time (Steam games) and the
; last launch: Hover (only on the highlighted tile), Always or Never. Tiles
; of games no longer installed always say so.
TileInfo=Hover
InfoFontSize=10
FontFace=Segoe UI
MenuFontSize=12
LabelFontSize=14
; Colours: R,G,B,A (alpha optional) or hex #RRGGBBAA / #RRGGBB (the # is
; optional). The same formats work for Color= in the category files.
BgColor=8,8,12,200
TileColor=36,36,44,255
; 1 = tiles with a logo but no background image (and no Color= in their
; category file) get a dark colour taken from the logo, computed once in the
; background; 0 = they use TileColor
AutoTileColor=1
HoverColor=255,255,255,25
AccentColor=0,210,180,255
ActiveCategoryColor=0,210,180,70
HoverCategoryColor=255,255,255,20
TextColor=240,240,245,255
TextDimColor=150,150,160,255
ScrollTrackColor=255,255,255,25
ScrollThumbColor=0,210,180,200
