import QtQuick
import qs.Commons
import qs.Commons as Commons

// Small-caps section label in the accent color.
// Adapted from OmaStats by Carmine Paolino (MIT).
Text {
  id: root

  property string fontFamily: Style.font.family

  textFormat: Text.PlainText
  color: Commons.Color.accent
  font.family: fontFamily
  font.pixelSize: Style.font.caption
  font.bold: true
  font.letterSpacing: 1.1
  font.capitalization: Font.AllUppercase
  elide: Text.ElideRight
  topPadding: Math.ceil(Style.font.caption * 0.15)
}
