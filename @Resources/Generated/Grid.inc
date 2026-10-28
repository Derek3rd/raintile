; GENERATO AUTOMATICAMENTE da Raintile.lua: non modificare a mano.
[Variables]
GridSignature=4x2|icontext|Games:Giochi:|Apps:App:|Links:Link:|System:Sistema:
CategoryFiles=Apps.ini|Games.ini|Links.ini|System.ini

[CatText1]
Meter=String
MeterStyle=StyleCategory
X=#PadX#
Y=(#PadY#+#MenuH#/2)
Text=Giochi

[CatText2]
Meter=String
MeterStyle=StyleCategory
X=(#MenuGap#+2*#MenuItemPad#)R
Y=(#PadY#+#MenuH#/2)
Text=App

[CatText3]
Meter=String
MeterStyle=StyleCategory
X=(#MenuGap#+2*#MenuItemPad#)R
Y=(#PadY#+#MenuH#/2)
Text=Link

[CatText4]
Meter=String
MeterStyle=StyleCategory
X=(#MenuGap#+2*#MenuItemPad#)R
Y=(#PadY#+#MenuH#/2)
Text=Sistema

[CatHit1]
Meter=Shape
MeterStyle=StyleCategoryHit
LeftMouseUpAction=[!CommandMeasure MeasureScript "SetCategory(1)"]
MouseOverAction=[!CommandMeasure MeasureScript "HoverCategory(1)"]
MouseLeaveAction=[!CommandMeasure MeasureScript "HoverCategory(0)"]

[CatHit2]
Meter=Shape
MeterStyle=StyleCategoryHit
LeftMouseUpAction=[!CommandMeasure MeasureScript "SetCategory(2)"]
MouseOverAction=[!CommandMeasure MeasureScript "HoverCategory(2)"]
MouseLeaveAction=[!CommandMeasure MeasureScript "HoverCategory(0)"]

[CatHit3]
Meter=Shape
MeterStyle=StyleCategoryHit
LeftMouseUpAction=[!CommandMeasure MeasureScript "SetCategory(3)"]
MouseOverAction=[!CommandMeasure MeasureScript "HoverCategory(3)"]
MouseLeaveAction=[!CommandMeasure MeasureScript "HoverCategory(0)"]

[CatHit4]
Meter=Shape
MeterStyle=StyleCategoryHit
LeftMouseUpAction=[!CommandMeasure MeasureScript "SetCategory(4)"]
MouseOverAction=[!CommandMeasure MeasureScript "HoverCategory(4)"]
MouseLeaveAction=[!CommandMeasure MeasureScript "HoverCategory(0)"]

[Tile1]
Meter=Image
MeterStyle=StyleTile
X=(#PadX#+0*(#TileW#+#Gap#))
Y=(#PadY#+#MenuH#+#Gap#+0*(#TileH#+#Gap#))
LeftMouseUpAction=[!CommandMeasure MeasureScript "Launch(1)"]
MouseOverAction=[!ShowMeter TileHover1][!Redraw]
MouseLeaveAction=[!HideMeter TileHover1][!Redraw]

[TileIcon1]
Meter=Image
MeterStyle=StyleTileIcon
X=(#PadX#+0*(#TileW#+#Gap#)+(#TileW#-#IconSize#)/2)
Y=(#PadY#+#MenuH#+#Gap#+0*(#TileH#+#Gap#)+(#TileH#-#IconSize#)/2)

[TileLabel1]
Meter=String
MeterStyle=StyleTileLabel
X=(#PadX#+0*(#TileW#+#Gap#)+#LabelPad#)
Y=(#PadY#+#MenuH#+#Gap#+0*(#TileH#+#Gap#)+#TileH#-#LabelPad#)

[TileHover1]
Meter=Shape
MeterStyle=StyleTileHover
X=(#PadX#+0*(#TileW#+#Gap#))
Y=(#PadY#+#MenuH#+#Gap#+0*(#TileH#+#Gap#))

[Tile2]
Meter=Image
MeterStyle=StyleTile
X=(#PadX#+1*(#TileW#+#Gap#))
Y=(#PadY#+#MenuH#+#Gap#+0*(#TileH#+#Gap#))
LeftMouseUpAction=[!CommandMeasure MeasureScript "Launch(2)"]
MouseOverAction=[!ShowMeter TileHover2][!Redraw]
MouseLeaveAction=[!HideMeter TileHover2][!Redraw]

[TileIcon2]
Meter=Image
MeterStyle=StyleTileIcon
X=(#PadX#+1*(#TileW#+#Gap#)+(#TileW#-#IconSize#)/2)
Y=(#PadY#+#MenuH#+#Gap#+0*(#TileH#+#Gap#)+(#TileH#-#IconSize#)/2)

[TileLabel2]
Meter=String
MeterStyle=StyleTileLabel
X=(#PadX#+1*(#TileW#+#Gap#)+#LabelPad#)
Y=(#PadY#+#MenuH#+#Gap#+0*(#TileH#+#Gap#)+#TileH#-#LabelPad#)

[TileHover2]
Meter=Shape
MeterStyle=StyleTileHover
X=(#PadX#+1*(#TileW#+#Gap#))
Y=(#PadY#+#MenuH#+#Gap#+0*(#TileH#+#Gap#))

[Tile3]
Meter=Image
MeterStyle=StyleTile
X=(#PadX#+2*(#TileW#+#Gap#))
Y=(#PadY#+#MenuH#+#Gap#+0*(#TileH#+#Gap#))
LeftMouseUpAction=[!CommandMeasure MeasureScript "Launch(3)"]
MouseOverAction=[!ShowMeter TileHover3][!Redraw]
MouseLeaveAction=[!HideMeter TileHover3][!Redraw]

[TileIcon3]
Meter=Image
MeterStyle=StyleTileIcon
X=(#PadX#+2*(#TileW#+#Gap#)+(#TileW#-#IconSize#)/2)
Y=(#PadY#+#MenuH#+#Gap#+0*(#TileH#+#Gap#)+(#TileH#-#IconSize#)/2)

[TileLabel3]
Meter=String
MeterStyle=StyleTileLabel
X=(#PadX#+2*(#TileW#+#Gap#)+#LabelPad#)
Y=(#PadY#+#MenuH#+#Gap#+0*(#TileH#+#Gap#)+#TileH#-#LabelPad#)

[TileHover3]
Meter=Shape
MeterStyle=StyleTileHover
X=(#PadX#+2*(#TileW#+#Gap#))
Y=(#PadY#+#MenuH#+#Gap#+0*(#TileH#+#Gap#))

[Tile4]
Meter=Image
MeterStyle=StyleTile
X=(#PadX#+3*(#TileW#+#Gap#))
Y=(#PadY#+#MenuH#+#Gap#+0*(#TileH#+#Gap#))
LeftMouseUpAction=[!CommandMeasure MeasureScript "Launch(4)"]
MouseOverAction=[!ShowMeter TileHover4][!Redraw]
MouseLeaveAction=[!HideMeter TileHover4][!Redraw]

[TileIcon4]
Meter=Image
MeterStyle=StyleTileIcon
X=(#PadX#+3*(#TileW#+#Gap#)+(#TileW#-#IconSize#)/2)
Y=(#PadY#+#MenuH#+#Gap#+0*(#TileH#+#Gap#)+(#TileH#-#IconSize#)/2)

[TileLabel4]
Meter=String
MeterStyle=StyleTileLabel
X=(#PadX#+3*(#TileW#+#Gap#)+#LabelPad#)
Y=(#PadY#+#MenuH#+#Gap#+0*(#TileH#+#Gap#)+#TileH#-#LabelPad#)

[TileHover4]
Meter=Shape
MeterStyle=StyleTileHover
X=(#PadX#+3*(#TileW#+#Gap#))
Y=(#PadY#+#MenuH#+#Gap#+0*(#TileH#+#Gap#))

[Tile5]
Meter=Image
MeterStyle=StyleTile
X=(#PadX#+0*(#TileW#+#Gap#))
Y=(#PadY#+#MenuH#+#Gap#+1*(#TileH#+#Gap#))
LeftMouseUpAction=[!CommandMeasure MeasureScript "Launch(5)"]
MouseOverAction=[!ShowMeter TileHover5][!Redraw]
MouseLeaveAction=[!HideMeter TileHover5][!Redraw]

[TileIcon5]
Meter=Image
MeterStyle=StyleTileIcon
X=(#PadX#+0*(#TileW#+#Gap#)+(#TileW#-#IconSize#)/2)
Y=(#PadY#+#MenuH#+#Gap#+1*(#TileH#+#Gap#)+(#TileH#-#IconSize#)/2)

[TileLabel5]
Meter=String
MeterStyle=StyleTileLabel
X=(#PadX#+0*(#TileW#+#Gap#)+#LabelPad#)
Y=(#PadY#+#MenuH#+#Gap#+1*(#TileH#+#Gap#)+#TileH#-#LabelPad#)

[TileHover5]
Meter=Shape
MeterStyle=StyleTileHover
X=(#PadX#+0*(#TileW#+#Gap#))
Y=(#PadY#+#MenuH#+#Gap#+1*(#TileH#+#Gap#))

[Tile6]
Meter=Image
MeterStyle=StyleTile
X=(#PadX#+1*(#TileW#+#Gap#))
Y=(#PadY#+#MenuH#+#Gap#+1*(#TileH#+#Gap#))
LeftMouseUpAction=[!CommandMeasure MeasureScript "Launch(6)"]
MouseOverAction=[!ShowMeter TileHover6][!Redraw]
MouseLeaveAction=[!HideMeter TileHover6][!Redraw]

[TileIcon6]
Meter=Image
MeterStyle=StyleTileIcon
X=(#PadX#+1*(#TileW#+#Gap#)+(#TileW#-#IconSize#)/2)
Y=(#PadY#+#MenuH#+#Gap#+1*(#TileH#+#Gap#)+(#TileH#-#IconSize#)/2)

[TileLabel6]
Meter=String
MeterStyle=StyleTileLabel
X=(#PadX#+1*(#TileW#+#Gap#)+#LabelPad#)
Y=(#PadY#+#MenuH#+#Gap#+1*(#TileH#+#Gap#)+#TileH#-#LabelPad#)

[TileHover6]
Meter=Shape
MeterStyle=StyleTileHover
X=(#PadX#+1*(#TileW#+#Gap#))
Y=(#PadY#+#MenuH#+#Gap#+1*(#TileH#+#Gap#))

[Tile7]
Meter=Image
MeterStyle=StyleTile
X=(#PadX#+2*(#TileW#+#Gap#))
Y=(#PadY#+#MenuH#+#Gap#+1*(#TileH#+#Gap#))
LeftMouseUpAction=[!CommandMeasure MeasureScript "Launch(7)"]
MouseOverAction=[!ShowMeter TileHover7][!Redraw]
MouseLeaveAction=[!HideMeter TileHover7][!Redraw]

[TileIcon7]
Meter=Image
MeterStyle=StyleTileIcon
X=(#PadX#+2*(#TileW#+#Gap#)+(#TileW#-#IconSize#)/2)
Y=(#PadY#+#MenuH#+#Gap#+1*(#TileH#+#Gap#)+(#TileH#-#IconSize#)/2)

[TileLabel7]
Meter=String
MeterStyle=StyleTileLabel
X=(#PadX#+2*(#TileW#+#Gap#)+#LabelPad#)
Y=(#PadY#+#MenuH#+#Gap#+1*(#TileH#+#Gap#)+#TileH#-#LabelPad#)

[TileHover7]
Meter=Shape
MeterStyle=StyleTileHover
X=(#PadX#+2*(#TileW#+#Gap#))
Y=(#PadY#+#MenuH#+#Gap#+1*(#TileH#+#Gap#))

[Tile8]
Meter=Image
MeterStyle=StyleTile
X=(#PadX#+3*(#TileW#+#Gap#))
Y=(#PadY#+#MenuH#+#Gap#+1*(#TileH#+#Gap#))
LeftMouseUpAction=[!CommandMeasure MeasureScript "Launch(8)"]
MouseOverAction=[!ShowMeter TileHover8][!Redraw]
MouseLeaveAction=[!HideMeter TileHover8][!Redraw]

[TileIcon8]
Meter=Image
MeterStyle=StyleTileIcon
X=(#PadX#+3*(#TileW#+#Gap#)+(#TileW#-#IconSize#)/2)
Y=(#PadY#+#MenuH#+#Gap#+1*(#TileH#+#Gap#)+(#TileH#-#IconSize#)/2)

[TileLabel8]
Meter=String
MeterStyle=StyleTileLabel
X=(#PadX#+3*(#TileW#+#Gap#)+#LabelPad#)
Y=(#PadY#+#MenuH#+#Gap#+1*(#TileH#+#Gap#)+#TileH#-#LabelPad#)

[TileHover8]
Meter=Shape
MeterStyle=StyleTileHover
X=(#PadX#+3*(#TileW#+#Gap#))
Y=(#PadY#+#MenuH#+#Gap#+1*(#TileH#+#Gap#))
