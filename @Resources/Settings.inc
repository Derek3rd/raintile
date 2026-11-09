[Variables]
; --- Screen ---------------------------------------------------------------------
; The area of the launcher: the whole screen. To keep the taskbar free use
; WORKAREA instead of SCREENAREA; for another monitor add @N (e.g.
; #SCREENAREAWIDTH@2#).
ScreenX=#SCREENAREAX#
ScreenY=#SCREENAREAY#
ScreenW=#SCREENAREAWIDTH#
ScreenH=#SCREENAREAHEIGHT#
; How the launcher shows on that area:
;   Fullscreen  all of it
;   Window      a window of WindowW x WindowH: drag an empty part of it to
;               move it; it stays open when you click elsewhere
;   Dock        on a side of the screen (DockSide: Left, Right, Top, Bottom),
;               DockSize wide (or tall): it comes in from that side
; Sizes in pixels or % of the area. A window never covers the taskbar: on
; the whole screen its area is the work area, so 100% leaves the taskbar free.
LauncherMode=Fullscreen
WindowW=60%
WindowH=70%
DockSide=Left
DockSize=30%
; Docked: 1 = it also opens when the mouse rests on that edge of the screen
; for DockEdgeDelay ms (not while a full-screen program, e.g. a game, is in
; front)
DockEdge=1
DockEdgeDelay=300

; --- Grid -----------------------------------------------------------------------
; Default visible tiles: NX columns x NY rows. Each category can have its own
; grid (NX=, NY= in the [Category] section of its file). Tiles resize
; themselves to fill the screen.
NX=4
NY=2
; Scroll direction: V (vertical, by rows) or H (horizontal, by columns)
ScrollDir=V
; Mouse wheel notch: rows/columns scrolled in the grid, tiles turned in the wheel
ScrollStep=1
; 1 = infinite scroll: after the last row the first comes back; with fewer
; tiles than fit on screen they repeat, so it still scrolls round; 0 = stop at
; the end
InfiniteScroll=1

; --- Wheel ----------------------------------------------------------------------
; Grid: the tiles in rows and columns (NX, NY, ScrollDir). Wheel: one line of
; square tiles on an arc (the thumbnails); the selected tile stays in the
; middle and the wheel turns, and it can be the launcher's backdrop
; (WheelBackdrop). Every thumbnail is one cell (Size=, NX, NY, IconSize and
; BgStyle are the grid's); best when docked.
ScrollMode=Grid
; Auto: along the docked side (vertical docked left or right, horizontal
; otherwise); Vertical or Horizontal
WheelAxis=Auto
; Out: the arc bulges towards the screen; In: hollow
WheelCurve=Out
; Radius of the arc, in percent of the launcher's length along the wheel
WheelRadius=70
; Space from one tile to the next, in percent of a tile (under 100 they overlap:
; the middle one is drawn on top)
WheelSpacing=50
; Place of the selected tile across the launcher, in percent from its docked side
WheelAnchor=69
; Size of the thumbnails, in percent of the smaller side of the screen; their
; logo is 70% of it (times LogoScale= of the tile)
WheelTileSize=25
; Tiles shown (odd): the selected one and as many on each side
WheelVisible=11
; How much the tiles fade towards the ends, in percent
WheelFade=65
; Names: Center (the selected tile only) or All
WheelLabels=Center
; Time to turn by one tile, in ms
WheelStepTime=350
; Mouse resting on a side tile: Turn (the wheel turns to it) or Highlight
WheelHover=Turn
; Click on a side tile: Launch (starts it) or Center (turns it to the middle)
WheelClick=Launch
; Categories: Ring (on an inner wheel; Q / E or LB / RB turn it) or Bar (the
; menu at the top)
WheelMenu=Ring
; Inner wheel: distance from the wheel of tiles and size of its entries, in
; percent of a tile
WheelMenuGap=50
WheelMenuSize=50
; 1 = the backdrop: the launcher's background takes the background image of
; the selected tile, filling it as a desktop wallpaper (cut from its centre,
; not framed; fading from one to the next), at WheelBackdropOpacity percent
; over BgColor
WheelBackdrop=1
WheelBackdropOpacity=40
; With WheelBackdrop=1, where the selected tile shows its logo and its lines
; (the update line and the play time): Tile (on its thumbnail) or Background
; (on the backdrop, under the top row, at their own place: BackLogoPos=,
; BackLogoScale=, BackInfoPos= of the tile or the category). The other
; thumbnails keep their logo (with WheelIconsOnly the selected one shows its
; background image instead); with the lines on the backdrop no thumbnail
; shows any.
WheelLogoOn=Tile
; Height of the logo on the backdrop, in percent of the area under the top
; row (times BackLogoScale= of the tile)
WheelBackdropLogoSize=30
WheelInfoOn=Tile
; 1 = the tiles of the wheel show only their logo, on a colour taken from it
; (as AutoTileColor; a Color= of the tile or the category still wins). Tiles
; without a logo keep their background.
WheelIconsOnly=0

; --- Spacing --------------------------------------------------------------------
; Sizes are written in pixels (e.g. 40) or as a percentage of the screen
; (e.g. 2%): of the width for PadX, SearchW, MenuItemPad, MenuGap and
; MenuIconGap, of the height for all the others.
; Gap: under the top row, and between the tiles of the grid
Gap=18
; Outer margins: PadX holds the vertical scrollbar, PadY the horizontal one.
PadX=40
PadY=24
; Side of the logo box in the tiles of the grid (per category: IconSize= in
; [Category]); the wheel's thumbnails have their own (WheelTileSize)
IconSize=96
; Inner margin of a tile: from its edge to the label and to the lines of the
; play time and updates
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
; Favorites, Recent and Not played yet: categories made of the tiles of the
; others, opened with the icon buttons right of the clock (the label shows on
; hover). Favorites: right click a tile > Add to Favorites. Recent: the
; tiles launched lately (RecentOrder=Recent) or most often (MostUsed). Not
; played yet: never launched, the ones added last first.
ShowFavorites=1
ShowRecent=1
RecentOrder=Recent
RecentCount=12
ShowUnplayed=1
UnplayedCount=24
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
; 1 = power button left of the gear: Lock, Sleep, Restart, Shut down (the
; last two want a second click)
ShowPower=1
; Key that closes the launcher (HotKey plugin), registered only while the
; launcher is visible and has the focus. Empty = no key.
CloseHotKey=ESCAPE
; Hot keys of the tiles (HotKey= in the category files): Always = they start
; their tile also while the launcher is closed; Open = only while it is open
; and has the focus (the keys stay free for other programs the rest of the
; time)
TileKeysWhen=Always
; Keyboard navigation, only active while the launcher is visible and has the
; focus (HotKey plugin): 1 = on, 0 = off. The launcher has the focus when it
; is opened or clicked, and loses it to a click on another program or another
; program in front; the shortcut gives it back. Each action has two keys
; (HotKey plugin names: letters, UP DOWN LEFT RIGHT, SPACE, ENTER, TAB, ...)
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
; monitor) or another program coming to the foreground. Not as a window. With
; 0 (or as a window) it stays open, without its keys and the gamepad.
AutoHide=1
; 1 = when Rainmeter starts the launcher stays hidden until the shortcut
StartHidden=0
; Window level when it is shown: 1 = above other windows, 0 = normal (above
; them while in use, behind them once the focus goes; the shortcut brings it
; back), -2 = on the desktop (focus loss is not seen there: it keeps its keys
; while visible), empty = leave it as is
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
; In the grid (the wheel's thumbnails are always cropped):
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
; Steps per second of the animations: Rainmeter draws the whole window on
; each one, so on very large screens fewer steps keep them smooth. Auto = 30
; from about 3 million pixels (e.g. 3440x1440, 2560x1440 is 3.7), 60 below;
; 60 or 30 to choose. Animations last the same either way.
FrameRate=Auto
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
; Button that opens the search with the on-screen keyboard: D-pad/stick move
; on it, A types, X deletes, Start keeps the results, B closes. LT/RT pick
; the filter chips of the results.
GamepadSearch=Y
; Button that opens the Options window, as the gear (RS = right stick click).
; It does nothing on a button of GamepadSearch or GamepadToggle; on X, LT or
; RT it takes their place. Empty = no button.
GamepadOptions=RS

; --- Search ---------------------------------------------------------------------
; Bar at the top left, after the clock and the Favorites / Recent buttons (or
; the NavSearch key): Enter searches every category, Esc or a click on a
; category goes back
SearchW=320
SearchPlaceholder=Search
; 1 = only the magnifier until the mouse is over it (it stays open while you
; type and while a search is shown), 0 = always open
SearchHover=1

; --- Widgets --------------------------------------------------------------------
; Any tile of any category can be a widget (Widget=: CPU, GPU, memory, disks,
; network, processes, system, temperatures, skins, custom ones): see
; Categories\Dashboard.ini, the example. They update every DashInterval ms,
; only while their category is on screen. Temperatures and fans:
; LibreHardwareMonitor's web server, or HWiNFO with "Shared Memory Support" on.
DashInterval=1000
; Port of LibreHardwareMonitor's web server (in it: Options > Remote Web
; Server > Run), for temperatures, fans and the other sensors
SensorPort=8085

; --- Clock ----------------------------------------------------------------------
; Time and date at the top left, updated every minute while the launcher is
; visible. Formats: %H:%M = 14:05, %#I:%M %p = 2:05 PM; %A %#d %B = Monday
; 2 November (in the language of Windows), %#d/%m/%Y = 2/11/2026
ShowClock=1
ShowDate=1
ClockFormat=%H:%M
DateFormat=%A %#d %B
ClockFontSize=18

; --- Games and apps ---------------------------------------------------------------
; Right click on the skin > "Add games and apps..." (or Options > Import):
; the games and apps installed on this PC are listed, and the ones you pick
; become normal tiles. Nothing is added by itself.
; Where to look, separated by |: Steam Epic GOG Ubisoft Battlenet EA Xbox
; GooglePlay (games), Folders (the programs in ImportFolders) and Apps (the
; Start menu)
ImportStores=Steam|Epic|GOG|Ubisoft|Battlenet|EA|Xbox|GooglePlay|Folders|Apps
; Folders of your own (portable games, emulators...), separated by |: every
; program (.exe) in them and in their subfolders is listed, named after its
; file (installers, uninstallers, redistributables and helpers left out).
; Each entry: Name=Folder>Kind>Category, all but the folder optional (e.g.
; Emulators=E:\Emu>App>Emulators): its name, shown in the list of found ones
; and offered by its filter (without one, the folder's name); Game or App
; (without one: Game); the category its programs go to (without one, the one
; of their kind: ImportCategory or AppsCategory)
ImportFolders=
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
; Release = only the releases; Nightly = also the build made on every change
; (pre-release "nightly", e.g. 1.2.1.5: the 5th after the release 1.2.1):
; newer, but not tested as much
UpdateChannel=Release

; --- Diagnostics ----------------------------------------------------------------
; 1 = write to the Rainmeter log (Manage > Log) what happens on confirm, on
; tile launch and on show/hide, and the keys seen by the HotKey plugin
DebugLog=0

; --- Appearance -----------------------------------------------------------------
; 1 = show the tile label (Label= in the category file), 0 = hide it
ShowLabels=1
; Line on the tiles with the play time (Steam games) and the last launch, at
; the top left unless moved (InfoPos= of the tile or the category): Hover
; (only on the highlighted tile), Always or Never. Tiles of games no longer
; installed always say so.
TileInfo=Hover
InfoFontSize=10
; 1 = measure the play time of the tiles that are not Steam games: the
; background helper looks for the game started by the tile and counts how
; long it runs (TimePlayed.txt in the data folder)
TrackPlaytime=1
; Steam games with an update waiting say so on a line above the play time:
; "Update 5.4 GB - Sat 06:27" (size and time Steam scheduled it),
; "Downloading 40% - 25.3 MB/s - 2:35 left" while it downloads (followed live
; while the launcher is open), and their tile gets a border in DownloadColor1
; and DownloadColor2. Hover (the line only on the highlighted tile; the
; border and the bar always), Always (the line on every such tile) or Never
; (none of it).
UpdateInfo=Hover
; What the update line says, in any order: percent, size (downloaded / total),
; speed, eta (time left), schedule (when Steam will download it)
DownloadInfo=percent speed eta size schedule
; How a download shows on its tile: Bar (a bar along the bottom), Greyscale
; (the background in greyscale, coloured again from the left as it goes) or
; Both
DownloadStyle=Bar
; Colours of the border of a tile with an update (a gradient from 1 to 2) and
; of the bar (1)
DownloadColor1=0,210,180,255
DownloadColor2=120,90,255,255
; Seconds the border turns when the launcher opens (0 = it stays still)
UpdateGlowTime=3
FontFace=Segoe UI
MenuFontSize=12
LabelFontSize=14
; Colours: R,G,B,A (alpha optional) or hex #RRGGBBAA / #RRGGBB (the # is
; optional). The same formats work for Color= in the category files.
BgColor=8,8,12,200
; Band behind the row at the top (clock, search, buttons, close) while the
; wheel shows the selected tile's background (WheelBackdrop): one rounded band
; from the search to the close button, so the row stays readable over the picture
TopBarColor=0,0,0,255
TileColor=36,36,44,255
; Rounded corners of the tiles, in pixels (0 = square)
TileRadius=0
; 1 = a fade over the tiles cut by the edge of the grid (they go on beyond it)
EdgeFade=1
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
