import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// The bar's read on Juno. It watches the daemon's tiny state file rather
// than holding a socket open, so the widget costs nothing while Juno sleeps
// and still shows the truth the instant she wakes.
BarWidget {
  id: root
  moduleName: "juno.assistant"

  property string phase: "idle"
  property bool muted: false
  property bool online: false

  readonly property string runtime: Quickshell.env("XDG_RUNTIME_DIR")
  readonly property bool live: online && phase !== "idle"

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  FileView {
    path: root.runtime + "/juno-state.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.apply(text())
    onLoadFailed: { root.online = false; root.phase = "idle" }
  }

  function apply(raw) {
    try {
      var s = JSON.parse(String(raw || ""))
      root.phase = s.state || "idle"
      root.muted = !!s.muted
      root.online = true
    } catch (e) {
      root.online = false
    }
  }

  readonly property string glyph: {
    if (!online) return ""
    if (muted) return ""
    switch (phase) {
    case "listening": return ""
    case "thinking":  return ""
    case "speaking":  return ""
    default:          return ""
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.glyph
    active: root.live
    useActiveColor: true
    horizontalMargin: 7

    onPressed: function(which) {
      if (which === Qt.RightButton) root.bar.run("juno wake")
      else root.bar.run("omarchy-shell shell toggle juno.assistant '{}'")
    }
  }

  // A halo that only exists while Juno is doing something. In a bar full of
  // static glyphs, motion is the whole signal.
  Rectangle {
    anchors.centerIn: button
    z: -1
    width: Math.min(root.barSize, Style.bar.iconSlot) - 4
    height: width
    radius: width / 2
    visible: root.live
    color: Util.alpha(root.phase === "speaking" ? Color.urgent : Color.accent, 0.22)

    SequentialAnimation on opacity {
      running: root.live
      loops: Animation.Infinite
      NumberAnimation { from: 0.25; to: 1.0; duration: 780; easing.type: Easing.InOutSine }
      NumberAnimation { from: 1.0; to: 0.25; duration: 780; easing.type: Easing.InOutSine }
    }
  }
}
