import QtQuick
import qs.Commons

// A round icon button. Small enough to live in a header row, with a hover
// fill that grows from the center rather than snapping on, and a tooltip
// that only appears once you have actually rested on it.
Item {
  id: root

  property string glyph: ""
  property string tip: ""
  property bool dim: false
  property bool emphasized: false
  property color foreground: Color.foreground
  property color accent: Color.accent
  property string fontFamily: Style.font.menuFamily
  property int diameter: Style.space(30)

  signal triggered()

  implicitWidth: diameter
  implicitHeight: diameter
  width: diameter
  height: diameter

  readonly property bool hovered: hover.hovered
  readonly property color tint: emphasized ? accent
    : dim ? Util.alpha(foreground, 0.38)
    : hovered ? foreground : Util.alpha(foreground, 0.72)

  Rectangle {
    anchors.centerIn: parent
    width: parent.width * (root.hovered || root.emphasized ? 1 : 0.7)
    height: width
    radius: width / 2
    color: root.emphasized ? Util.alpha(root.accent, 0.18)
         : root.hovered ? Util.alpha(root.foreground, 0.10) : "transparent"
    Behavior on width { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
    Behavior on color { ColorAnimation { duration: 140 } }

    // Emphasis breathes so a live "listening" button never looks static.
    SequentialAnimation on opacity {
      running: root.emphasized
      loops: Animation.Infinite
      NumberAnimation { from: 1.0; to: 0.55; duration: 900; easing.type: Easing.InOutSine }
      NumberAnimation { from: 0.55; to: 1.0; duration: 900; easing.type: Easing.InOutSine }
    }
    onVisibleChanged: if (!root.emphasized) opacity = 1
  }

  Text {
    anchors.centerIn: parent
    text: root.glyph
    color: root.tint
    font.family: root.fontFamily
    font.pixelSize: Style.font.icon
    Behavior on color { ColorAnimation { duration: 140 } }
  }

  HoverHandler {
    id: hover
    cursorShape: Qt.PointingHandCursor
  }

  TapHandler {
    onTapped: root.triggered()
  }

  Rectangle {
    id: tooltip
    visible: opacity > 0.01
    opacity: root.hovered && root.tip !== "" ? 1 : 0
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.top: parent.bottom
    anchors.topMargin: Style.spacing.xs
    width: label.implicitWidth + Style.spacing.controlPaddingX * 2
    height: label.implicitHeight + Style.spacing.xs * 2
    radius: Style.space(6)
    color: Color.tooltip.background
    border.width: 1
    border.color: Util.alpha(Color.tooltip.border, 0.3)
    z: 50
    Behavior on opacity { NumberAnimation { duration: 160 } }

    Text {
      id: label
      anchors.centerIn: parent
      text: root.tip
      color: Color.tooltip.text
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }
  }
}
