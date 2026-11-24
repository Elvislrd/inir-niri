pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import QtQuick.Effects
import Quickshell
import Quickshell.Services.Mpris
import qs.modules.common
import qs.modules.common.widgets
import qs.services

// ─────────────────────────────────────────────────────────────────────────────
//  MediaOrbitPlayer  ·  popup de medios "Orbit"
//
//  Idea: la carátula es una galleta (cookie) cuyo borde late con el audio real
//  (cava) y gira más rápido cuanto más energía tiene la música. Alrededor hay un
//  anillo que es a la vez barra de progreso y rueda de scrubbing.
//
//  Interacción
//    · Clic en la carátula ............ play / pausa
//    · Arrastrar la carátula ← / → .... canción anterior / siguiente (swipe)
//    · Arrastrar sobre el anillo ...... buscar en la canción (como un jog wheel)
//    · Rueda del ratón (en todo) ...... volumen
//    · Pasar el ratón por el título ... se desplaza si es largo
//    · Teclado (si el popup tiene foco): Espacio, ←/→ ±5 s, ↑/↓ volumen, N / P, M
//
//  Colores: usa los mismos tokens que el resto de tu shell (zzz / angel / inir /
//  aurora / material) y tiñe el fondo con el color dominante de la carátula.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    // ── Contrato compatible con MediaDashboardPlayer ─────────────────────────
    required property MprisPlayer player
    property list<real> visualizerPoints: []
    property real normalizationCeiling: 1
    property string outputName: ""
    property bool motion: true
    property real radius: Appearance.rounding.normal
    signal eqRequested()

    implicitWidth: 620
    implicitHeight: 308
    focus: true

    // ── Estado del reproductor ───────────────────────────────────────────────
    readonly property bool playing: root.player?.isPlaying ?? false
    readonly property string title: root.player?.trackTitle || Translation.tr("Unknown title")
    readonly property string artist: root.player?.trackArtist ?? ""
    readonly property string album: root.player?.trackAlbum ?? ""
    readonly property string artUrl: root.player?.trackArtUrl ?? ""
    readonly property real length: Math.max(0, root.player?.length ?? 0)
    readonly property real position: Math.max(0, root.player?.position ?? 0)
    readonly property bool canSeek: (root.player?.canSeek ?? false) && root.length > 0
    readonly property real playFrac: root.length > 0 ? Math.max(0, Math.min(1, root.position / root.length)) : 0

    // ── Tema (mismos tokens que usa BarMediaPopup para su placeholder) ───────
    readonly property bool _zzz: !!Appearance.zzzEverywhere
    readonly property bool _angel: !!Appearance.angelEverywhere
    readonly property bool _inir: !!(Appearance.inirEverywhere && Appearance.inir)
    readonly property bool _aurora: !!(Appearance.auroraEverywhere && Appearance.aurora)

    readonly property color colSurface: _zzz ? Appearance.zzz.bg0
        : _angel ? Appearance.angel.colGlassCard
        : _inir ? Appearance.inir.colLayer1
        : _aurora ? Appearance.aurora.colPopupSurface
        : Appearance.colors.colLayer0
    readonly property color colBorder: _zzz ? Appearance.zzz.borderColor
        : _inir ? Appearance.inir.colBorder
        : _aurora ? Appearance.aurora.colPopupBorder
        : "transparent"
    readonly property real borderW: (_zzz || _inir || _aurora) ? 1 : 0
    readonly property color colText: _zzz ? Appearance.zzz.ink
        : _angel ? Appearance.angel.colText
        : _inir ? Appearance.inir.colText
        : Appearance.colors.colOnLayer0
    readonly property color colSub: _zzz ? Appearance.zzz.ghostInk
        : _angel ? Appearance.angel.colTextSecondary
        : _inir ? Appearance.inir.colTextSecondary
        : _aurora ? Appearance.aurora.colTextSecondary
        : Appearance.colors.colSubtext
    readonly property color colBase: _zzz ? Appearance.zzz.accent
        : _angel ? Appearance.angel.colPrimary
        : _inir ? Appearance.inir.colPrimary
        : Appearance.colors.colPrimary
    readonly property real cardRadius: _zzz ? Appearance.zzz.panelRadius
        : _angel ? Appearance.angel.roundingNormal
        : _inir ? Appearance.inir.roundingNormal
        : root.radius

    readonly property bool isDark: root.colSurface.hslLightness < 0.5
    readonly property color colOnBase: root.colBase.hslLightness > 0.6 ? "#1b1b1f" : "#ffffff"
    readonly property color colTonal: root.mixc(root.colSurface, root.colText, 0.10)
    readonly property color colTrack: root.alpha(root.colText, 0.14)

    // Color dominante de la carátula (lo calcula el Canvas "probe")
    property color _rawArt: "transparent"
    property bool _hasArt: false
    property color artColor: {
        if (!root._hasArt || root._rawArt.hslHue < 0)
            return root.colBase;
        return Qt.hsla(root._rawArt.hslHue,
                       Math.max(0.35, Math.min(0.85, root._rawArt.hslSaturation)),
                       root.isDark ? 0.72 : 0.40, 1);
    }
    Behavior on artColor {
        enabled: Appearance.animationsEnabled
        ColorAnimation { duration: 600 }
    }
    readonly property color cardColor: root.mixc(root.colSurface, root.artColor, root.isDark ? 0.10 : 0.07)
    readonly property color cardColorClear: root.alpha(root.cardColor, 0)

    function alpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a); }
    function mixc(a, b, t) {
        return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, a.a);
    }
    function fmt(sec) {
        const s = Math.max(0, Math.floor(sec || 0));
        const h = Math.floor(s / 3600);
        const m = Math.floor((s % 3600) / 60);
        const ss = s % 60;
        const two = (n) => (n < 10 ? "0" : "") + n;
        return h > 0 ? (h + ":" + two(m) + ":" + two(ss)) : (m + ":" + two(ss));
    }
    function clamp01(v) { return Math.max(0, Math.min(1, v)); }

    // ── Medidas ──────────────────────────────────────────────────────────────
    readonly property real coverSize: 244
    readonly property real ringR: root.coverSize / 2 - 10
    readonly property real cookieR: root.ringR - 30
    readonly property int petals: 9
    readonly property int _N: 96

    // ── Scrubbing / volumen ──────────────────────────────────────────────────
    property bool scrubbing: false
    property bool _hold: false
    property real scrubFrac: 0
    property real shownFrac: (root.scrubbing || root._hold) ? root.scrubFrac : root.playFrac
    Behavior on shownFrac {
        enabled: !root.scrubbing && Appearance.animationsEnabled
        NumberAnimation { duration: 260; easing.type: Easing.Linear }
    }
    readonly property real shownPos: (root.scrubbing || root._hold) ? root.scrubFrac * root.length : root.position

    readonly property bool volSupported: root.player?.volumeSupported ?? false
    property real volDrag: -1
    readonly property real volFrac: root.volDrag >= 0 ? root.volDrag : root.clamp01(root.player?.volume ?? 0)
    property real _prevVol: 0.5
    property bool hudShown: false

    function setVol(v) {
        if (!root.player || !root.volSupported) return;
        root.player.volume = root.clamp01(v);
        root.hudShown = true;
        hudTimer.restart();
    }
    function nudgeVol(delta) { root.setVol((root.player?.volume ?? 0) + delta); }
    function toggleMute() {
        const v = root.player?.volume ?? 0;
        if (v > 0.001) { root._prevVol = v; root.setVol(0); }
        else root.setVol(root._prevVol > 0.001 ? root._prevVol : 0.5);
    }
    function seekFrac(f) {
        if (!root.player || !root.canSeek) return;
        root.player.position = root.clamp01(f) * root.length;
        root.player.positionChanged();
    }
    function seekBy(sec) {
        if (!root.player || !root.canSeek) return;
        root.player.position = Math.max(0, Math.min(root.length, root.position + sec));
        root.player.positionChanged();
    }
    function cycleLoop() {
        if (!root.player || !(root.player.loopSupported ?? false)) return;
        const s = root.player.loopState;
        root.player.loopState = s === MprisLoopState.None ? MprisLoopState.Playlist
            : s === MprisLoopState.Playlist ? MprisLoopState.Track : MprisLoopState.None;
    }

    Timer {
        id: hudTimer
        interval: 1100
        onTriggered: root.hudShown = false
    }
    Timer {
        id: holdTimer
        interval: 550
        onTriggered: root._hold = false
    }
    // Mantiene la posición fresca mientras suena
    Timer {
        running: root.visible && root.playing
        interval: 250
        repeat: true
        onTriggered: root.player?.positionChanged()
    }

    Keys.onPressed: (e) => {
        if (e.key === Qt.Key_Space) root.player?.togglePlaying();
        else if (e.key === Qt.Key_Right) root.seekBy(5);
        else if (e.key === Qt.Key_Left) root.seekBy(-5);
        else if (e.key === Qt.Key_Up) root.nudgeVol(0.05);
        else if (e.key === Qt.Key_Down) root.nudgeVol(-0.05);
        else if (e.key === Qt.Key_N) root.player?.next();
        else if (e.key === Qt.Key_P) root.player?.previous();
        else if (e.key === Qt.Key_M) root.toggleMute();
        else return;
        e.accepted = true;
    }

    WheelHandler {
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: (e) => root.nudgeVol((e.angleDelta.y / 120) * 0.05)
    }

    // ── Motor de la galleta reactiva ─────────────────────────────────────────
    property var maskPoints: []
    property var _lvl: []
    property real _phase: 0
    property real _peak: 0.05
    property real _lastTick: 0
    property real _lastAmp: -1
    property real energy: 0
    property bool coverHover: false
    property real petalAmp: root.playing ? (root.coverHover ? 0.085 : 0.062) : 0.022
    Behavior on petalAmp {
        enabled: Appearance.animationsEnabled
        NumberAnimation { duration: 700; easing.type: Easing.OutCubic }
    }

    function _tick() {
        const now = Date.now();
        let dt = (now - root._lastTick) / 1000;
        if (root._lastTick === 0 || dt > 0.2) dt = 0.033;
        root._lastTick = now;

        const N = root._N;
        const pts = root.visualizerPoints;
        const n = pts ? pts.length : 0;
        const playing = root.playing;

        if (root._lvl.length !== N) root._lvl = new Array(N).fill(0);

        // Normalización adaptativa: no dependemos de la escala de cava
        let mx = 0;
        for (let k = 0; k < n; k++) mx = Math.max(mx, pts[k]);
        root._peak = Math.max(root._peak * 0.994, mx, 0.02);

        const raw = new Array(N);
        for (let i = 0; i < N; i++) {
            // Espectro espejado: graves abajo, agudos arriba
            const th = (i / N) * 2 * Math.PI;
            const u = (1 - Math.cos(th - Math.PI / 2)) / 2;
            let target = 0;
            if (playing) {
                if (n > 1) {
                    const pos = u * (n - 1);
                    const i0 = Math.floor(pos);
                    const i1 = Math.min(n - 1, i0 + 1);
                    const f = pos - i0;
                    target = (pts[i0] * (1 - f) + pts[i1] * f) / root._peak;
                } else {
                    // Sin datos de cava: respiración suave para que no quede muerta
                    target = 0.30 + 0.25 * Math.sin(now / 420 + u * 6);
                }
                target = Math.max(0, Math.min(1, target));
            }
            const cur = root._lvl[i];
            raw[i] = cur + (target - cur) * (target > cur ? 0.6 : 0.14);
        }
        const sm = new Array(N);
        let sum = 0;
        for (let i = 0; i < N; i++) {
            sm[i] = (raw[(i + N - 1) % N] + 2 * raw[i] + raw[(i + 1) % N]) / 4;
            sum += sm[i];
        }
        root._lvl = sm;
        root.energy = (!playing && sum / N < 0.003) ? 0 : sum / N;

        root._phase += dt * (playing ? (0.30 + root.energy * 2.2) : 0);

        const amp = root.petalAmp;
        if (!playing && root.energy === 0 && Math.abs(amp - root._lastAmp) < 0.0004 && root.maskPoints.length > 0)
            return;
        root._lastAmp = amp;

        const c = root.coverSize / 2;
        const R = root.cookieR;
        const gain = 0.26;
        const out = [];
        for (let i = 0; i <= N; i++) {
            const th = (i / N) * 2 * Math.PI;
            const r = R * (1 + amp * Math.cos(root.petals * th + root._phase) + gain * sm[i % N]);
            out.push(Qt.point(c + r * Math.cos(th), c + r * Math.sin(th)));
        }
        root.maskPoints = out;
    }

    Timer {
        running: root.visible && root.motion
        interval: 33
        repeat: true
        onTriggered: root._tick()
    }
    Component.onCompleted: root._tick()

    // ── Extractor de color dominante (funciona con URLs http y file) ─────────
    Canvas {
        id: probe
        width: 24
        height: 24
        opacity: 0.01
        property string src: root.artUrl
        onSrcChanged: {
            if (src.length > 0) loadImage(src);
            else root._hasArt = false;
        }
        Component.onCompleted: if (src.length > 0) loadImage(src)
        onImageLoaded: requestPaint()
        onPaint: {
            const ctx = getContext("2d");
            ctx.clearRect(0, 0, width, height);
            const u = root.artUrl;
            if (!u || !isImageLoaded(u)) return;
            ctx.drawImage(u, 0, 0, width, height);
            let d;
            try { d = ctx.getImageData(0, 0, width, height).data; } catch (e) { return; }
            let r = 0, g = 0, b = 0, ws = 0;
            for (let i = 0; i < d.length; i += 4) {
                if (d[i + 3] < 200) continue;
                const R = d[i] / 255, G = d[i + 1] / 255, B = d[i + 2] / 255;
                const mxv = Math.max(R, G, B), mnv = Math.min(R, G, B);
                if (mxv < 0.18) continue;               // ignora barras negras y sombras
                const s = (mxv - mnv) / mxv;
                const w = 0.1 + s * s * 2 + mxv * 0.3;
                r += R * w; g += G * w; b += B * w; ws += w;
            }
            if (ws > 0) {
                root._rawArt = Qt.rgba(r / ws, g / ws, b / ws, 1);
                root._hasArt = true;
            } else {
                root._hasArt = false;
            }
        }
    }

    // ── Pop al cambiar de canción ────────────────────────────────────────────
    property real popScale: 1
    Connections {
        target: root.player
        function onTrackTitleChanged() {
            if (!Appearance.animationsEnabled) return;
            popAnim.restart();
            textIn.restart();
        }
    }
    SequentialAnimation {
        id: popAnim
        NumberAnimation { target: root; property: "popScale"; to: 0.86; duration: 90; easing.type: Easing.OutQuad }
        NumberAnimation { target: root; property: "popScale"; to: 1; duration: 420; easing.type: Easing.OutBack; easing.overshoot: 2.4 }
    }

    // Latido del punto de estado
    property real _beat: 1
    SequentialAnimation on _beat {
        running: root.playing && Appearance.animationsEnabled
        loops: Animation.Infinite
        NumberAnimation { to: 0.35; duration: 700; easing.type: Easing.InOutSine }
        NumberAnimation { to: 1; duration: 700; easing.type: Easing.InOutSine }
    }

    // ── Botón reutilizable (no referencia ids externos) ──────────────────────
    component OButton: Item {
        id: btn
        property string icon: ""
        property real iconSize: 22
        property color fillColor: "transparent"
        property color iconColor: "white"
        property color toggledColor: fillColor
        property color toggledIconColor: iconColor
        property bool toggled: false
        property real cornerRadius: height / 2
        property int nudge: 0
        property real glyphDx: 0
        readonly property bool hovered: mouse.containsMouse
        readonly property bool pressed: mouse.pressed
        signal clicked()

        opacity: enabled ? 1 : 0.38
        scale: pressed ? 0.9 : (hovered ? 1.05 : 1.0)
        Behavior on scale {
            enabled: Appearance.animationsEnabled
            NumberAnimation { duration: 260; easing.type: Easing.OutBack; easing.overshoot: 2.2 }
        }

        Rectangle {
            anchors.fill: parent
            radius: btn.cornerRadius
            color: btn.toggled ? btn.toggledColor : btn.fillColor
            Behavior on radius {
                enabled: Appearance.animationsEnabled
                NumberAnimation { duration: 320; easing.type: Easing.OutBack; easing.overshoot: 1.6 }
            }
            Behavior on color {
                enabled: Appearance.animationsEnabled
                ColorAnimation { duration: 200 }
            }
        }
        MaterialSymbol {
            id: glyph
            anchors.centerIn: parent
            text: btn.icon
            iconSize: btn.iconSize
            color: btn.toggled ? btn.toggledIconColor : btn.iconColor
            transform: Translate { x: btn.glyphDx }
        }
        onIconChanged: if (Appearance.animationsEnabled) swap.restart()
        ParallelAnimation {
            id: swap
            NumberAnimation { target: glyph; property: "scale"; from: 0.4; to: 1; duration: 300; easing.type: Easing.OutBack; easing.overshoot: 2 }
            NumberAnimation { target: glyph; property: "rotation"; from: -70; to: 0; duration: 300; easing.type: Easing.OutCubic }
        }
        SequentialAnimation {
            id: nudgeAnim
            ParallelAnimation {
                NumberAnimation { target: btn; property: "glyphDx"; to: btn.nudge * 14; duration: 110; easing.type: Easing.InQuad }
                NumberAnimation { target: glyph; property: "opacity"; to: 0; duration: 110 }
            }
            PropertyAction { target: btn; property: "glyphDx"; value: -btn.nudge * 14 }
            ParallelAnimation {
                NumberAnimation { target: btn; property: "glyphDx"; to: 0; duration: 240; easing.type: Easing.OutBack }
                NumberAnimation { target: glyph; property: "opacity"; to: 1; duration: 160 }
            }
        }
        MouseArea {
            id: mouse
            anchors.fill: parent
            hoverEnabled: true
            enabled: btn.enabled
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                if (btn.nudge !== 0 && Appearance.animationsEnabled) nudgeAnim.restart();
                btn.clicked();
            }
        }
    }

    // ═════════════════════════════════════════════════════════════════════════
    //  UI
    // ═════════════════════════════════════════════════════════════════════════
    StyledRectangularShadow {
        target: card
    }

    Rectangle {
        id: card
        anchors.fill: parent
        anchors.margins: Appearance.sizes.elevationMargin
        radius: root.cardRadius
        color: root.cardColor
        border.width: root.borderW
        border.color: root.colBorder
        clip: true

        // Resplandor ambiental que respira con la música
        Item {
            id: glow
            width: root.coverSize * 1.15
            height: width
            x: 22 + root.coverSize / 2 - width / 2
            y: card.height / 2 - height / 2
            scale: 1 + root.energy * 0.35
            layer.enabled: true
            layer.effect: MultiEffect {
                blurEnabled: true
                blur: 1.0
                blurMax: 64
            }
            Rectangle {
                anchors.centerIn: parent
                width: parent.width * 0.62
                height: width
                radius: width / 2
                color: root.artColor
                opacity: root.isDark ? (0.30 + root.energy * 0.5) : (0.22 + root.energy * 0.35)
            }
        }

        RowLayout {
            anchors.fill: parent
            anchors.margins: 22
            spacing: 26

            // ─────────────── IZQUIERDA · carátula + anillo ───────────────────
            Item {
                id: coverItem
                Layout.preferredWidth: root.coverSize
                Layout.preferredHeight: root.coverSize
                Layout.alignment: Qt.AlignVCenter

                property real swipeX: 0
                Behavior on swipeX {
                    enabled: !coverMouse.tracking && Appearance.animationsEnabled
                    NumberAnimation { duration: 420; easing.type: Easing.OutBack; easing.overshoot: 2 }
                }
                                readonly property bool showCenter: !root.scrubbing && (!root.playing || (root.coverHover && !coverMouse.ringHit))

                // Máscara viva (galleta). Se re-dibuja con el audio.
                Item {
                    id: maskItem
                    width: root.coverSize
                    height: root.coverSize
                    visible: false
                    layer.enabled: true
                    layer.samples: 4
                    Shape {
                        anchors.fill: parent
                        ShapePath {
                            fillColor: "white"
                            strokeColor: "transparent"
                            PathPolyline { path: root.maskPoints }
                        }
                    }
                }

                // Carátula recortada con la galleta
                Item {
                    id: artHolder
                    width: root.coverSize
                    height: root.coverSize
                    x: coverItem.swipeX
                    clip: true
                    scale: root.popScale
                        * (root.playing ? 1 : 0.93)
                        * ((root.coverHover && !coverMouse.ringHit) ? 1.03 : 1)
                        * ((coverMouse.pressed && !coverMouse.ringHit) ? 0.97 : 1)
                    Behavior on scale {
                        enabled: Appearance.animationsEnabled
                        NumberAnimation { duration: 380; easing.type: Easing.OutBack; easing.overshoot: 1.8 }
                    }
                    layer.enabled: true
                    layer.effect: MultiEffect {
                        maskEnabled: true
                        maskSource: maskItem
                        maskThresholdMin: 0.5
                        maskSpreadAtMin: 1.0
                    }

                    Rectangle {
                        anchors.fill: parent
                        color: root.colTonal
                    }
                    MaterialSymbol {
                        anchors.centerIn: parent
                        visible: coverImage.status !== Image.Ready
                        text: "music_note"
                        iconSize: 72
                        color: root.colSub
                    }
                    Image {
                        id: coverImage
                        // Miniaturas 16:9/4:3 con barras negras → un poco de zoom
                        readonly property real zoom: {
                            const w = implicitWidth, h = implicitHeight;
                            if (w <= 0 || h <= 0) return 1;
                            const ratio = w / h;
                            return (ratio > 1.2 || ratio < 0.83) ? 1.35 : 1;
                        }
                        anchors.centerIn: parent
                        width: root.coverSize * zoom
                        height: root.coverSize * zoom
                        source: root.artUrl
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        cache: true
                        smooth: true
                        sourceSize.width: 600
                        sourceSize.height: 600
                        opacity: status === Image.Ready ? 1 : 0
                        Behavior on opacity {
                            enabled: Appearance.animationsEnabled
                            NumberAnimation { duration: 300 }
                        }
                    }
                }

                // Anillo: progreso + rueda de scrubbing
                Shape {
                    anchors.fill: parent
                    layer.enabled: true
                    layer.samples: 4
                    ShapePath {
                        strokeColor: root.colTrack
                        strokeWidth: coverMouse.ringHit || root.scrubbing || (coverMouse.containsMouse && root.canSeek) ? 7 : 5
                        fillColor: "transparent"
                        capStyle: ShapePath.RoundCap
                        Behavior on strokeWidth {
                            enabled: Appearance.animationsEnabled
                            NumberAnimation { duration: 180 }
                        }
                        PathAngleArc {
                            centerX: root.coverSize / 2
                            centerY: root.coverSize / 2
                            radiusX: root.ringR
                            radiusY: root.ringR
                            startAngle: -90
                            sweepAngle: 359.9
                        }
                    }
                    ShapePath {
                        strokeColor: root.artColor
                        strokeWidth: coverMouse.ringHit || root.scrubbing || (coverMouse.containsMouse && root.canSeek) ? 7 : 5
                        fillColor: "transparent"
                        capStyle: ShapePath.RoundCap
                        PathAngleArc {
                            centerX: root.coverSize / 2
                            centerY: root.coverSize / 2
                            radiusX: root.ringR
                            radiusY: root.ringR
                            startAngle: -90
                            sweepAngle: Math.max(0.01, 359.9 * root.shownFrac)
                        }
                    }
                }

                // Tirador del anillo
                Rectangle {
                    readonly property real ang: (-90 + 360 * root.shownFrac) * Math.PI / 180
                    width: (root.scrubbing || coverMouse.ringHit) ? 20 : 12
                    height: width
                    radius: width / 2
                    x: root.coverSize / 2 + root.ringR * Math.cos(ang) - width / 2
                    y: root.coverSize / 2 + root.ringR * Math.sin(ang) - height / 2
                    color: root.artColor
                    border.width: 3
                    border.color: root.cardColor
                    visible: root.canSeek
                    Behavior on width {
                        enabled: Appearance.animationsEnabled
                        NumberAnimation { duration: 200; easing.type: Easing.OutBack; easing.overshoot: 2.5 }
                    }
                }

                // Pistas del swipe
                MaterialSymbol {
                    anchors.left: parent.left
                    anchors.leftMargin: 30
                    anchors.verticalCenter: parent.verticalCenter
                    text: "skip_previous"
                    iconSize: 34
                    color: root.artColor
                    opacity: root.clamp01(coverItem.swipeX / 50)
                }
                MaterialSymbol {
                    anchors.right: parent.right
                    anchors.rightMargin: 30
                    anchors.verticalCenter: parent.verticalCenter
                    text: "skip_next"
                    iconSize: 34
                    color: root.artColor
                    opacity: root.clamp01(-coverItem.swipeX / 50)
                }

                // Botón central: estado + acción
                Rectangle {
                    id: centerBtn
                    anchors.centerIn: parent
                    width: 68
                    height: 68
                    radius: root.playing ? 22 : 34
                    color: root.colBase
                    opacity: coverItem.showCenter ? 1 : 0
                    scale: coverItem.showCenter ? 1 : 0.55
                    Behavior on opacity {
                        enabled: Appearance.animationsEnabled
                        NumberAnimation { duration: 200 }
                    }
                    Behavior on scale {
                        enabled: Appearance.animationsEnabled
                        NumberAnimation { duration: 320; easing.type: Easing.OutBack; easing.overshoot: 2.2 }
                    }
                    Behavior on radius {
                        enabled: Appearance.animationsEnabled
                        NumberAnimation { duration: 320; easing.type: Easing.OutBack; easing.overshoot: 1.6 }
                    }
                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: root.playing ? "pause" : "play_arrow"
                        iconSize: 36
                        color: root.colOnBase
                    }
                }

                // Tiempo grande mientras se hace scrubbing
                Rectangle {
                    anchors.centerIn: parent
                    width: scrubText.implicitWidth + 28
                    height: 44
                    radius: 22
                    color: root.colBase
                    opacity: root.scrubbing ? 1 : 0
                    scale: root.scrubbing ? 1 : 0.7
                    Behavior on opacity {
                        enabled: Appearance.animationsEnabled
                        NumberAnimation { duration: 150 }
                    }
                    Behavior on scale {
                        enabled: Appearance.animationsEnabled
                        NumberAnimation { duration: 260; easing.type: Easing.OutBack; easing.overshoot: 2 }
                    }
                    StyledText {
                        id: scrubText
                        anchors.centerIn: parent
                        text: root.fmt(root.scrubFrac * root.length)
                        font.pixelSize: 22
                        font.weight: Font.DemiBold
                        color: root.colOnBase
                    }
                }

                // Indicador de volumen (rueda / slider)
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 34
                    width: hudRow.implicitWidth + 24
                    height: 34
                    radius: 17
                    color: root.colBase
                    opacity: root.hudShown ? 1 : 0
                    scale: root.hudShown ? 1 : 0.8
                    Behavior on opacity {
                        enabled: Appearance.animationsEnabled
                        NumberAnimation { duration: 160 }
                    }
                    Behavior on scale {
                        enabled: Appearance.animationsEnabled
                        NumberAnimation { duration: 240; easing.type: Easing.OutBack }
                    }
                    RowLayout {
                        id: hudRow
                        anchors.centerIn: parent
                        spacing: 6
                        MaterialSymbol {
                            text: root.volFrac < 0.01 ? "volume_off" : (root.volFrac < 0.5 ? "volume_down" : "volume_up")
                            iconSize: 18
                            color: root.colOnBase
                        }
                        StyledText {
                            text: Math.round(root.volFrac * 100) + "%"
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.DemiBold
                            color: root.colOnBase
                        }
                    }
                }

                // Interacción: clic, swipe, scrub
                MouseArea {
                    id: coverMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton
                    cursorShape: ringHit && root.canSeek ? Qt.PointingHandCursor : Qt.ArrowCursor

                    property bool ringHit: false
                    property bool tracking: false
                    property real pressX: 0
                    property real dragDx: 0
                    property real _lastF: 0

                    function _dist(mx, my) { return Math.hypot(mx - width / 2, my - height / 2); }
                    function _fracAt(mx, my) {
                        let f = (Math.atan2(my - height / 2, mx - width / 2) + Math.PI / 2) / (2 * Math.PI);
                        if (f < 0) f += 1;
                        // evita el salto 100% → 0% al cruzar la parte de arriba
                        if (_lastF > 0.75 && f < 0.25) f = 1;
                        else if (_lastF < 0.25 && f > 0.75) f = 0;
                        _lastF = f;
                        return f;
                    }
                    function _updateRing() {
                        ringHit = _dist(mouseX, mouseY) > root.ringR - 22;
                    }

                    onContainsMouseChanged: root.coverHover = containsMouse
                    onPositionChanged: (m) => {
                        if (!pressed) { _updateRing(); return; }
                        if (root.scrubbing) {
                            root.scrubFrac = _fracAt(m.x, m.y);
                        } else {
                            dragDx = m.x - pressX;
                            coverItem.swipeX = Math.max(-70, Math.min(70, dragDx * 0.55));
                        }
                    }
                    onPressed: (m) => {
                        tracking = true;
                        pressX = m.x;
                        dragDx = 0;
                        _updateRing();
                        if (ringHit && root.canSeek) {
                            _lastF = root.playFrac;
                            root.scrubFrac = _fracAt(m.x, m.y);
                            root.scrubbing = true;
                            root._hold = false;
                        }
                    }
                    onCanceled: {
                        tracking = false;
                        root.scrubbing = false;
                        coverItem.swipeX = 0;
                    }
                    onReleased: (m) => {
                        tracking = false;
                        if (root.scrubbing) {
                            root.seekFrac(root.scrubFrac);
                            root.scrubbing = false;
                            root._hold = true;
                            holdTimer.restart();
                        } else if (Math.abs(dragDx) > 56) {
                            if (dragDx < 0) root.player?.next();
                            else root.player?.previous();
                        } else if (Math.abs(dragDx) < 8 && !ringHit) {
                            root.player?.togglePlaying();
                        }
                        dragDx = 0;
                        coverItem.swipeX = 0;
                    }
                    onExited: ringHit = false
                }
            }

            // ─────────────── DERECHA · info + controles ──────────────────────
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 8

                // Fuente + EQ
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Rectangle {
                        radius: height / 2
                        color: root.colTonal
                        implicitHeight: 30
                        implicitWidth: chipRow.implicitWidth + 22
                        RowLayout {
                            id: chipRow
                            anchors.centerIn: parent
                            spacing: 7
                            Rectangle {
                                implicitWidth: 8
                                implicitHeight: 8
                                radius: 4
                                color: root.artColor
                                opacity: root.playing ? root._beat : 0.45
                            }
                            StyledText {
                                text: root.player?.identity ?? "Player"
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: root.colSub
                            }
                        }
                    }
                    Item { Layout.fillWidth: true }
                    OButton {
                        Layout.preferredWidth: 34
                        Layout.preferredHeight: 34
                        icon: "equalizer"
                        iconSize: 18
                        fillColor: root.colTonal
                        iconColor: root.colText
                        onClicked: root.eqRequested()
                    }
                }

                // Título + artista
                ColumnLayout {
                    id: textBlock
                    Layout.fillWidth: true
                    spacing: 2

                    transform: Translate { id: textShift }
                    ParallelAnimation {
                        id: textIn
                        NumberAnimation { target: textBlock; property: "opacity"; from: 0; to: 1; duration: 320 }
                        NumberAnimation { target: textShift; property: "y"; from: 10; to: 0; duration: 380; easing.type: Easing.OutCubic }
                    }

                    Item {
                        id: titleBox
                        Layout.fillWidth: true
                        implicitHeight: titleText.implicitHeight
                        clip: true
                        readonly property real overflow: Math.max(0, titleText.implicitWidth - width)

                        HoverHandler { id: titleHover }

                        StyledText {
                            id: titleText
                            text: root.title
                            font.pixelSize: 24
                            font.weight: Font.DemiBold
                            color: root.colText
                            wrapMode: Text.NoWrap
                        }
                        Rectangle {
                            anchors.right: parent.right
                            width: 32
                            height: parent.height
                            visible: titleBox.overflow > 0 && titleText.x === 0
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0; color: root.cardColorClear }
                                GradientStop { position: 1; color: root.cardColor }
                            }
                        }
                        SequentialAnimation {
                            running: titleHover.hovered && titleBox.overflow > 0
                            loops: Animation.Infinite
                            alwaysRunToEnd: true
                            NumberAnimation {
                                target: titleText
                                property: "x"
                                to: -titleBox.overflow - 6
                                duration: titleBox.overflow * 22 + 500
                                easing.type: Easing.InOutSine
                            }
                            PauseAnimation { duration: 500 }
                            NumberAnimation { target: titleText; property: "x"; to: 0; duration: 380; easing.type: Easing.InOutSine }
                        }
                    }
                    StyledText {
                        Layout.fillWidth: true
                        visible: text.length > 0
                        text: root.artist + (root.album.length > 0 && root.artist.length > 0 ? "  ·  " + root.album : root.album)
                        font.pixelSize: Appearance.font.pixelSize.normal
                        color: root.artColor
                        elide: Text.ElideRight
                    }
                }

                Item { Layout.fillHeight: true }

                // Tiempo
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    StyledText {
                        text: root.fmt(root.shownPos)
                        font.pixelSize: 30
                        font.weight: Font.DemiBold
                        color: root.scrubbing ? root.artColor : root.colText
                        Behavior on color {
                            enabled: Appearance.animationsEnabled
                            ColorAnimation { duration: 150 }
                        }
                    }
                    StyledText {
                        Layout.alignment: Qt.AlignBottom
                        Layout.bottomMargin: 4
                        text: "/ " + root.fmt(root.length)
                        font.pixelSize: Appearance.font.pixelSize.normal
                        color: root.colSub
                    }
                }

                // Controles
                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 8

                    OButton {
                        Layout.preferredWidth: 38
                        Layout.preferredHeight: 38
                        enabled: root.player?.shuffleSupported ?? false
                        icon: "shuffle"
                        iconSize: 19
                        fillColor: "transparent"
                        iconColor: root.colSub
                        toggled: root.player?.shuffle ?? false
                        toggledColor: root.alpha(root.artColor, 0.22)
                        toggledIconColor: root.artColor
                        onClicked: if (root.player) root.player.shuffle = !root.player.shuffle
                    }
                    OButton {
                        Layout.preferredWidth: 46
                        Layout.preferredHeight: 46
                        enabled: root.player?.canGoPrevious ?? false
                        icon: "skip_previous"
                        iconSize: 24
                        nudge: -1
                        fillColor: root.colTonal
                        iconColor: root.colText
                        onClicked: root.player?.previous()
                    }
                    OButton {
                        Layout.preferredWidth: 76
                        Layout.preferredHeight: 54
                        enabled: root.player?.canTogglePlaying ?? true
                        icon: root.playing ? "pause" : "play_arrow"
                        iconSize: 32
                        cornerRadius: root.playing ? 18 : height / 2
                        fillColor: root.colBase
                        iconColor: root.colOnBase
                        onClicked: root.player?.togglePlaying()
                    }
                    OButton {
                        Layout.preferredWidth: 46
                        Layout.preferredHeight: 46
                        enabled: root.player?.canGoNext ?? false
                        icon: "skip_next"
                        iconSize: 24
                        nudge: 1
                        fillColor: root.colTonal
                        iconColor: root.colText
                        onClicked: root.player?.next()
                    }
                    OButton {
                        Layout.preferredWidth: 38
                        Layout.preferredHeight: 38
                        enabled: root.player?.loopSupported ?? false
                        icon: root.player?.loopState === MprisLoopState.Track ? "repeat_one" : "repeat"
                        iconSize: 19
                        fillColor: "transparent"
                        iconColor: root.colSub
                        toggled: (root.player?.loopState ?? MprisLoopState.None) !== MprisLoopState.None
                        toggledColor: root.alpha(root.artColor, 0.22)
                        toggledIconColor: root.artColor
                        onClicked: root.cycleLoop()
                    }
                }

                // Volumen
                RowLayout {
                    Layout.fillWidth: true
                    visible: root.volSupported
                    spacing: 6

                    OButton {
                        Layout.preferredWidth: 28
                        Layout.preferredHeight: 28
                        icon: root.volFrac < 0.01 ? "volume_off" : (root.volFrac < 0.5 ? "volume_down" : "volume_up")
                        iconSize: 18
                        fillColor: "transparent"
                        iconColor: root.colSub
                        onClicked: root.toggleMute()
                    }
                    Item {
                        id: volSlider
                        Layout.fillWidth: true
                        implicitHeight: 26
                        readonly property real fillW: Math.max(0, root.volFrac * (width - 10))

                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width
                            height: 10
                            radius: 5
                            color: root.colTrack
                        }
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: volSlider.fillW + 3
                            height: 10
                            radius: 5
                            color: root.artColor
                        }
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            x: volSlider.fillW + 6
                            width: 4
                            height: volMouse.pressed ? 24 : 20
                            radius: 2
                            color: root.artColor
                            Behavior on height {
                                enabled: Appearance.animationsEnabled
                                NumberAnimation { duration: 150; easing.type: Easing.OutBack }
                            }
                        }
                        MouseArea {
                            id: volMouse
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            function _set(mx) {
                                root.volDrag = root.clamp01((mx - 5) / (width - 10));
                                root.setVol(root.volDrag);
                            }
                            onPressed: (m) => _set(m.x)
                            onPositionChanged: (m) => { if (pressed) _set(m.x); }
                            onReleased: root.volDrag = -1
                        }
                    }
                }
            }
        }
    }
}
