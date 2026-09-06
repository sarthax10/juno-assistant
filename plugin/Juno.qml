import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui

// The face of Juno.
//
// This window is a pure subscriber. Every fact it shows arrives as a JSON
// event from the daemon over `juno stream`, and every action it takes goes
// back out as a one-shot `juno <cmd>`. Nothing here owns state that would
// be lost on a reload — close it mid-answer and the answer still finishes.
//
// Two layouts share one window. Before you have said anything, the orb is
// the whole interface, centered and large. The moment there is a
// conversation, the orb docks to the header and the thread takes the room.
// The transition is animated because the two are the same object.
Item {
  id: root

  property bool opened: false
  property string phase: "idle"
  property bool offline: true
  property real level: 0

  property var messages: []          // [{ role, text }]
  property string streaming: ""      // assistant text arriving right now
  property var tools: []             // [{ id, name, detail, done, ok }]
  property string errorText: ""
  property string blockedText: ""
  property string wakeWord: "Juno"
  property bool micMuted: false
  property bool speakEnabled: true
  property string workspace: ""
  property var health: ({})
  property string lastNoise: ""
  property string draft: ""
  property double followUntil: 0        // epoch ms the free-listening window ends
  property int followRemaining: 0

  readonly property bool conversing: messages.length > 0 || streaming !== ""
  readonly property bool busy: phase === "thinking"

  // ------------------------------------------------------------- geometry

  readonly property color surface: Color.menu.background
  readonly property color foreground: Color.menu.text
  readonly property color scrim: Color.menu.scrim
  readonly property color accent: Color.accent
  readonly property color muted: Qt.darker(foreground, 1.7)
  readonly property color hairline: Util.alpha(foreground, 0.10)
  readonly property string fontFamily: Style.font.menuFamily
  readonly property int radius: Math.max(Style.cornerRadius, Style.space(16))

  function alpha(c, a) { return Util.alpha(c, a) }

  // --------------------------------------------------------------- plumbing

  function send(args) { Util.execArgv(["juno"].concat(args)) }

  function open(payloadJson) {
    root.opened = true
    root.errorText = ""
  }

  function close() {
    root.opened = false
    root.draft = ""
  }

  function toggle() { root.opened ? root.close() : root.open("{}") }

  function submitDraft() {
    var text = root.draft.trim()
    if (text === "") return
    root.draft = ""
    root.send(["ask", text])
  }

  function pushMessage(role, text) {
    var next = root.messages.slice()
    next.push({ role: role, text: text })
    root.messages = next.slice(-40)
  }

  function clearConversation() {
    root.messages = []
    root.streaming = ""
    root.tools = []
    root.errorText = ""
    root.blockedText = ""
    root.send(["clear"])
  }

  // ------------------------------------------------------------ event feed

  Process {
    id: feed
    running: true
    command: ["juno", "stream"]
    stdout: SplitParser {
      splitMarker: "\n"
      onRead: function(line) { root.handleEvent(line) }
    }
    onExited: function(code, status) {
      root.offline = true
      restart.start()
    }
  }

  Timer {
    id: noiseFade
    interval: 2200
    onTriggered: root.lastNoise = ""
  }

  // Drives the countdown ring while the free-listening window runs down.
  Timer {
    id: followTick
    interval: 100
    repeat: true
    running: root.opened && root.followUntil > 0
    onTriggered: if (Date.now() > root.followUntil) root.followUntil = 0
  }

  property double nowMs: Date.now()
  Timer {
    interval: 100
    repeat: true
    running: root.opened
    onTriggered: root.nowMs = Date.now()
  }

  readonly property real followProgress: followUntil > 0
    ? Math.max(0, Math.min(1, (followUntil - nowMs) / 6000)) : 0

  Timer {
    id: restart
    interval: 1500
    onTriggered: if (!feed.running) feed.running = true
  }

  // The daemon publishes microphone levels only while something is showing
  // them. Ask while open, stop asking when closed, and re-assert
  // periodically so the claim lapses on its own if this window dies.
  Timer {
    id: levelLease
    interval: 10000
    repeat: true
    running: root.opened
    triggeredOnStart: true
    onTriggered: root.send(["levels", "on"])
  }

  onOpenedChanged: if (!opened) root.send(["levels", "off"])

  function handleEvent(line) {
    var e
    try { e = JSON.parse(line) } catch (err) { return }
    if (!e || !e.t) return

    switch (e.t) {
    case "offline":
      root.offline = true
      root.phase = "idle"
      return

    case "hello":
      root.offline = false
      root.phase = e.state || "idle"
      root.health = e.health || ({})
      if (e.config) {
        root.wakeWord = root.titleize(e.config.wakeWord || "Juno")
        root.micMuted = !!e.config.micMuted
        root.speakEnabled = e.config.speak !== false
        root.workspace = e.config.workspace || ""
      }
      var restored = []
      var hist = e.history || []
      for (var i = 0; i < hist.length; i++)
        restored.push({ role: hist[i].role, text: hist[i].text })
      root.messages = restored.slice(-40)
        return

    case "state":
      root.phase = e.state
      if (e.state === "thinking") root.streaming = ""
      return

    case "level":
      root.level = e.rms || 0
      return

    case "wake":
    case "awake":
      root.errorText = ""
      root.blockedText = ""
      root.followUntil = 0
      return

    case "listening_followup":
      root.followUntil = Date.now() + (e.seconds || 6) * 1000
      root.followRemaining = e.remaining || 0
      return

    case "sleep":
      root.followUntil = 0
      return

    case "noise":
      // Heard, judged to be the room rather than a person, discarded.
      root.lastNoise = e.text || ""
      noiseFade.restart()
      return

    case "user":
      root.streaming = ""
      root.tools = []
      root.pushMessage("user", e.text || "")
      return

    case "delta":
      root.streaming += (e.text || "")
        return

    case "assistant":
      root.streaming = ""
      root.pushMessage("assistant", e.text || "")
      return

    case "tool": {
      var t = root.tools.slice()
      t.push({ id: e.id, name: e.name || "", detail: e.detail || "",
               done: false, ok: true })
      root.tools = t.slice(-6)
      return
    }

    case "tool_done": {
      var list = root.tools.slice()
      for (var j = 0; j < list.length; j++) {
        if (list[j].id === e.id) {
          list[j] = { id: list[j].id, name: list[j].name,
                      detail: list[j].detail, done: true, ok: !!e.ok }
        }
      }
      root.tools = list
      return
    }

    case "blocked":
      root.blockedText = e.reason || "a command Juno will not run"
      return

    case "error":
      root.errorText = e.message || ""
      return

    case "cleared":
      root.messages = []
      root.streaming = ""
      root.tools = []
      return

    case "config":
      if (e.key === "micMuted") root.micMuted = !!e.value
      if (e.key === "speak") root.speakEnabled = !!e.value
      return
    }
  }

  function titleize(word) {
    if (!word || word.length === 0) return "Juno"
    return word.charAt(0).toUpperCase() + word.slice(1)
  }

  readonly property string statusLine: {
    if (offline) return "Juno is not running"
    if (micMuted) return "Microphone muted — she cannot hear you"
    switch (phase) {
    case "listening":
      return followUntil > 0
        ? "Listening — no need to say her name (" + Math.ceil((followUntil - nowMs) / 1000) + "s)"
        : "Listening — go ahead"
    case "thinking":  return "Thinking…"
    case "speaking":  return "Speaking…"
    default:          return "Say “Hey " + wakeWord + "” to begin"
    }
  }

  // ------------------------------------------------------------------ view

  // Unmistakable "you are being heard" signal, independent of the panel.
  // The question "is it actually listening to me right now?" should never
  // require reading text — the whole screen answers it.
  // One surface per monitor. A single PanelWindow binds to one screen, so
  // on a multi-monitor desk the overlay appeared on the left display and was
  // invisible to anyone looking at the right one.
  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: earshot
      required property var modelData
      screen: modelData
      visible: root.phase === "listening" && !root.micMuted && !root.offline
      anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "juno-listening"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    mask: Region {}                     // never intercepts a click

    Rectangle {
      anchors.fill: parent
      color: "transparent"
      border.width: Math.max(2, Style.space(3)) + root.level * Style.space(5)
      border.color: root.alpha(root.accent, 0.35 + root.level * 0.5)
      Behavior on border.width { NumberAnimation { duration: 90 } }
      Behavior on border.color { ColorAnimation { duration: 120 } }

      SequentialAnimation on opacity {
          running: earshot.visible
          loops: Animation.Infinite
          NumberAnimation { from: 0.55; to: 1.0; duration: 900; easing.type: Easing.InOutSine }
          NumberAnimation { from: 1.0; to: 0.55; duration: 900; easing.type: Easing.InOutSine }
        }
      }
    }
  }

  Variants {
    model: Quickshell.screens

    PanelWindow {
    id: window
    required property var modelData
    screen: modelData
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "juno"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    // Backdrop. A plain flat scrim makes the card look pasted on; a vertical
    // wash gives the composition a light source.
    Rectangle {
      anchors.fill: parent
      gradient: Gradient {
        GradientStop { position: 0.0; color: root.alpha(root.scrim, 0.965) }
        GradientStop { position: 1.0; color: root.alpha(Qt.darker(root.scrim, 1.25), 0.97) }
      }
      opacity: root.opened ? 1 : 0
      Behavior on opacity { NumberAnimation { duration: 220 } }

      MouseArea {
        anchors.fill: parent
        onClicked: root.close()
      }
    }

    // A faint bloom of the orb's color leaking into the backdrop.
    Rectangle {
      anchors.horizontalCenter: parent.horizontalCenter
      y: parent.height * (root.conversing ? 0.02 : 0.18)
      width: parent.width * 0.5
      height: width
      radius: width / 2
      color: root.alpha(root.accent, root.phase === "idle" ? 0.05 : 0.11)
      Behavior on color { ColorAnimation { duration: 500 } }
      Behavior on y { NumberAnimation { duration: 420; easing.type: Easing.OutCubic } }
      layer.enabled: true
      layer.effect: MultiEffect {
        blurEnabled: true
        blur: 1.0
        blurMax: 64
        autoPaddingEnabled: true
      }
    }

    PanelKeyCatcher {
      id: keys
      // Each monitor's catcher grabs focus when its own window appears.
      Connections {
        target: root
        function onOpenedChanged() {
          if (root.opened) Qt.callLater(keys.forceActiveFocus)
        }
      }
      anchors.fill: parent
      // The composer owns the keyboard; Escape and Enter are handled there.
      blocked: true
      onCloseRequested: root.close()

      Item {
        id: stage
        anchors.centerIn: parent
        // Proportional to the display, with a floor so it stays usable on a
        // laptop and a ceiling so a line of text never runs the width of an
        // ultrawide. Reading comfort caps out long before the screen does.
        width: Math.max(Style.space(420),
                        Math.min(Style.space(960),
                                 window.width * 0.42,
                                 window.width - Style.space(64)))
        height: Math.max(Style.space(380),
                         Math.min(Style.space(820),
                                  window.height * 0.66,
                                  window.height - Style.space(64)))

        // Entrance: rise and settle, never a linear fade.
        opacity: root.opened ? 1 : 0
        scale: root.opened ? 1 : 0.965
        y: root.opened ? 0 : Style.space(18)
        Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
        Behavior on scale {
          NumberAnimation { duration: 340; easing.type: Easing.OutBack; easing.overshoot: 0.9 }
        }

        // A muted microphone is a state Juno cannot recover from on her own
        // and the user cannot see. It gets a banner, not a dimmed icon.
        Rectangle {
          id: mutedBanner
          visible: opacity > 0.01
          opacity: root.micMuted && !root.offline ? 1 : 0
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.top: parent.top
          width: Math.min(parent.width, mutedRow.implicitWidth + Style.spacing.panelPadding * 2)
          height: Style.space(40)
          radius: height / 2
          color: root.alpha(Color.urgent, 0.16)
          border.width: 1
          border.color: root.alpha(Color.urgent, 0.5)
          z: 20
          Behavior on opacity { NumberAnimation { duration: 200 } }

          Row {
            id: mutedRow
            anchors.centerIn: parent
            spacing: Style.spacing.md

            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: ""
              color: Color.urgent
              font.family: root.fontFamily
              font.pixelSize: Style.font.icon
            }
            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: "Microphone is muted — Juno cannot hear you. Click to unmute."
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
          }

          HoverHandler { cursorShape: Qt.PointingHandCursor }
          TapHandler { onTapped: root.send(["unmute"]) }
        }

        // ------------------------------------------------------ ambient mode

        Item {
          id: ambient
          anchors.fill: parent
          visible: opacity > 0.01
          opacity: root.conversing ? 0 : 1
          Behavior on opacity { NumberAnimation { duration: 260 } }

          Column {
            anchors.centerIn: parent
            spacing: Style.spacing.huge * 2

            Orb {
              width: Math.min(stage.width * 0.62, stage.height * 0.52)
              height: width
              anchors.horizontalCenter: parent.horizontalCenter
              mode: root.phase
              animating: root.opened && !root.conversing
              level: root.level
              offline: root.offline
              accent: root.accent
              warm: Color.urgent
              foreground: root.foreground
            }

            Column {
              anchors.horizontalCenter: parent.horizontalCenter
              spacing: Style.spacing.md

              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.statusLine
                color: root.phase === "idle" ? root.muted : root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.heading
                font.letterSpacing: 0.4
                Behavior on color { ColorAnimation { duration: 300 } }
              }

              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: root.phase === "idle" && !root.offline
                text: "or type below · Esc to dismiss"
                color: root.alpha(root.foreground, 0.35)
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }
            }
          }
        }

        // -------------------------------------------------- conversation mode

        Item {
          id: conversation
          anchors.fill: parent
          visible: opacity > 0.01
          opacity: root.conversing ? 1 : 0
          Behavior on opacity { NumberAnimation { duration: 260 } }

          Rectangle {
            id: card
            anchors.fill: parent
            anchors.bottomMargin: composer.height + Style.spacing.panelGap
            radius: root.radius
            color: root.alpha(root.surface, 0.86)
            border.width: 1
            border.color: root.hairline

            // Glass: the backdrop bloom shows through, so the card needs a
            // top highlight to sit above it rather than in it.
            Rectangle {
              anchors.fill: parent
              radius: parent.radius
              gradient: Gradient {
                GradientStop { position: 0.0; color: root.alpha(root.foreground, 0.045) }
                GradientStop { position: 0.35; color: "transparent" }
              }
            }

            Column {
              anchors.fill: parent
              anchors.margins: Style.spacing.panelPadding
              spacing: Style.spacing.lg

              // ---------------------------------------------------- header
              Item {
                width: parent.width
                height: Style.space(46)

                Orb {
                  id: dockedOrb
                  width: Style.space(42)
                  height: width
                  anchors.verticalCenter: parent.verticalCenter
                  mode: root.phase
                  animating: root.opened && root.conversing
                  level: root.level
                  offline: root.offline
                  accent: root.accent
                  warm: Color.urgent
                  foreground: root.foreground
                }

                Column {
                  anchors.left: dockedOrb.right
                  anchors.leftMargin: Style.spacing.rowPaddingX
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: 1

                  Text {
                    text: root.wakeWord
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.title
                    font.letterSpacing: 0.6
                  }
                  Text {
                    text: root.statusLine
                    color: root.phase === "idle" ? root.alpha(root.foreground, 0.4) : root.accent
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    Behavior on color { ColorAnimation { duration: 250 } }
                  }
                }

                Row {
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.spacing.sm

                  GlyphButton {
                    glyph: root.speakEnabled ? "" : ""
                    tip: root.speakEnabled ? "Mute Juno's voice" : "Let Juno speak"
                    dim: !root.speakEnabled
                    foreground: root.foreground
                    accent: root.accent
                    fontFamily: root.fontFamily
                    onTriggered: root.send([root.speakEnabled ? "quiet" : "speak"])
                  }
                  GlyphButton {
                    glyph: root.micMuted ? "" : ""
                    tip: root.micMuted ? "Unmute the microphone" : "Mute the microphone"
                    dim: root.micMuted
                    foreground: root.foreground
                    accent: root.accent
                    fontFamily: root.fontFamily
                    onTriggered: root.send([root.micMuted ? "unmute" : "mute"])
                  }
                  GlyphButton {
                    glyph: ""
                    tip: "Clear this conversation"
                    foreground: root.foreground
                    accent: root.accent
                    fontFamily: root.fontFamily
                    onTriggered: root.clearConversation()
                  }
                  GlyphButton {
                    glyph: ""
                    tip: "Close"
                    foreground: root.foreground
                    accent: root.accent
                    fontFamily: root.fontFamily
                    onTriggered: root.close()
                  }
                }
              }

              Rectangle {
                width: parent.width
                height: 1
                color: root.hairline
              }

              // ---------------------------------------------------- thread
              ChatThread {
                id: thread
                width: parent.width
                height: parent.height - y
                messages: root.messages
                streaming: root.streaming
                tools: root.tools
                busy: root.busy
                errorText: root.errorText
                blockedText: root.blockedText
                foreground: root.foreground
                accent: root.accent
                fontFamily: root.fontFamily
                onAllowRequested: {
                  root.blockedText = ""
                  root.send(["allow"])
                }
                onDismissBlocked: root.blockedText = ""
              }
            }
          }
        }

        // ------------------------------------------------------- composer

        Rectangle {
          id: composer
          anchors.bottom: parent.bottom
          width: parent.width
          height: Style.space(52)
          radius: Math.min(height / 2, root.radius)
          color: root.alpha(root.surface, 0.92)
          border.width: 1
          border.color: input.activeFocus ? root.alpha(root.accent, 0.55) : root.hairline
          Behavior on border.color { ColorAnimation { duration: 180 } }

          Row {
            anchors.fill: parent
            anchors.leftMargin: Style.spacing.rowPaddingX + Style.spacing.xs
            anchors.rightMargin: Style.spacing.sm
            spacing: Style.spacing.md

            // A live mic level meter doubling as the focus affordance.
            Item {
              width: Style.space(18)
              height: parent.height
              Row {
                anchors.centerIn: parent
                spacing: 2
                Repeater {
                  model: 3
                  Rectangle {
                    required property int index
                    width: 2
                    radius: 1
                    height: root.phase === "listening"
                      ? Style.space(4) + root.level * Style.space(16) * (index === 1 ? 1.4 : 0.8)
                      : Style.space(4)
                    anchors.verticalCenter: parent.verticalCenter
                    color: root.phase === "listening" ? root.accent
                                                      : root.alpha(root.foreground, 0.3)
                    Behavior on height { NumberAnimation { duration: 80 } }
                    Behavior on color { ColorAnimation { duration: 200 } }
                  }
                }
              }
            }

            TextInput {
              id: input
              width: parent.width - Style.space(18) - actions.width - Style.spacing.md * 2
              anchors.verticalCenter: parent.verticalCenter
              text: root.draft
              onTextChanged: root.draft = text
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.subtitle
              selectByMouse: true
              selectionColor: root.alpha(root.accent, 0.4)
              clip: true
              focus: root.opened

              Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: input.text.length === 0
                text: root.offline ? "Juno is offline — run: juno start"
                                   : "Ask " + root.wakeWord + " anything…"
                color: root.alpha(root.foreground, 0.32)
                font: input.font
              }

              Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Escape) {
                  root.close(); event.accepted = true
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                  root.submitDraft(); event.accepted = true
                } else if (event.key === Qt.Key_L && (event.modifiers & Qt.ControlModifier)) {
                  root.clearConversation(); event.accepted = true
                }
              }
            }

            Row {
              id: actions
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.spacing.xs

              GlyphButton {
                visible: root.busy || root.phase === "speaking"
                glyph: ""
                tip: "Stop"
                foreground: root.foreground
                accent: Color.urgent
                fontFamily: root.fontFamily
                onTriggered: root.send(["cancel"])
              }

              // Push to talk: the button is the same affordance as the wake
              // word, for when saying the name out loud is not an option.
              GlyphButton {
                glyph: ""
                tip: "Listen now (⏎ to send typed text)"
                emphasized: root.phase === "listening"
                foreground: root.foreground
                accent: root.accent
                fontFamily: root.fontFamily
                onTriggered: root.draft.trim() !== "" ? root.submitDraft()
                                                      : root.send(["wake"])
              }
            }
          }
        }
      }
    }
  }
  }
}
