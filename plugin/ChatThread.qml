import QtQuick
import qs.Commons
import qs.Ui

// The conversation. Your words are a quiet right-aligned chip; Juno's are
// set large and left-aligned, because the reply is the thing you came for.
// Between them sits the activity rail — the live account of what Juno is
// actually doing, which is the difference between waiting and watching.
Item {
  id: root

  property var messages: []
  property string streaming: ""
  property var tools: []
  property bool busy: false
  property string errorText: ""
  property string blockedText: ""
  property color foreground: Color.foreground
  property color accent: Color.accent
  property string fontFamily: Style.font.menuFamily
  // The theme font is a Latin monospace and has no Devanagari glyphs, so
  // Hindi would render as a row of empty boxes. Swap the family per message
  // rather than globally, so English keeps the terminal look it should have.
  property string devanagariFamily: "Noto Sans Devanagari"

  function scriptFamily(text) {
    return /[ऀ-ॿ]/.test(String(text || "")) ? devanagariFamily : fontFamily
  }

  // Each monitor's thread follows its own content. The root used to call
  // scrollToEnd() on "the" thread, which stopped meaning anything once there
  // was one per screen.
  onMessagesChanged: Qt.callLater(scrollToEnd)
  onStreamingChanged: Qt.callLater(scrollToEnd)

  signal allowRequested()
  signal dismissBlocked()

  function alpha(c, a) { return Util.alpha(c, a) }

  function scrollToEnd() {
    // Only follow the tail when the reader is already there; yanking the
    // view while someone scrolls back is the rudest thing a chat UI does.
    if (flick.atYEnd || flick.contentHeight <= flick.height + 4)
      tail.restart()
  }

  Timer {
    id: tail
    interval: 16
    onTriggered: flick.contentY = Math.max(0, flick.contentHeight - flick.height)
  }

  Flickable {
    id: flick
    anchors.fill: parent
    contentWidth: width
    contentHeight: column.height
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    flickDeceleration: 4000

    Column {
      id: column
      width: flick.width
      spacing: Style.spacing.xl
      // A short conversation sits against the composer rather than floating
      // at the top of an empty card — the newest line is always where your
      // eye already is.
      y: Math.max(0, flick.height - height)

      Repeater {
        model: root.messages

        Item {
          required property var modelData
          readonly property bool mine: modelData.role === "user"
          readonly property string body: modelData.text || ""

          width: column.width
          height: mine ? chip.height : answer.implicitHeight

          // Each turn fades up rather than snapping in. Declared as a
          // Behavior, not a targeted animation: inside a delegate, a
          // non-visual animation's `parent` does not resolve to the
          // delegate, and the turn would sit at opacity 0 forever.
          opacity: 0
          Component.onCompleted: opacity = 1
          Behavior on opacity {
            NumberAnimation { duration: 260; easing.type: Easing.OutCubic }
          }

          // Your turn: a quiet chip, right-aligned, deliberately secondary.
          Rectangle {
            id: chip
            visible: parent.mine
            anchors.right: parent.right
            width: Math.min(parent.width * 0.82,
                            userText.implicitWidth + Style.spacing.rowPaddingX * 2)
            height: userText.implicitHeight + Style.spacing.controlPaddingY * 2
            radius: Style.space(12)
            color: root.alpha(root.foreground, 0.07)

            Text {
              id: userText
              anchors.centerIn: parent
              width: parent.width - Style.spacing.rowPaddingX * 2
              text: parent.parent.body
              color: root.alpha(root.foreground, 0.78)
              font.family: root.scriptFamily(text)
              font.pixelSize: Style.font.body
              wrapMode: Text.WordWrap
              horizontalAlignment: Text.AlignRight
            }
          }

          // Juno's turn: full width, larger, generous leading. This is the
          // thing the user came for, so it gets the room.
          Text {
            id: answer
            visible: !parent.mine
            width: parent.width
            text: parent.body
            color: root.foreground
            font.family: root.scriptFamily(text)
            font.pixelSize: Style.font.subtitle
            lineHeight: 1.45
            lineHeightMode: Text.ProportionalHeight
            wrapMode: Text.WordWrap
            textFormat: Text.PlainText
          }
        }
      }

      // The answer currently arriving, rendered with the same type as a
      // finished one so nothing shifts when it completes.
      Text {
        width: column.width
        visible: root.streaming !== ""
        text: root.streaming
        color: root.foreground
        font.family: root.scriptFamily(text)
        font.pixelSize: Style.font.subtitle
        lineHeight: 1.45
        lineHeightMode: Text.ProportionalHeight
        wrapMode: Text.WordWrap
        textFormat: Text.PlainText
      }

      // ------------------------------------------------------ activity rail

      Column {
        width: column.width
        spacing: Style.spacing.sm
        visible: root.tools.length > 0

        Repeater {
          model: root.tools

          Rectangle {
            required property var modelData
            width: column.width
            height: Style.space(30)
            radius: Style.space(8)
            color: root.alpha(root.foreground, 0.045)
            border.width: 1
            border.color: root.alpha(root.foreground, modelData.done ? 0.06 : 0.14)
            Behavior on border.color { ColorAnimation { duration: 240 } }

            opacity: 0
            Component.onCompleted: opacity = 1
            Behavior on opacity { NumberAnimation { duration: 220 } }

            Row {
              anchors.fill: parent
              anchors.leftMargin: Style.spacing.rowPaddingX
              anchors.rightMargin: Style.spacing.rowPaddingX
              spacing: Style.spacing.md

              // Pending work gets a pulsing dot; finished work gets a
              // verdict. One glance tells you where Juno is.
              Item {
                width: Style.space(8)
                height: parent.height
                Rectangle {
                  anchors.centerIn: parent
                  width: Style.space(6)
                  height: width
                  radius: width / 2
                  color: !modelData.done ? root.accent
                       : modelData.ok ? root.alpha(root.foreground, 0.4)
                       : Color.urgent
                  SequentialAnimation on opacity {
                    running: !modelData.done
                    loops: Animation.Infinite
                    NumberAnimation { from: 1; to: 0.25; duration: 620 }
                    NumberAnimation { from: 0.25; to: 1; duration: 620 }
                  }
                }
              }

              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: modelData.name
                color: root.alpha(root.foreground, 0.85)
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
              }

              Text {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - Style.space(8) - Style.space(90)
                text: modelData.detail
                color: root.alpha(root.foreground, 0.45)
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                elide: Text.ElideMiddle
              }
            }
          }
        }
      }

      // Three dots while Juno has said nothing yet — the gap between asking
      // and the first token is the one place a spinner earns its keep.
      Row {
        visible: root.busy && root.streaming === ""
        spacing: Style.spacing.xs
        height: Style.space(20)

        Repeater {
          model: 3
          Rectangle {
            required property int index
            width: Style.space(6)
            height: width
            radius: width / 2
            anchors.verticalCenter: parent.verticalCenter
            color: root.accent
            SequentialAnimation on opacity {
              running: root.busy
              loops: Animation.Infinite
              PauseAnimation { duration: index * 160 }
              NumberAnimation { from: 0.25; to: 1; duration: 380 }
              NumberAnimation { from: 1; to: 0.25; duration: 380 }
              PauseAnimation { duration: (2 - index) * 160 }
            }
          }
        }
      }

      // ---------------------------------------------------------- blocked

      Rectangle {
        width: column.width
        visible: root.blockedText !== ""
        height: visible ? blockCol.height + Style.spacing.panelPadding : 0
        radius: Style.space(10)
        color: root.alpha(Color.urgent, 0.10)
        border.width: 1
        border.color: root.alpha(Color.urgent, 0.35)

        Column {
          id: blockCol
          anchors.centerIn: parent
          width: parent.width - Style.spacing.panelPadding * 2
          spacing: Style.spacing.md

          Text {
            width: parent.width
            text: "Juno stopped before " + root.blockedText
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          Row {
            spacing: Style.spacing.md

            Rectangle {
              width: allowLabel.implicitWidth + Style.spacing.controlPaddingX * 2
              height: Style.space(26)
              radius: Style.space(6)
              color: allowHover.hovered ? root.alpha(Color.urgent, 0.35)
                                        : root.alpha(Color.urgent, 0.2)
              Behavior on color { ColorAnimation { duration: 140 } }
              Text {
                id: allowLabel
                anchors.centerIn: parent
                text: "Run it anyway"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
              HoverHandler { id: allowHover; cursorShape: Qt.PointingHandCursor }
              TapHandler { onTapped: root.allowRequested() }
            }

            Rectangle {
              width: skipLabel.implicitWidth + Style.spacing.controlPaddingX * 2
              height: Style.space(26)
              radius: Style.space(6)
              color: skipHover.hovered ? root.alpha(root.foreground, 0.10) : "transparent"
              Behavior on color { ColorAnimation { duration: 140 } }
              Text {
                id: skipLabel
                anchors.centerIn: parent
                text: "Leave it"
                color: root.alpha(root.foreground, 0.6)
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
              HoverHandler { id: skipHover; cursorShape: Qt.PointingHandCursor }
              TapHandler { onTapped: root.dismissBlocked() }
            }
          }
        }
      }

      // ------------------------------------------------------------ error

      Text {
        width: column.width
        visible: root.errorText !== ""
        text: root.errorText
        color: Color.urgent
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        wrapMode: Text.WordWrap
      }

      Item { width: 1; height: Style.spacing.md }
    }
  }

  // A fade at the top edge so scrolled-away text dissolves instead of being
  // guillotined by the card border.
  Rectangle {
    anchors.top: parent.top
    width: parent.width
    height: Style.space(24)
    visible: !flick.atYBeginning
    gradient: Gradient {
      GradientStop { position: 0.0; color: Color.menu.background }
      GradientStop { position: 1.0; color: "transparent" }
    }
  }

}
