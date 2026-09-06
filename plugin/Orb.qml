import QtQuick
import QtQuick.Effects
import qs.Commons

// Juno's face.
//
// Three blurred blobs orbiting inside a clipped circle read as one living
// body of light rather than three shapes — cheaper than a shader, and it
// inherits the theme's palette for free. The ring around it is a real
// waveform: a scrolling history of microphone level, so it moves with the
// shape of your voice instead of pulsing on a timer.
Item {
  id: root

  property string mode: "idle"         // idle | listening | thinking | speaking
  // Set false whenever the orb is off screen. Every animation, timer and
  // blur pass below is gated on this: a hidden window that keeps compositing
  // a 400px gaussian blur is a battery bug, not a visual effect.
  // (Named `animating`, not `active` — `active` already means "Juno is
  // listening or speaking" a few lines down.)
  property bool animating: true
  property real level: 0               // 0..1, live mic amplitude
  property color accent: Color.accent
  property color warm: Color.urgent
  property color foreground: Color.foreground
  property bool offline: false

  readonly property bool active: mode === "listening" || mode === "speaking"
  readonly property real diameter: Math.min(width, height)

  // One smoothed value drives scale, glow and ring gain together, so every
  // part of the orb agrees about how loud the room is.
  property real smoothLevel: 0
  Behavior on smoothLevel {
    NumberAnimation { duration: 90; easing.type: Easing.OutQuad }
  }
  onLevelChanged: smoothLevel = Math.max(0, Math.min(1, level))

  // Breathing. Idle is a slow tide; listening rides the voice on top of it.
  property real breathe: 0
  SequentialAnimation on breathe {
    running: root.animating
    loops: Animation.Infinite
    NumberAnimation { from: 0; to: 1; duration: 2600; easing.type: Easing.InOutSine }
    NumberAnimation { from: 1; to: 0; duration: 2600; easing.type: Easing.InOutSine }
  }

  property real spin: 0
  NumberAnimation on spin {
    running: root.animating
    loops: Animation.Infinite
    from: 0; to: 360
    duration: root.mode === "thinking" ? 2600 : 11000
  }

  readonly property real pulse: 1
    + breathe * (active ? 0.018 : 0.032)
    + (mode === "listening" ? smoothLevel * 0.14 : 0)
    + (mode === "speaking" ? smoothLevel * 0.06 : 0)

  property color moodA: offline ? Qt.darker(foreground, 2.2)
    : mode === "speaking" ? warm : accent
  property color moodB: offline ? Qt.darker(foreground, 2.6)
    : mode === "thinking" ? Qt.lighter(accent, 1.5) : foreground

  Behavior on moodA { ColorAnimation { duration: 420 } }
  Behavior on moodB { ColorAnimation { duration: 420 } }

  function alpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }

  // ------------------------------------------------------------- waveform
  //
  // A ring buffer of past levels. New samples enter at the top of the circle
  // and travel outward in both directions, which is what makes it read as a
  // voice rather than a spinner.

  property int barCount: 48
  property var wave: []

  Component.onCompleted: {
    var seed = []
    for (var i = 0; i < barCount; i++) seed.push(0)
    wave = seed
  }

  Timer {
    interval: 33
    running: root.animating
    repeat: true
    onTriggered: {
      // Sample enters at index 0 (top of the circle) and each tick pushes
      // every earlier sample one step further around, in both directions.
      var half = Math.floor(root.barCount / 2)
      var shifted = new Array(root.barCount).fill(0)
      for (var k = 1; k <= half; k++) {
        shifted[k] = root.wave[k - 1] || 0
        var mirror = root.barCount - k
        if (mirror > half) shifted[mirror] = root.wave[mirror + 1] || 0
      }
      var input = root.mode === "listening" ? root.smoothLevel
        : root.mode === "speaking" ? 0.22 + root.smoothLevel * 0.5
        : root.mode === "thinking" ? 0.10 + Math.random() * 0.12
        : 0.02 + Math.random() * 0.03
      var sample = Math.min(1, input * (0.75 + Math.random() * 0.5))
      shifted[0] = sample
      shifted[root.barCount - 1] = sample * 0.85
      root.wave = shifted
    }
  }

  // ----------------------------------------------------------------- body

  Item {
    id: orb
    anchors.centerIn: parent
    width: root.diameter * 0.62
    height: width
    scale: root.pulse
    Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutQuad } }

    // The blobs live in a layered, clipped item so the blur cannot bleed
    // past the sphere's edge.
    Item {
      id: blobField
      anchors.fill: parent
      layer.enabled: true
      layer.smooth: true
      layer.textureSize: Qt.size(Math.max(2, Math.round(width / 2)),
                                 Math.max(2, Math.round(height / 2)))
      visible: false

      Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: Qt.rgba(root.moodA.r, root.moodA.g, root.moodA.b, 0.20)
      }

      Repeater {
        model: 3
        Rectangle {
          required property int index
          readonly property real phase: root.spin + index * 137
          readonly property real orbit: blobField.width * (0.13 + index * 0.05)
          width: blobField.width * (0.62 - index * 0.08)
          height: width
          radius: width / 2
          x: blobField.width / 2 - width / 2
             + Math.cos(phase * Math.PI / 180) * orbit
          y: blobField.height / 2 - height / 2
             + Math.sin(phase * Math.PI / 180 * (index === 1 ? -1.4 : 1)) * orbit
          color: index === 0 ? root.alpha(root.moodA, 0.95)
               : index === 1 ? root.alpha(root.moodB, 0.55)
               : root.alpha(Qt.lighter(root.moodA, 1.6), 0.45)
        }
      }
    }

    MultiEffect {
      anchors.fill: parent
      source: blobField
      blurEnabled: true
      blur: 1.0
      // Proportional, not absolute: the same orb has to read at 42px in the
      // header and at 400px on the ambient screen.
      blurMax: Math.max(6, Math.min(36, Math.round(orb.width * 0.30)))
      blurMultiplier: 1.2
      saturation: root.offline ? -0.7 : 0.35
      maskEnabled: true
      maskSource: sphereMask
      opacity: root.offline ? 0.45 : 0.95
      Behavior on opacity { NumberAnimation { duration: 300 } }
    }

    Item {
      id: sphereMask
      anchors.fill: parent
      layer.enabled: true
      visible: false
      Rectangle {
        anchors.fill: parent
        radius: width / 2
        gradient: Gradient {
          GradientStop { position: 0.0; color: "#ffffffff" }
          GradientStop { position: 0.72; color: "#ffffffff" }
          GradientStop { position: 1.0; color: "#00ffffff" }
        }
      }
    }

    // A specular highlight. Without it the orb reads flat; with it, spherical.
    Rectangle {
      anchors.fill: parent
      radius: width / 2
      gradient: Gradient {
        GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.16) }
        GradientStop { position: 0.45; color: Qt.rgba(1, 1, 1, 0.02) }
        GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.16) }
      }
    }

    // Rim light — the edge that separates the orb from the backdrop.
    Rectangle {
      anchors.fill: parent
      radius: width / 2
      color: "transparent"
      border.width: Math.max(1.25, parent.width * 0.014)
      border.color: root.alpha(root.moodA, root.active ? 0.7 : 0.35)
      Behavior on border.color { ColorAnimation { duration: 300 } }
    }
  }

  // Outer glow, sitting under everything, sized by the same pulse.
  Rectangle {
    anchors.centerIn: parent
    z: -1
    width: orb.width * 1.32
    height: width
    radius: width / 2
    opacity: root.offline ? 0.05
      : (root.active ? 0.14 + root.smoothLevel * 0.16 : 0.10)
    color: root.alpha(root.moodA, 0.5)
    layer.enabled: true
    layer.effect: MultiEffect {
      blurEnabled: true
      blur: 1.0
      blurMax: Math.max(8, Math.min(44, Math.round(orb.width * 0.45)))
      autoPaddingEnabled: true
    }
    layer.textureSize: Qt.size(Math.max(2, Math.round(width / 2)),
                               Math.max(2, Math.round(height / 2)))
    Behavior on opacity { NumberAnimation { duration: 400 } }
  }

  // ------------------------------------------------------------ the ring

  Item {
    id: ring
    anchors.centerIn: parent
    width: root.diameter
    height: width
    opacity: root.offline ? 0.25 : 1
    rotation: root.mode === "thinking" ? root.spin : 0
    Behavior on opacity { NumberAnimation { duration: 300 } }

    Repeater {
      model: root.barCount

      Rectangle {
        required property int index
        readonly property real sample: root.wave[index] !== undefined ? root.wave[index] : 0
        // The tail of the waveform fades as it travels away from the source.
        readonly property real distance: Math.min(index, root.barCount - index)
                                         / (root.barCount / 2)
        readonly property real gain: 1 - distance * 0.72
        readonly property real amplitude: sample * gain

        width: Math.max(1.5, root.diameter * 0.008)
        height: root.diameter * (0.022 + amplitude * 0.16)
        radius: width / 2
        color: root.alpha(
          index % 9 === 0 ? root.moodB : root.moodA,
          0.18 + amplitude * 0.75)

        transform: [
          Translate {
            x: ring.width / 2 - width / 2
            y: ring.height / 2 - root.diameter * 0.40 - height
          },
          Rotation {
            origin.x: ring.width / 2
            origin.y: ring.height / 2
            angle: index * (360 / root.barCount)
          }
        ]

        // No Behavior here on purpose. The ring is redrawn 30 times a
        // second from the sample buffer, which is already smooth; adding a
        // tween per bar meant 48 concurrent animators every frame for
        // motion the eye cannot separate from the samples themselves.
      }
    }
  }

  // A sweeping arc that only appears while Juno is working, so "thinking"
  // never looks like "frozen".
  Rectangle {
    anchors.centerIn: parent
    width: root.diameter * 0.86
    height: width
    radius: width / 2
    color: "transparent"
    visible: opacity > 0.01
    opacity: root.mode === "thinking" ? 1 : 0
    border.width: Math.max(1, root.diameter * 0.006)
    border.color: root.alpha(root.moodA, 0.10)
    Behavior on opacity { NumberAnimation { duration: 260 } }

    Rectangle {
      width: parent.width
      height: parent.height
      radius: width / 2
      color: "transparent"
      border.width: parent.border.width
      border.color: root.alpha(root.moodA, 0.85)
      rotation: root.spin * 2.4
      // A conic sweep is not available without a shader; masking the ring
      // with a fading gradient gives the same read for a fraction of the cost.
      // The layer only exists while the sweep is on screen.
      layer.enabled: root.mode === "thinking"
      layer.effect: MultiEffect {
        maskEnabled: true
        maskSource: sweepMask
        maskSpreadAtMin: 0.2
      }
    }
  }

  Item {
    id: sweepMask
    width: root.diameter * 0.86
    height: width
    layer.enabled: true
    visible: false
    Rectangle {
      anchors.fill: parent
      gradient: Gradient {
        orientation: Gradient.Horizontal
        GradientStop { position: 0.0; color: "#00ffffff" }
        GradientStop { position: 0.5; color: "#00ffffff" }
        GradientStop { position: 0.88; color: "#ffffffff" }
        GradientStop { position: 1.0; color: "#ffffffff" }
      }
    }
  }
}
