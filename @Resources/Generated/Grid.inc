; GENERATO AUTOMATICAMENTE da Raintile.lua: non modificare a mano.
[Variables]
GridSignature=v2|4x2|icontext|Games:Giochi:|Apps:App:|Links:Link:|System:Sistema:
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
MouseOverAction=[!CommandMeasure MeasureScript "HoverTile(1)"]
MouseLeaveAction=[!CommandMeasure MeasureScript "LeaveTile(1)"]

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

[Tile2]
Meter=Image
MeterStyle=StyleTile
X=(#PadX#+1*(#TileW#+#Gap#))
Y=(#PadY#+#MenuH#+#Gap#+0*(#TileH#+#Gap#))
LeftMouseUpAction=[!CommandMeasure MeasureScript "Launch(2)"]
MouseOverAction=[!CommandMeasure MeasureScript "HoverTile(2)"]
MouseLeaveAction=[!CommandMeasure MeasureScript "LeaveTile(2)"]

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

[Tile3]
Meter=Image
MeterStyle=StyleTile
X=(#PadX#+2*(#TileW#+#Gap#))
Y=(#PadY#+#MenuH#+#Gap#+0*(#TileH#+#Gap#))
LeftMouseUpAction=[!CommandMeasure MeasureScript "Launch(3)"]
MouseOverAction=[!CommandMeasure MeasureScript "HoverTile(3)"]
MouseLeaveAction=[!CommandMeasure MeasureScript "LeaveTile(3)"]

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

[Tile4]
Meter=Image
MeterStyle=StyleTile
X=(#PadX#+3*(#TileW#+#Gap#))
Y=(#PadY#+#MenuH#+#Gap#+0*(#TileH#+#Gap#))
LeftMouseUpAction=[!CommandMeasure MeasureScript "Launch(4)"]
MouseOverAction=[!CommandMeasure MeasureScript "HoverTile(4)"]
MouseLeaveAction=[!CommandMeasure MeasureScript "LeaveTile(4)"]

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

[Tile5]
Meter=Image
MeterStyle=StyleTile
X=(#PadX#+0*(#TileW#+#Gap#))
Y=(#PadY#+#MenuH#+#Gap#+1*(#TileH#+#Gap#))
LeftMouseUpAction=[!CommandMeasure MeasureScript "Launch(5)"]
MouseOverAction=[!CommandMeasure MeasureScript "HoverTile(5)"]
MouseLeaveAction=[!CommandMeasure MeasureScript "LeaveTile(5)"]

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

[Tile6]
Meter=Image
MeterStyle=StyleTile
X=(#PadX#+1*(#TileW#+#Gap#))
Y=(#PadY#+#MenuH#+#Gap#+1*(#TileH#+#Gap#))
LeftMouseUpAction=[!CommandMeasure MeasureScript "Launch(6)"]
MouseOverAction=[!CommandMeasure MeasureScript "HoverTile(6)"]
MouseLeaveAction=[!CommandMeasure MeasureScript "LeaveTile(6)"]

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

[Tile7]
Meter=Image
MeterStyle=StyleTile
X=(#PadX#+2*(#TileW#+#Gap#))
Y=(#PadY#+#MenuH#+#Gap#+1*(#TileH#+#Gap#))
LeftMouseUpAction=[!CommandMeasure MeasureScript "Launch(7)"]
MouseOverAction=[!CommandMeasure MeasureScript "HoverTile(7)"]
MouseLeaveAction=[!CommandMeasure MeasureScript "LeaveTile(7)"]

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

[Tile8]
Meter=Image
MeterStyle=StyleTile
X=(#PadX#+3*(#TileW#+#Gap#))
Y=(#PadY#+#MenuH#+#Gap#+1*(#TileH#+#Gap#))
LeftMouseUpAction=[!CommandMeasure MeasureScript "Launch(8)"]
MouseOverAction=[!CommandMeasure MeasureScript "HoverTile(8)"]
MouseLeaveAction=[!CommandMeasure MeasureScript "LeaveTile(8)"]

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
