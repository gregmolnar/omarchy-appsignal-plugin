import QtQuick
import qs.Commons

Item {
  id: root
  property real iconSize: Style.font.icon
  property color color: Color.foreground

  implicitWidth: iconSize
  implicitHeight: iconSize
  width: iconSize
  height: iconSize

  Text {
    anchors.centerIn: parent
    text: "󰓅"
    color: root.color
    font.family: Style.font.family
    font.pixelSize: root.iconSize
    renderType: Text.NativeRendering
  }
}
