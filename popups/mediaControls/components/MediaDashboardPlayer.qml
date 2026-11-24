pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects as GE
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import Quickshell.Services.Mpris
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.common.models
import qs.modules.shared.mediaControls.components
import qs.services
import qs.services.deferred

/**
 * MediaDashboardPlayer — "Orbital Console" (layout 16:9)
 *
 *  IZQUIERDA : portada con anillo de espectro/progreso, título, artista, histograma,
 *              barra de progreso, controles y caja de LETRAS (4 líneas, la actual resaltada).
 *  CENTRO    : tu avatar, tu nombre, puntos de CPU, tabla de sistema y planeta con órbita.
 *  DERECHA   : reloj, fecha, clima, onda, COLA DE REPRODUCCIÓN y 4 medidores (CPU/GPU/RAM/DISCO).
 *
 *  Todo se dibuja sobre una base de 1672x941 y se escala solo al tamaño que dé el host.
 */
Item {
    id: root
    required property MprisPlayer player
    property list<real> visualizerPoints: []
    property real normalizationCeiling: 100
    property string outputName: ""
    property real radius: Appearance.rounding.normal
    property bool motion: true
    property bool cyber: true
    property real consoleOpacity: 0.0
    property real webIntensity: 0.85
    property bool cornerBrackets: false
    readonly property bool panelActive: root.visible && (root.QsWindow?.window?.visible ?? false)
    signal eqRequested()

    // ── Size: base 1672x941 (16:9). Cambia sizeBoost para hacer la ventana más grande/pequeña ──
    property real sizeBoost: 0.68
    readonly property real _baseW: 1672
    readonly property real _baseH: 941
    implicitWidth: Math.round(root._baseW * root.sizeBoost + Appearance.sizes.elevationMargin)
    implicitHeight: Math.round(root._baseH * root.sizeBoost + Appearance.sizes.elevationMargin)

    // ── Theme tokens ─────────────────────────────────────────────
    readonly property bool _inir: Appearance.inirEverywhere && Appearance.inir
    readonly property color colPrimary: root._inir ? Appearance.inir.colPrimary : Appearance.colors.colPrimary
    readonly property color colAccent2: Qt.lighter(root.colPrimary, 1.12)
    readonly property color colCore: ColorUtils.mix("#ffffff", root.colAccent2, 0.7)
    readonly property bool _angel: Appearance.angelEverywhere
    readonly property bool _regalia: Appearance.regaliaEverywhere
    readonly property color colSurface: root._regalia ? Appearance.regalia.bg2
        : root._angel ? Appearance.angel.colGlassPopup
        : root._inir ? Appearance.inir.colLayer2
        : Appearance.colors.colSurfaceContainer
    readonly property color colText: root._angel ? Appearance.angel.colText
        : root._inir ? Appearance.inir.colText : Appearance.colors.colOnLayer1
    readonly property color colTextSecondary: ColorUtils.applyAlpha(root.colText, 0.68)
    readonly property color colOnPrimary: Appearance.colors.colOnPrimary

    // ── Player ───────────────────────────────────────────────────
    PlayerBase {
        id: playerBase
        player: root.player
        positionUpdatesActive: root.motion && root.panelActive
    }
    readonly property bool _playing: playerBase.effectiveIsPlaying
    readonly property real _len: playerBase.effectiveLength
    readonly property real _pos: playerBase.effectivePosition
    readonly property string _title: StringUtils.cleanMusicTitle(playerBase.effectiveTitle) || playerBase.effectiveTitle || "—"

    // ── Engine state ─────────────────────────────────────────────
    property real _t: 0
    property int _frame: 0
    property real _enter: 1
    property real _flash: 0
    property real _bass: 0
    property real _mid: 0
    property real _high: 0
    property real _bassAvg: 0.12
    property int _bassCool: 0
    property real _peakRef: 20
    property real _mx: 0
    property real _my: 0
    property var _smooth: new Array(64).fill(0.05)
    property var _disp: new Array(64).fill(0.08)
    property var _peaks: new Array(64).fill(0.12)
    property bool _shuffleOn: false
    property bool _repeatOn: false
    property bool _repeatCool: false
    property bool _volShown: false
    property string _lastTitle: ""

    function _burst(): void {
        root._flash = 1;
    }

    function _tick(): void {
        const pts = root.visualizerPoints;
        const M = 64;
        const ceil = root.normalizationCeiling > 0 ? root.normalizationCeiling : 100;
        root._t += 0.042;
        root._frame++;
        root._flash *= 0.88;

        const sm = root._smooth.slice(), disp = root._disp.slice(), peaks = root._peaks.slice();
        const has = pts && pts.length > 1;
        const playing = root._playing;
        let framePeak = 0;
        for (let i = 0; i < M; i++) {
            let v = 0;
            if (has) {
                const x = i / (M - 1) * (pts.length - 1);
                const i0 = Math.floor(x), i1 = Math.min(pts.length - 1, i0 + 1), f = x - i0;
                v = Math.max(0, (pts[i0] ?? 0) * (1 - f) + (pts[i1] ?? 0) * f);
            }
            sm[i] = v > sm[i] ? sm[i] + (v - sm[i]) * 0.68 : sm[i] * 0.84;
            framePeak = Math.max(framePeak, sm[i]);
        }
        root._peakRef = Math.max(framePeak, root._peakRef * 0.992, ceil * 0.005, 0.01);
        let bs = 0, ms = 0, hs = 0;
        for (let i = 0; i < M; i++) {
            const n = Math.min(1, sm[i] / root._peakRef);
            const idle = playing ? (0.07 + 0.04 * Math.sin(root._t * 2.2 + i * 0.45)) : (0.04 + 0.015 * Math.sin(root._t * 1.2 + i * 0.4));
            disp[i] = Math.max(n, idle);
            if (disp[i] >= peaks[i])
                peaks[i] = Math.min(1, disp[i] + 0.03);
            else
                peaks[i] = Math.max(disp[i], peaks[i] - 0.012);
            if (i < 8)
                bs += disp[i];
            else if (i < 30)
                ms += disp[i];
            else
                hs += disp[i];
        }
        root._smooth = sm;
        root._disp = disp;
        root._peaks = peaks;

        const bassNow = bs / 8, midNow = ms / 22, highNow = hs / 34;
        root._bass += (bassNow - root._bass) * (bassNow > root._bass ? 0.65 : 0.15);
        root._mid += (midNow - root._mid) * (midNow > root._mid ? 0.55 : 0.15);
        root._high += (highNow - root._high) * (highNow > root._high ? 0.65 : 0.18);
        if (root._bassCool > 0)
            root._bassCool--;
        if (playing && has && bassNow > 0.28 && bassNow > root._bassAvg * 1.18 && root._bassCool === 0) {
            root._flash = Math.max(root._flash, Math.min(1, (bassNow - root._bassAvg) * 2.4 + bassNow * 0.5));
            root._bassCool = 6;
        }
        root._bassAvg += (bassNow - root._bassAvg) * 0.08;

        // smooth mouse parallax
        const tx = stageHover.hovered ? (stageHover.point.position.x / Math.max(1, stage.width) - 0.5) * 2 : 0;
        const ty = stageHover.hovered ? (stageHover.point.position.y / Math.max(1, stage.height) - 0.5) * 2 : 0;
        root._mx += (tx - root._mx) * 0.08;
        root._my += (ty - root._my) * 0.08;

        // karaoke fill + repeat-one
        root._lyFrac = root._computeLyFrac();
        if (root._repeatOn && !root._repeatCool && root._len > 2 && root._pos >= root._len - 0.5) {
            root._repeatCool = true;
            repeatCoolTimer.restart();
            playerBase.seek(0);
        }

        // queue refresh when the track changes
        if (root._frame % 15 === 0 && playerBase.effectiveTitle !== root._lastTitle) {
            root._lastTitle = playerBase.effectiveTitle;
            queueTimer.restart();
        }

        ringCv.requestPaint();
        specCv.requestPaint();
        clockWaveCv.requestPaint();
        if (root._frame % 2 === 0)
            planetCv.requestPaint();
    }

    Timer {
        id: frameTimer
        interval: 34
        repeat: true
        running: root.visible
        triggeredOnStart: true
        onTriggered: root._tick()
    }
    Timer {
        id: repeatCoolTimer
        interval: 2500
        onTriggered: root._repeatCool = false
    }
    Timer {
        id: volTimer
        interval: 1300
        onTriggered: root._volShown = false
    }

    NumberAnimation {
        id: enterAnim
        target: root
        property: "_enter"
        from: 0
        to: 1
        duration: 420
        easing.type: Easing.OutCubic
    }

    ResourceUsageMonitor {
        active: true
        target: root
    }

    // ── Clock ────────────────────────────────────────────────────
    property date _now: new Date()
    Timer {
        interval: 1000
        repeat: true
        running: root.visible
        triggeredOnStart: true
        onTriggered: root._now = new Date()
    }
    readonly property string _clockHM: {
        const h = root._now.getHours() % 12 || 12, m = root._now.getMinutes();
        return (h < 10 ? "0" + h : "" + h) + ":" + (m < 10 ? "0" + m : "" + m);
    }
    readonly property string _clockAP: root._now.getHours() >= 12 ? "PM" : "AM"
    readonly property string _dateStr: {
        const d = ["Dom", "Lun", "Mar", "Mié", "Jue", "Vie", "Sáb"];
        const m = ["Enero", "Febrero", "Marzo", "Abril", "Mayo", "Junio", "Julio", "Agosto", "Septiembre", "Octubre", "Noviembre", "Diciembre"];
        return d[root._now.getDay()] + ", " + root._now.getDate() + " " + m[root._now.getMonth()] + " " + root._now.getFullYear();
    }

    // ── Weather (wttr.in, located by IP) ──
    property string _wTemp: "—"
    property string _wDesc: ""
    property string _wIcon: "cloud"
    function _wIconFor(code): string {
        if (code === 113)
            return "sunny";
        if (code === 116)
            return "partly_cloudy_day";
        if (code === 119 || code === 122)
            return "cloud";
        if ([143, 248, 260].includes(code))
            return "foggy";
        if ([200, 386, 389, 392, 395].includes(code))
            return "thunderstorm";
        if ([179, 227, 230, 323, 326, 329, 332, 335, 338, 368, 371, 350, 374, 377].includes(code))
            return "weather_snowy";
        return "rainy";
    }
    function _fetchWeather(): void {
        const xhr = new XMLHttpRequest();
        xhr.onreadystatechange = function () {
            if (xhr.readyState !== XMLHttpRequest.DONE || xhr.status !== 200)
                return;
            try {
                const c = JSON.parse(xhr.responseText).current_condition[0];
                root._wTemp = c.temp_C + "°C";
                root._wDesc = c.weatherDesc[0].value;
                root._wIcon = root._wIconFor(parseInt(c.weatherCode));
            } catch (e) {}
        };
        xhr.open("GET", "https://wttr.in/?format=j1");
        xhr.send();
    }
    Timer {
        interval: 1200000
        repeat: true
        running: root.visible
        triggeredOnStart: true
        onTriggered: root._fetchWeather()
    }

    // ── Identity (name + avatar come from your user) ─────────────
    property string _gecosName: ""
    Process {
        command: ["bash", "-c", "getent passwd \"$(id -u)\" | cut -d: -f5 | cut -d, -f1"]
        stdout: SplitParser {
            onRead: line => {
                const t = line.trim();
                if (t.length > 0)
                    root._gecosName = t;
            }
        }
        Component.onCompleted: running = true
    }
    readonly property string _fullName: {
        const dn = String(SystemInfo.displayName ?? "").trim();
        return dn.length > 0 ? dn : root._gecosName;
    }
    readonly property string _bigName: {
        const n = root._fullName;
        if (n.length > 0)
            return n.split(/\s+/)[0].toUpperCase();
        return (Quickshell.env("USER") ?? "").toUpperCase() || "OPERATOR";
    }

    // ── System info ──────────────────────────────────────────────
    property var systemDetails: ({})
    Process {
        running: true
        command: ["python3", Quickshell.env("HOME") + "/.local/bin/inir-panel-system-info.py"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.systemDetails = JSON.parse(text); } catch (e) {}
            }
        }
    }
    readonly property string _distroName: String(SystemInfo.distroName ?? "").trim() || "Linux"
    property real _uptimeSeconds: 0
    readonly property string _uptimeHms: {
        const s = Math.floor(root._uptimeSeconds);
        if (s <= 0)
            return "--:--";
        const d = Math.floor(s / 86400), h = Math.floor((s % 86400) / 3600), m = Math.floor((s % 3600) / 60), sec = s % 60;
        const p = v => (v < 10 ? "0" + v : "" + v);
        return d > 0 ? d + "d " + p(h) + ":" + p(m) : p(h) + ":" + p(m) + ":" + p(sec);
    }
    Process {
        id: uptimeProc
        command: ["cat", "/proc/uptime"]
        stdout: SplitParser {
            onRead: line => root._uptimeSeconds = parseFloat(line.split(" ")[0]) || 0
        }
    }
    Timer {
        interval: 15000
        repeat: true
        running: root.visible
        triggeredOnStart: true
        onTriggered: uptimeProc.running = true
    }

    // ── Extra data for the gauges (CPU GHz, GPU name, disk) ──────
    property string _cpuGhz: ""
    Process {
        id: freqProc
        command: ["bash", "-c", "awk '/MHz/{s+=$4;n++}END{if(n)printf \"%.1f GHz\", s/n/1000}' /proc/cpuinfo"]
        stdout: SplitParser {
            onRead: line => {
                const t = line.trim();
                if (t.length > 0)
                    root._cpuGhz = t;
            }
        }
    }
    Timer {
        interval: 4000
        repeat: true
        running: root.visible
        triggeredOnStart: true
        onTriggered: freqProc.running = true
    }
    property string _gpuName: ""
    Process {
        running: true
        command: ["bash", "-c", "lspci 2>/dev/null | grep -iE 'vga|3d|display' | tail -n1 | sed -E 's/.*\\[([^]]+)\\][^[]*$/\\1/; s/GeForce //; s/Radeon //'"]
        stdout: SplitParser {
            onRead: line => {
                const t = line.trim();
                if (t.length > 0 && t.length < 40)
                    root._gpuName = t;
            }
        }
    }
    readonly property string _gpuLabel: String(root.systemDetails.gpu || root._gpuName || "GPU")
    readonly property string _ramText: (ResourceUsage.memoryUsed / 1048576).toFixed(1) + " / " + (ResourceUsage.memoryTotal / 1048576).toFixed(1) + " GiB"
    readonly property string _diskText: {
        const u = Number(ResourceUsage.diskUsed), t = Number(ResourceUsage.diskTotal);
        if (!(u > 0) || !(t > 0))
            return "";
        return (u / 1048576).toFixed(0) + " / " + (t / 1048576).toFixed(0) + " GiB";
    }

    // ── System audio ─────────────────────────────────────────────
    readonly property real _vol: Math.max(0, Math.min(1, Audio.value ?? 0))
    readonly property bool _muted: Audio.sink?.audio?.muted ?? false
    function _setVol(v): void {
        Audio.setSinkVolume(Math.max(0, Math.min(1, v)));
        root._volShown = true;
        volTimer.restart();
    }

    // ── Lyrics (LyricsService of the shell) ──────────────────────
    property bool _lyricsSubscribed: false
    readonly property bool _lyricsActive: LyricsService.status === "ok" && (LyricsService.lyricsLines?.length ?? 0) > 0
    function _lyricAt(offset): string {
        const lines = LyricsService.lyricsLines;
        const idx = LyricsService.activeIndex + offset;
        if (!lines || idx < 0 || idx >= lines.length)
            return "";
        return String(lines[idx]?.text ?? "");
    }
    property real _lyFrac: 0
    property real _lyChangedAt: 0
    function _lyTime(i): real {
        const L = LyricsService.lyricsLines;
        if (!L || i < 0 || i >= L.length)
            return -1;
        const o = L[i];
        let t = o?.time ?? o?.t ?? o?.start ?? o?.startTime ?? o?.timestamp ?? o?.position;
        if (t === undefined || t === null)
            return -1;
        t = Number(t);
        if (isNaN(t))
            return -1;
        return (root._len > 0 && t > root._len * 2) ? t / 1000 : t;
    }
    function _computeLyFrac(): real {
        if (!root._lyricsActive)
            return 0;
        const i = LyricsService.activeIndex;
        if (i < 0)
            return 0;
        const t0 = root._lyTime(i), t1 = root._lyTime(i + 1);
        let f;
        if (t0 >= 0 && t1 > t0)
            f = (root._pos - t0) / (Math.min(t1 - t0, 7) * 0.9);
        else
            f = ((Date.now() - root._lyChangedAt) / 1000) / Math.max(1.2, Math.min(6, root._lyricAt(0).length * 0.08));
        return Math.max(0, Math.min(1, f));
    }
    Connections {
        target: LyricsService
        function onActiveIndexChanged() { root._lyChangedAt = Date.now(); }
    }
    readonly property string _lyricsPlaceholder: {
        if (LyricsService.status === "loading" || LyricsService.status === "idle")
            return Translation.tr("Looking for lyrics") + "…";
        if (LyricsService.status === "offline")
            return Translation.tr("Lyrics need an internet connection");
        return Translation.tr("No synced lyrics for this track");
    }
    function _syncLyricsSubscription(): void {
        const should = root.visible;
        if (should === root._lyricsSubscribed)
            return;
        root._lyricsSubscribed = should;
        if (should)
            LyricsService.subscribe();
        else
            LyricsService.unsubscribe();
    }
    onVisibleChanged: {
        root._syncLyricsSubscription();
        if (root.visible && Appearance.animationsEnabled) {
            root._enter = 0;
            enterAnim.restart();
        }
        if (root.visible)
            queueTimer.restart();
    }
    Component.onCompleted: {
        root._syncLyricsSubscription();
        Qt.callLater(() => root._tick());
        queueTimer.restart();
    }
    Component.onDestruction: {
        if (root._lyricsSubscribed) {
            root._lyricsSubscribed = false;
            LyricsService.unsubscribe();
        }
    }

    // ── Queue (YtMusic queue + upcoming playlist) ────────────────
    property var _queue: []
    function _fmtDur(d): string {
        if (d === undefined || d === null || d === "")
            return "";
        if (typeof d === "number")
            return d > 0 ? StringUtils.friendlyTimeForSeconds(d) : "";
        return String(d);
    }
    function _qItem(t, source, i): var {
        return {
            title: String(t.title ?? ""),
            artist: String(t.artist ?? ""),
            art: String(t.thumbnail || YtMusic._getThumbnailUrl(t.videoId)),
            dur: root._fmtDur(t.duration ?? t.length ?? t.durationSeconds ?? t.lengthSeconds),
            current: false,
            ytSource: source,
            ytIndex: i
        };
    }
    function _buildQueue(): void {
        const out = [{
            title: root._title,
            artist: playerBase.effectiveArtist,
            art: playerBase.displayedArtFilePath,
            dur: StringUtils.friendlyTimeForSeconds(root._len),
            current: true,
            ytSource: "",
            ytIndex: -1
        }];
        try {
            const q = YtMusic.queue ?? [];
            for (let i = 0; i < q.length && out.length < 16; i++)
                out.push(root._qItem(q[i], "queue", i));
            const pl = YtMusic.activePlaylist ?? [];
            if (pl.length > 0 && YtMusic.currentIndex >= 0) {
                for (let i = YtMusic.currentIndex + 1; i < pl.length && out.length < 16; i++)
                    out.push(root._qItem(pl[i], "playlist", i));
            }
        } catch (e) {}
        root._queue = out;
    }
    Timer {
        id: queueTimer
        interval: 350
        onTriggered: root._buildQueue()
    }
    Connections {
        target: YtMusic
        function onQueueChanged() { queueTimer.restart(); }
        function onActivePlaylistChanged() { queueTimer.restart(); }
        function onCurrentIndexChanged() { queueTimer.restart(); }
        function onCurrentVideoIdChanged() { queueTimer.restart(); }
    }
    function _playQueueItem(it): void {
        if (it.current) {
            playerBase.togglePlaying();
            return;
        }
        if (it.ytSource === "queue")
            YtMusic.playFromQueue(it.ytIndex);
        else if (it.ytSource === "playlist")
            YtMusic.playFromPlaylist(YtMusic.activePlaylist, it.ytIndex, YtMusic.activePlaylistSource);
        root._burst();
    }
    function _goNext(): void {
        if (root._shuffleOn && root._queue.length > 1) {
            const i = 1 + Math.floor(Math.random() * (root._queue.length - 1));
            root._playQueueItem(root._queue[i]);
        } else {
            playerBase.next();
        }
        root._burst();
    }

    // ═══════════════════════════ CARD ═══════════════════════════
    StyledRectangularShadow {
        target: card
        visible: Appearance.angelEverywhere || (!Appearance.inirEverywhere && !Appearance.auroraEverywhere)
    }

    Rectangle {
        id: card
        anchors.centerIn: parent
        width: parent.width - Appearance.sizes.elevationMargin
        height: parent.height - Appearance.sizes.elevationMargin
        radius: root.radius
        color: ColorUtils.applyAlpha(root.colSurface, root.consoleOpacity)
        border.width: 0
        border.color: ColorUtils.applyAlpha(root.colPrimary, 0.30 + root._flash * 0.5)
        clip: true
        opacity: root._enter

        // Reflejo suave sobre el blur nativo, sin borde ni franja inferior.
        Rectangle {
            anchors.fill: parent
            radius: card.radius
            gradient: Gradient {
                GradientStop { position: 0; color: "transparent" }
                GradientStop { position: 0.38; color: "transparent" }
                GradientStop { position: 1; color: "transparent" }
            }
        }

        // The stage is scaled uniformly so nothing is ever cut, whatever size the host gives.
        Item {
            id: stage
            readonly property real k: Math.max(0.3, Math.min(2.6, card.width / root._baseW, card.height / root._baseH))
            width: root._baseW
            height: root._baseH
            x: (card.width - width * stage.k) / 2
            y: (card.height - height * stage.k) / 2
            scale: stage.k
            transformOrigin: Item.TopLeft

            HoverHandler {
                id: stageHover
            }

            // ── soft green glow blobs (background) ──
            Canvas {
                id: bgCv
                anchors.fill: parent
                property color c1: root.colPrimary
                onC1Changed: requestPaint()
                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()
                Component.onCompleted: requestPaint()
                onPaint: {
                    const ctx = getContext("2d");
                    ctx.reset();
                    const w = width, h = height;
                    const blobs = [
                        { x: 0.10, y: 0.22, r: 330, a: 0.13 },
                        { x: 0.52, y: 0.30, r: 360, a: 0.10 },
                        { x: 0.30, y: 0.80, r: 300, a: 0.08 },
                        { x: 0.90, y: 0.20, r: 300, a: 0.09 },
                        { x: 0.82, y: 0.85, r: 340, a: 0.10 }
                    ];
                    for (const b of blobs) {
                        const g = ctx.createRadialGradient(b.x * w, b.y * h, 0, b.x * w, b.y * h, b.r);
                        g.addColorStop(0, ColorUtils.applyAlpha(c1, b.a));
                        g.addColorStop(1, ColorUtils.applyAlpha(c1, 0));
                        ctx.fillStyle = g;
                        ctx.fillRect(0, 0, w, h);
                    }
                }
            }

            Item {
                id: content
                width: stage.width
                height: root._baseH
                y: (stage.height - height) / 2

                // ── corner brackets ──
                Canvas {
                    id: bracketsCv
                    anchors.fill: parent
                    visible: root.cornerBrackets
                    property color c1: root.colAccent2
                    onC1Changed: requestPaint()
                    onWidthChanged: requestPaint()
                    Component.onCompleted: requestPaint()
                    onPaint: {
                        const ctx = getContext("2d");
                        ctx.reset();
                        const w = width, h = height, L = 16, m = 33, t = 34, b = h - 34;
                        ctx.strokeStyle = c1;
                        ctx.lineWidth = 1.5;
                        ctx.globalAlpha = 0.7;
                        ctx.beginPath();
                        ctx.moveTo(m, t + L); ctx.lineTo(m, t); ctx.lineTo(m + L, t);
                        ctx.moveTo(w - m - L, t); ctx.lineTo(w - m, t); ctx.lineTo(w - m, t + L);
                        ctx.moveTo(m, b - L); ctx.lineTo(m, b); ctx.lineTo(m + L, b);
                        ctx.moveTo(w - m - L, b); ctx.lineTo(w - m, b); ctx.lineTo(w - m, b - L);
                        ctx.stroke();
                    }
                }

                // ── column dividers ──
                Rectangle {
                    x: 597
                    y: 40
                    width: 1.5
                    height: 840
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: ColorUtils.applyAlpha(root.colPrimary, 0) }
                        GradientStop { position: 0.2; color: ColorUtils.applyAlpha(root.colPrimary, 0.45) }
                        GradientStop { position: 0.8; color: ColorUtils.applyAlpha(root.colPrimary, 0.45) }
                        GradientStop { position: 1.0; color: ColorUtils.applyAlpha(root.colPrimary, 0) }
                    }
                }
                Rectangle {
                    x: content.width - 602
                    y: 40
                    width: 1.5
                    height: 840
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: ColorUtils.applyAlpha(root.colPrimary, 0) }
                        GradientStop { position: 0.2; color: ColorUtils.applyAlpha(root.colPrimary, 0.45) }
                        GradientStop { position: 0.8; color: ColorUtils.applyAlpha(root.colPrimary, 0.45) }
                        GradientStop { position: 1.0; color: ColorUtils.applyAlpha(root.colPrimary, 0) }
                    }
                }

                // ═══════════════════ LEFT: MUSIC ═══════════════════
                Item {
                    id: leftZone
                    x: 0
                    width: 600
                    height: root._baseH

                    // cover + spectrum ring that doubles as the progress bar
                    Item {
                        id: ringBox
                        x: 45
                        y: 70
                        width: 230
                        height: 230
                        scale: 1 + root._bass * 0.02

                        Canvas {
                            id: ringCv
                            anchors.fill: parent
                            onPaint: {
                                const ctx = getContext("2d");
                                ctx.reset();
                                const c = width / 2, N = 96, TAU = Math.PI * 2, R0 = 84;
                                const prog = root._len > 0 ? Math.max(0, Math.min(1, root._pos / root._len)) : 0;
                                ctx.lineCap = "round";
                                for (let i = 0; i < N; i++) {
                                    const a = -Math.PI / 2 + i / N * TAU;
                                    const j = i < N / 2 ? i : N - 1 - i;
                                    const band = Math.min(63, Math.floor(j / (N / 2) * 44));
                                    const v = root._disp[band] ?? 0.08;
                                    const L = 5 + v * 20;
                                    const passed = (i + 0.5) / N <= prog;
                                    ctx.strokeStyle = passed ? root.colAccent2 : ColorUtils.applyAlpha(root.colPrimary, 0.5);
                                    ctx.globalAlpha = passed ? 0.95 : 0.6;
                                    ctx.lineWidth = (i % 5 === 0) ? 3.5 : 2.4;
                                    ctx.beginPath();
                                    ctx.moveTo(c + Math.cos(a) * R0, c + Math.sin(a) * R0);
                                    ctx.lineTo(c + Math.cos(a) * (R0 + L), c + Math.sin(a) * (R0 + L));
                                    ctx.stroke();
                                }
                                // top marker
                                ctx.globalAlpha = 1;
                                ctx.strokeStyle = root.colCore;
                                ctx.lineWidth = 3.5;
                                ctx.beginPath();
                                ctx.moveTo(c, c - R0 - 28);
                                ctx.lineTo(c, c - R0 - 6);
                                ctx.stroke();
                            }
                        }
                        Rectangle {
                            id: coverDisc
                            anchors.centerIn: parent
                            width: 152
                            height: 152
                            radius: 76
                            color: ColorUtils.mix("#0d0d11", playerBase.artDominantColor, 0.35)
                            border.width: 4
                            border.color: ColorUtils.applyAlpha(root.colAccent2, 0.95)
                            Image {
                                id: coverImg
                                anchors.fill: parent
                                anchors.margins: 5
                                source: playerBase.displayedArtFilePath
                                fillMode: Image.PreserveAspectCrop
                                smooth: true
                                mipmap: true
                                asynchronous: true
                                visible: source !== "" && status === Image.Ready
                                layer.enabled: true
                                layer.effect: GE.OpacityMask {
                                    maskSource: Rectangle {
                                        width: coverImg.width
                                        height: coverImg.height
                                        radius: Math.min(coverImg.width, coverImg.height) / 2
                                    }
                                }
                            }
                            Rectangle {
                                anchors.fill: parent
                                radius: width / 2
                                color: ColorUtils.applyAlpha("#000000", 0.45)
                                opacity: coverMouse.containsMouse ? 1 : 0
                                Behavior on opacity {
                                    enabled: Appearance.animationsEnabled
                                    NumberAnimation { duration: 140 }
                                }
                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: root._playing ? "pause" : "play_arrow"
                                    iconSize: 54
                                    fill: 1
                                    color: "#ffffff"
                                }
                            }
                        }
                        MouseArea {
                            id: coverMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            cursorShape: Qt.PointingHandCursor
                            onClicked: mouse => {
                                if (mouse.button === Qt.RightButton)
                                    Audio.toggleMute();
                                else
                                    playerBase.togglePlaying();
                                root._burst();
                            }
                            onWheel: wheel => root._setVol(root._vol + (wheel.angleDelta.y > 0 ? 0.05 : -0.05))
                        }
                        // volume flash
                        Rectangle {
                            x: (parent.width - width) / 2
                            y: parent.height - 14
                            width: volRow.implicitWidth + 18
                            height: 24
                            radius: 12
                            color: ColorUtils.applyAlpha(root.colSurface, 0.92)
                            border.width: 1
                            border.color: ColorUtils.applyAlpha(root.colPrimary, 0.5)
                            opacity: root._volShown ? 1 : 0
                            visible: opacity > 0.01
                            Behavior on opacity {
                                enabled: Appearance.animationsEnabled
                                NumberAnimation { duration: 180 }
                            }
                            Row {
                                id: volRow
                                anchors.centerIn: parent
                                spacing: 5
                                MaterialSymbol {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: (root._muted || root._vol < 0.01) ? "volume_off" : "volume_up"
                                    iconSize: 15
                                    fill: 1
                                    color: root.colAccent2
                                }
                                StyledText {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: Math.round(root._vol * 100) + "%"
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    renderType: Text.QtRendering
                                    font.family: Appearance.font.family.numbers
                                    color: root.colText
                                }
                            }
                        }
                    }

                    // header + title / artist
                    Column {
                        x: 276
                        y: 94
                        width: 290
                        spacing: 10
                        Item {
                            width: parent.width
                            height: 20
                            StyledText {
                                id: npLabel
                                anchors.verticalCenter: parent.verticalCenter
                                text: Translation.tr("Now playing").toUpperCase()
                                font.pixelSize: 28
                                renderType: Text.QtRendering
                                font.letterSpacing: 0
                                font.weight: Font.DemiBold
                                color: ColorUtils.applyAlpha(root.colText, 0.85)
                            }
                            Rectangle {
                                x: npLabel.implicitWidth + 14
                                anchors.verticalCenter: parent.verticalCenter
                                width: Math.max(0, parent.width - x)
                                height: 2
                                radius: 1
                                color: ColorUtils.applyAlpha(root.colAccent2, 0.9)
                            }
                        }
                        StyledText {
                            width: parent.width
                            text: root._title
                            font.pixelSize: 44
                            renderType: Text.QtRendering
                            font.weight: Font.DemiBold
                            color: root.colText
                            elide: Text.ElideRight
                            animateChange: true
                            animationDistanceX: 8
                            animationDistanceY: 0
                        }
                        StyledText {
                            width: parent.width
                            text: playerBase.effectiveArtist
                            font.pixelSize: 32
                            renderType: Text.QtRendering
                            color: ColorUtils.applyAlpha(root.colText, 0.85)
                            elide: Text.ElideRight
                            visible: text !== ""
                        }
                    }

                    // live spectrum histogram
                    Canvas {
                        id: specCv
                        x: 52
                        y: 272
                        width: 510
                        height: 108
                        onPaint: {
                            const ctx = getContext("2d");
                            ctx.reset();
                            const w = width, H = height, N = 64, step = w / N;
                            const g = ctx.createLinearGradient(0, H, 0, 0);
                            g.addColorStop(0, ColorUtils.applyAlpha(root.colPrimary, 0.28));
                            g.addColorStop(0.5, root.colPrimary);
                            g.addColorStop(1, root.colAccent2);
                            ctx.fillStyle = g;
                            ctx.globalAlpha = 1;
                            const bw = Math.max(3, step * 0.62);
                            for (let i = 0; i < N; i++) {
                                const h = 5 + (root._disp[i] ?? 0.05) * (H - 12);
                                ctx.fillRect(i * step + (step - bw) / 2, H - h, bw, h);
                            }
                        }
                    }

                    // progress
                    Item {
                        x: 50
                        y: 392
                        width: 520
                        height: 24
                        StyledText {
                            x: 0
                            anchors.verticalCenter: parent.verticalCenter
                            text: StringUtils.friendlyTimeForSeconds(root._pos)
                            font.family: Appearance.font.family.numbers
                            font.pixelSize: 28
                            renderType: Text.QtRendering
                            color: root.colText
                        }
                        Item {
                            id: seekBox
                            x: 70
                            width: 378
                            height: parent.height
                            readonly property real frac: root._len > 0 ? Math.max(0, Math.min(1, root._pos / root._len)) : 0
                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width
                                height: 4
                                radius: 2
                                color: ColorUtils.applyAlpha(root.colText, 0.18)
                                Rectangle {
                                    height: parent.height
                                    radius: 2
                                    width: parent.width * seekBox.frac
                                    gradient: Gradient {
                                        orientation: Gradient.Horizontal
                                        GradientStop { position: 0; color: root.colPrimary }
                                        GradientStop { position: 1; color: root.colAccent2 }
                                    }
                                }
                                Rectangle {
                                    width: seekMouse.containsMouse || seekMouse.pressed ? 17 : 14
                                    height: width
                                    radius: width / 2
                                    color: root.colAccent2
                                    anchors.verticalCenter: parent.verticalCenter
                                    x: parent.width * seekBox.frac - width / 2
                                    Behavior on width {
                                        enabled: Appearance.animationsEnabled
                                        NumberAnimation { duration: 90 }
                                    }
                                }
                            }
                            MouseArea {
                                id: seekMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                enabled: playerBase.effectiveCanSeek
                                function seekAt(mx) {
                                    if (root._len <= 0)
                                        return;
                                    playerBase.seek(Math.max(0, Math.min(1, mx / Math.max(1, width))) * root._len);
                                }
                                onPressed: m => seekAt(m.x)
                                onPositionChanged: m => {
                                    if (pressed)
                                        seekAt(m.x);
                                }
                            }
                        }
                        StyledText {
                            x: 474
                            anchors.verticalCenter: parent.verticalCenter
                            text: StringUtils.friendlyTimeForSeconds(root._len)
                            font.family: Appearance.font.family.numbers
                            font.pixelSize: 28
                            renderType: Text.QtRendering
                            color: root.colText
                        }
                    }

                    // controls
                    Item {
                        id: ctlRow
                        x: 0
                        y: 430
                        width: 600
                        height: 96
                        CtlBtn {
                            x: 102 - width / 2
                            anchors.verticalCenter: parent.verticalCenter
                            icon: "shuffle"
                            active: root._shuffleOn
                            onClicked: root._shuffleOn = !root._shuffleOn
                        }
                        CtlBtn {
                            x: 208 - width / 2
                            anchors.verticalCenter: parent.verticalCenter
                            icon: "skip_previous"
                            enabled: playerBase.effectiveCanGoPrevious
                            onClicked: {
                                playerBase.previous();
                                root._burst();
                            }
                        }
                        CtlBtn {
                            x: 310 - width / 2
                            anchors.verticalCenter: parent.verticalCenter
                            big: true
                            icon: root._playing ? "pause" : "play_arrow"
                            onClicked: {
                                playerBase.togglePlaying();
                                root._burst();
                            }
                        }
                        CtlBtn {
                            x: 411 - width / 2
                            anchors.verticalCenter: parent.verticalCenter
                            icon: "skip_next"
                            enabled: playerBase.effectiveCanGoNext
                            onClicked: root._goNext()
                        }
                        CtlBtn {
                            x: 516 - width / 2
                            anchors.verticalCenter: parent.verticalCenter
                            icon: root._repeatOn ? "repeat_one" : "repeat"
                            active: root._repeatOn
                            onClicked: root._repeatOn = !root._repeatOn
                        }
                    }

                    // lyrics box ("LETRAS")
                    Item {
                        id: lyBox
                        x: 49
                        y: 565
                        width: 512
                        height: 272

                        Canvas {
                            anchors.fill: parent
                            property color c1: root.colAccent2
                            visible: false
                            onC1Changed: requestPaint()
                            Component.onCompleted: requestPaint()
                            onPaint: {
                                const ctx = getContext("2d");
                                ctx.reset();
                                const x0 = 1.5, y0 = 8, x1 = width - 1.5, y1 = height - 2, r = 24;
                                const gapL = 32, gapR = 142;
                                const path = () => {
                                    ctx.beginPath();
                                    ctx.moveTo(gapL, y0);
                                    ctx.lineTo(x0 + r, y0);
                                    ctx.arcTo(x0, y0, x0, y0 + r, r);
                                    ctx.lineTo(x0, y1 - r);
                                    ctx.arcTo(x0, y1, x0 + r, y1, r);
                                    ctx.lineTo(x1 - r, y1);
                                    ctx.arcTo(x1, y1, x1, y1 - r, r);
                                    ctx.lineTo(x1, y0 + r);
                                    ctx.arcTo(x1, y0, x1 - r, y0, r);
                                    ctx.lineTo(gapR, y0);
                                };
                                ctx.lineCap = "round";
                                ctx.strokeStyle = c1;
                                ctx.globalAlpha = 0.16;
                                ctx.lineWidth = 7;
                                path();
                                ctx.stroke();
                                ctx.globalAlpha = 0.95;
                                ctx.lineWidth = 2;
                                path();
                                ctx.stroke();
                            }
                        }
                        StyledText {
                            x: 40
                            y: -2
                            text: "LETRAS"
                            visible: false
                            font.pixelSize: 28
                            font.letterSpacing: 0
                            font.weight: Font.DemiBold
                            color: ColorUtils.applyAlpha(root.colText, 0.9)
                        }

                        // previous line (can wrap to two lines)
                        StyledText {
                            visible: root._lyricsActive
                            x: 12
                            y: 36
                            width: parent.width - 24
                            height: 74
                            verticalAlignment: Text.AlignVCenter
                            text: root._lyricAt(-1)
                            font.pixelSize: 34
                            font.family: "Z003"
                            renderType: Text.QtRendering
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.WordWrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                            color: ColorUtils.applyAlpha(root.colText, 0.75)
                        }
                        // current line: highlight bar + marker + karaoke fill
                        Rectangle {
                            visible: false
                            x: 24
                            y: 122
                            width: 460
                            height: 42
                            radius: 9
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0; color: ColorUtils.applyAlpha(root.colPrimary, 0.62) }
                                GradientStop { position: 1; color: ColorUtils.applyAlpha(root.colPrimary, 0.32) }
                            }
                        }
                        Rectangle {
                            visible: false
                            x: 26
                            y: 130
                            width: 13
                            height: 26
                            radius: 4
                            color: root.colAccent2
                        }
                        StyledText {
                            id: lyNow
                            x: 12
                            y: 122
                            width: parent.width - 24
                            height: 48
                            verticalAlignment: Text.AlignVCenter
                            horizontalAlignment: Text.AlignHCenter
                            text: root._lyricsActive ? (root._lyricAt(0) || "♪") : root._lyricsPlaceholder
                            font.pixelSize: 36
                            font.family: "Z003"
                            font.weight: Font.Normal
                            renderType: Text.QtRendering
                            elide: Text.ElideRight
                            color: root._lyricsActive ? ColorUtils.applyAlpha(root.colText, 0.72) : ColorUtils.applyAlpha(root.colText, 0.6)
                        }
                        Item {
                            visible: root._lyricsActive
                            clip: true
                            x: lyNow.x + Math.max(0, (lyNow.width - lyNow.contentWidth) / 2)
                            y: lyNow.y
                            width: Math.min(lyNow.width, lyNow.contentWidth) * root._lyFrac
                            height: lyNow.height
                            StyledText {
                                x: -Math.max(0, (lyNow.width - lyNow.contentWidth) / 2)
                                width: lyNow.width
                                height: lyNow.height
                                verticalAlignment: Text.AlignVCenter
                                horizontalAlignment: Text.AlignHCenter
                                text: lyNow.text
                                font: lyNow.font
                                renderType: Text.QtRendering
                                elide: lyNow.elide
                                color: root.colPrimary
                            }
                        }
                        StyledText {
                            visible: root._lyricsActive
                            x: 12
                            y: 170
                            width: parent.width - 24
                            height: 42
                            verticalAlignment: Text.AlignVCenter
                            text: root._lyricAt(1)
                            font.pixelSize: 34
                            font.family: "Z003"
                            renderType: Text.QtRendering
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                            color: ColorUtils.applyAlpha(root.colText, 0.75)
                            animateChange: true
                        }
                        StyledText {
                            visible: root._lyricsActive
                            x: 12
                            y: 216
                            width: parent.width - 24
                            height: 42
                            verticalAlignment: Text.AlignVCenter
                            text: root._lyricAt(2)
                            font.pixelSize: 34
                            font.family: "Z003"
                            renderType: Text.QtRendering
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                            color: ColorUtils.applyAlpha(root.colText, 0.6)
                        }
                    }

                    // equalizer shortcut (only when EasyEffects/iiEqualizer is available)
                    CtlBtn {
                        x: 520
                        y: 846
                        icon: "graphic_eq"
                        visible: EasyEffects.available
                            && (Config.options?.panelFamily ?? "ii") === "ii"
                            && (Config.options?.enabledPanels ?? []).includes("iiEqualizer")
                        onClicked: root.eqRequested()
                    }
                }

                // ═══════════════════ CENTER: YOU ═══════════════════
                Item {
                    id: centerZone
                    x: (content.width - width) / 2
                    width: 472
                    height: root._baseH

                    // avatar (your user picture) fading into the background
                    Item {
                        id: avatarBox
                        x: 16 + root._mx * 6
                        y: root._my * 3
                        width: 440
                        height: 352
                        scale: 1 + root._bass * 0.012
                        MaterialSymbol {
                            anchors.centerIn: parent
                            visible: avatarImg.status !== Image.Ready
                            text: "person"
                            iconSize: 150
                            fill: 1
                            color: ColorUtils.applyAlpha(root.colPrimary, 0.35)
                        }
                        Image {
                            id: avatarImg
                            anchors.fill: parent
                            source: Directories.userAvatarSourcePrimary
                            fillMode: Image.PreserveAspectCrop
                            cache: false
                            smooth: true
                            mipmap: true
                            asynchronous: true
                            layer.enabled: true
                            layer.effect: GE.OpacityMask {
                                maskSource: GE.RadialGradient {
                                    width: avatarImg.width
                                    height: avatarImg.height
                                    horizontalRadius: avatarImg.width * 0.5
                                    verticalRadius: avatarImg.height * 0.58
                                    verticalOffset: -26
                                    gradient: Gradient {
                                        GradientStop { position: 0.0; color: "#ffffffff" }
                                        GradientStop { position: 0.58; color: "#ffffffff" }
                                        GradientStop { position: 1.0; color: "#00ffffff" }
                                    }
                                }
                            }
                        }
                    }

                    // name
                    StyledText {
                        x: (parent.width - width) / 2 + 12
                        y: 344
                        text: root._bigName
                        font.pixelSize: 46
                        renderType: Text.QtRendering
                        font.weight: Font.Bold
                        font.letterSpacing: 0
                        color: root.colText
                    }
                    // live CPU dots
                    Row {
                        x: (parent.width - width) / 2
                        y: 410
                        spacing: 22
                        Repeater {
                            model: 7
                            delegate: Rectangle {
                                id: cpuDot
                                required property int index
                                readonly property bool lit: cpuDot.index < Math.max(1, Math.round(Math.max(0, Math.min(1, ResourceUsage.cpuUsage)) * 7))
                                width: 9
                                height: 9
                                radius: 4.5
                                color: cpuDot.lit ? root.colAccent2 : ColorUtils.applyAlpha(root.colPrimary, 0.4)
                                Behavior on color {
                                    enabled: Appearance.animationsEnabled
                                    ColorAnimation { duration: 260 }
                                }
                            }
                        }
                    }

                    // system info table
                    Item {
                        id: sysBox
                        x: 62
                        y: 447
                        width: 363
                        height: 262
                        Rectangle {
                            width: parent.width
                            height: 1
                            color: ColorUtils.applyAlpha(root.colPrimary, 0.28)
                        }
                        Column {
                            y: 1
                            width: parent.width
                            spacing: 0
                            SysRow { width: parent.width; k: "os"; v: root._distroName }
                            SysRow { width: parent.width; k: "cpu"; v: root.systemDetails.cpu ?? "—" }
                            SysRow { width: parent.width; k: "ram"; v: (ResourceUsage.memoryUsed / 1048576).toFixed(2) + " / " + (ResourceUsage.memoryTotal / 1048576).toFixed(2) + " GiB (" + Math.round(ResourceUsage.memoryUsedPercentage * 100) + "%)" }
                            SysRow { width: parent.width; k: "sh"; v: root.systemDetails.shell ?? "—" }
                            SysRow { width: parent.width; k: "kernel"; v: root.systemDetails.kernel ?? "—" }
                            SysRow { width: parent.width; k: "uptime"; v: root._uptimeHms }
                            SysRow { width: parent.width; k: "pkgs"; v: root.systemDetails.packages ?? "—" }
                            SysRow { width: parent.width; k: "wm"; v: root.systemDetails.wm ?? "—" }
                        }
                    }

                    // planet with orbit ring
                    Canvas {
                        id: planetCv
                        x: (parent.width - width) / 2
                        y: 733
                        width: 420
                        height: 130
                        onPaint: {
                            const ctx = getContext("2d");
                            ctx.reset();
                            const TAU = Math.PI * 2, w = width, cx = w / 2, cy = 62, R = 47;
                            const rx = 96, ry = 19, rot = -0.22, oy = cy + 10;
                            const pt = a => {
                                const x = rx * Math.cos(a), y = ry * Math.sin(a);
                                return { x: cx + x * Math.cos(rot) - y * Math.sin(rot), y: oy + x * Math.sin(rot) + y * Math.cos(rot) };
                            };
                            const arcPath = (a0, a1) => {
                                ctx.beginPath();
                                for (let i = 0; i <= 60; i++) {
                                    const p = pt(a0 + (a1 - a0) * i / 60);
                                    if (i === 0)
                                        ctx.moveTo(p.x, p.y);
                                    else
                                        ctx.lineTo(p.x, p.y);
                                }
                            };
                            const dot = p => {
                                ctx.fillStyle = root.colCore;
                                ctx.globalAlpha = 0.35;
                                ctx.beginPath();
                                ctx.arc(p.x, p.y, 7, 0, TAU);
                                ctx.fill();
                                ctx.globalAlpha = 1;
                                ctx.beginPath();
                                ctx.arc(p.x, p.y, 3.8, 0, TAU);
                                ctx.fill();
                            };
                            ctx.lineCap = "round";
                            // side lines
                            ctx.strokeStyle = root.colAccent2;
                            ctx.globalAlpha = 0.85;
                            ctx.lineWidth = 2;
                            ctx.beginPath();
                            ctx.moveTo(0, cy + 4);
                            ctx.lineTo(78, cy + 4);
                            ctx.moveTo(w - 78, cy + 4);
                            ctx.lineTo(w, cy + 4);
                            ctx.stroke();
                            // halo
                            const hg = ctx.createRadialGradient(cx, cy, R * 0.5, cx, cy, R * 1.7);
                            hg.addColorStop(0, ColorUtils.applyAlpha(root.colPrimary, 0.28 + root._bass * 0.2));
                            hg.addColorStop(1, ColorUtils.applyAlpha(root.colPrimary, 0));
                            ctx.globalAlpha = 1;
                            ctx.fillStyle = hg;
                            ctx.beginPath();
                            ctx.arc(cx, cy, R * 1.7, 0, TAU);
                            ctx.fill();
                            // back half of the ring
                            ctx.strokeStyle = root.colAccent2;
                            ctx.globalAlpha = 0.35;
                            ctx.lineWidth = 1.6;
                            arcPath(Math.PI, TAU);
                            ctx.stroke();
                            const sa = root._t * 0.6, sp = pt(sa), front = Math.sin(sa) > 0;
                            if (!front)
                                dot(sp);
                            // sphere
                            const sg = ctx.createRadialGradient(cx - R * 0.3, cy - R * 0.35, R * 0.1, cx, cy, R);
                            sg.addColorStop(0, ColorUtils.applyAlpha(root.colCore, 0.5));
                            sg.addColorStop(0.6, ColorUtils.applyAlpha(root.colAccent2, 0.3));
                            sg.addColorStop(1, ColorUtils.applyAlpha(root.colPrimary, 0.18));
                            ctx.globalAlpha = 1;
                            ctx.fillStyle = sg;
                            ctx.beginPath();
                            ctx.arc(cx, cy, R, 0, TAU);
                            ctx.fill();
                            ctx.strokeStyle = root.colAccent2;
                            ctx.globalAlpha = 0.2;
                            ctx.lineWidth = 8;
                            ctx.beginPath();
                            ctx.arc(cx, cy, R, 0, TAU);
                            ctx.stroke();
                            ctx.globalAlpha = 0.95;
                            ctx.lineWidth = 2.4;
                            ctx.beginPath();
                            ctx.arc(cx, cy, R, 0, TAU);
                            ctx.stroke();
                            // front half of the ring
                            ctx.globalAlpha = 0.95;
                            ctx.lineWidth = 2;
                            arcPath(0, Math.PI);
                            ctx.stroke();
                            if (front)
                                dot(sp);
                            ctx.globalAlpha = 1;
                        }
                    }
                }

                // ═══════════════════ RIGHT: SYSTEM ═══════════════════
                Item {
                    id: rightZone
                    x: content.width - 600
                    width: 600
                    height: root._baseH

                    // clock + date
                    Row {
                        x: 40
                        y: 88
                        spacing: 8
                        StyledText {
                            text: root._clockHM
                            font.pixelSize: 74
                            renderType: Text.QtRendering
                            font.weight: Font.Bold
                            font.family: Appearance.font.family.main
                            color: root.colText
                        }
                        StyledText {
                            y: 46
                            text: root._clockAP
                            font.pixelSize: 32
                            renderType: Text.QtRendering
                            font.weight: Font.Medium
                            color: root.colText
                        }
                    }
                    StyledText {
                        x: 42
                        y: 172
                        text: root._dateStr
                        font.pixelSize: 30
                        renderType: Text.QtRendering
                        color: ColorUtils.applyAlpha(root.colText, 0.9)
                    }
                    // divider between clock and weather
                    Rectangle {
                        x: 318
                        y: 90
                        width: 1.5
                        height: 116
                        gradient: Gradient {
                            GradientStop { position: 0.0; color: ColorUtils.applyAlpha(root.colPrimary, 0) }
                            GradientStop { position: 0.5; color: ColorUtils.applyAlpha(root.colPrimary, 0.7) }
                            GradientStop { position: 1.0; color: ColorUtils.applyAlpha(root.colPrimary, 0) }
                        }
                    }
                    // weather
                    MaterialSymbol {
                        x: 352
                        y: 92
                        text: root._wIcon
                        iconSize: 86
                        color: root.colText
                    }
                    Column {
                        x: 468
                        y: 102
                        width: 120
                        spacing: 0
                        StyledText {
                            width: parent.width
                            text: root._wTemp
                            font.pixelSize: 37
                            renderType: Text.QtRendering
                            font.weight: Font.Medium
                            color: root.colText
                            elide: Text.ElideRight
                        }
                        StyledText {
                            width: parent.width
                            text: root._wDesc
                            font.pixelSize: 28
                            renderType: Text.QtRendering
                            color: ColorUtils.applyAlpha(root.colText, 0.8)
                            elide: Text.ElideRight
                        }
                    }

                    // glowing wave
                    Canvas {
                        id: clockWaveCv
                        x: 40
                        y: 218
                        width: 508
                        height: 56
                        onPaint: {
                            const ctx = getContext("2d");
                            ctx.reset();
                            const w = width, h = height, mid = h / 2;
                            ctx.lineCap = "round";
                            const fy = (x, k) => {
                                const env = Math.sin(Math.PI * x / w);
                                const amp = (4 + root._bass * 18 + root._mid * 8) * env * (1 - 0.25 * k);
                                return mid + amp * Math.sin(x * 0.03 * (1 + 0.35 * k) - root._t * (2.0 + k * 0.8) + k);
                            };
                            for (let k = 2; k >= 0; k--) {
                                ctx.beginPath();
                                for (let x = 0; x <= w; x += 3) {
                                    const y = fy(x, k);
                                    if (x === 0)
                                        ctx.moveTo(x, y);
                                    else
                                        ctx.lineTo(x, y);
                                }
                                ctx.strokeStyle = k === 0 ? root.colAccent2 : root.colPrimary;
                                ctx.globalAlpha = k === 0 ? 0.95 : 0.4;
                                ctx.lineWidth = k === 0 ? 2.6 : 1.2;
                                ctx.stroke();
                            }
                            ctx.globalAlpha = 1;
                        }
                    }

                    // queue header
                    Item {
                        x: 40
                        y: 294
                        width: 508
                        height: 22
                        StyledText {
                            id: qLabel
                            anchors.verticalCenter: parent.verticalCenter
                            text: "COLA DE REPRODUCCIÓN"
                            font.pixelSize: 28
                            renderType: Text.QtRendering
                            font.letterSpacing: 0
                            font.weight: Font.DemiBold
                            color: ColorUtils.applyAlpha(root.colText, 0.9)
                        }
                        Rectangle {
                            x: qLabel.implicitWidth + 14
                            anchors.verticalCenter: parent.verticalCenter
                            width: Math.max(0, parent.width - x)
                            height: 2
                            radius: 1
                            color: ColorUtils.applyAlpha(root.colAccent2, 0.9)
                        }
                    }

                    // queue
                    Item {
                        id: queueBox
                        x: 0
                        y: 342
                        width: 600
                        height: 304
                        // current-track marker dot
                        Rectangle {
                            x: 28
                            y: 38 - height / 2
                            width: 11
                            height: 11
                            radius: 5.5
                            color: root.colAccent2
                            border.width: 3
                            border.color: ColorUtils.applyAlpha(root.colAccent2, 0.35)
                        }
                        ListView {
                            id: qList
                            x: 55
                            width: 512
                            height: parent.height
                            model: root._queue
                            clip: true
                            spacing: 0
                            boundsBehavior: Flickable.StopAtBounds
                            delegate: Item {
                                id: qRow
                                required property var modelData
                                required property int index
                                width: 493
                                height: 76
                                Rectangle {
                                    anchors.fill: parent
                                    anchors.topMargin: 1
                                    anchors.bottomMargin: 1
                                    radius: 14
                                    border.width: qRow.modelData.current ? 1 : 0
                                    border.color: ColorUtils.applyAlpha(root.colAccent2, 0.55)
                                    color: qRow.modelData.current ? ColorUtils.applyAlpha(root.colPrimary, 0.5) : (qMouse.containsMouse ? ColorUtils.applyAlpha(root.colText, 0.08) : "transparent")
                                    Behavior on color {
                                        enabled: Appearance.animationsEnabled
                                        ColorAnimation { duration: 120 }
                                    }
                                }
                                // right accent bar for the playing row
                                Rectangle {
                                    visible: qRow.modelData.current
                                    x: qRow.width + 6
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 4
                                    height: 66
                                    radius: 2
                                    color: root.colAccent2
                                }
                                ClippingRectangle {
                                    id: qThumb
                                    x: 14
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 74
                                    height: 58
                                    radius: 10
                                    color: ColorUtils.applyAlpha(root.colPrimary, 0.3)
                                    Image {
                                        anchors.fill: parent
                                        source: qRow.modelData.art ?? ""
                                        sourceSize: Qt.size(160, 120)
                                        fillMode: Image.PreserveAspectCrop
                                        asynchronous: true
                                    }
                                }
                                Column {
                                    x: 120
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - 120 - 80
                                    spacing: 1
                                    StyledText {
                                        width: parent.width
                                        text: qRow.modelData.title
                                        font.pixelSize: 34
                                        renderType: Text.QtRendering
                                        font.weight: Font.Medium
                                        color: root.colText
                                        elide: Text.ElideRight
                                    }
                                    StyledText {
                                        width: parent.width
                                        text: qRow.modelData.artist
                                        font.pixelSize: 28
                                        renderType: Text.QtRendering
                                        color: ColorUtils.applyAlpha(root.colText, 0.7)
                                        elide: Text.ElideRight
                                    }
                                }
                                StyledText {
                                    anchors.right: parent.right
                                    anchors.rightMargin: 20
                                    y: 14
                                    text: qRow.modelData.dur
                                    font.pixelSize: 28
                                    renderType: Text.QtRendering
                                    font.family: Appearance.font.family.numbers
                                    color: qRow.modelData.current ? root.colCore : ColorUtils.applyAlpha(root.colText, 0.8)
                                }
                                MouseArea {
                                    id: qMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root._playQueueItem(qRow.modelData)
                                }
                            }
                        }
                    }

                    // separator
                    Rectangle {
                        x: 43
                        y: 672
                        width: 505
                        height: 1.5
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0.0; color: ColorUtils.applyAlpha(root.colAccent2, 0) }
                            GradientStop { position: 0.15; color: ColorUtils.applyAlpha(root.colAccent2, 0.7) }
                            GradientStop { position: 0.85; color: ColorUtils.applyAlpha(root.colAccent2, 0.7) }
                            GradientStop { position: 1.0; color: ColorUtils.applyAlpha(root.colAccent2, 0) }
                        }
                    }

                    // gauges
                    Gauge {
                        x: 26
                        y: 688
                        label: "CPU"
                        value: Math.max(0, Math.min(1, ResourceUsage.cpuUsage))
                        sub: root._cpuGhz
                    }
                    Gauge {
                        x: 161
                        y: 688
                        label: "GPU"
                        value: Math.max(0, Math.min(1, ResourceUsage.gpuUsage))
                        sub: root._gpuLabel
                    }
                    Gauge {
                        x: 301
                        y: 688
                        label: "RAM"
                        value: Math.max(0, Math.min(1, ResourceUsage.memoryUsedPercentage))
                        sub: root._ramText
                    }
                    Gauge {
                        x: 442
                        y: 688
                        label: "DISCO"
                        value: Math.max(0, Math.min(1, ResourceUsage.diskUsedPercentage))
                        sub: root._diskText
                    }
                }
            }
        }
    }

    // ═══════════ Inline components ═══════════

    component CtlBtn: Item {
        id: cb
        property string icon: ""
        property bool active: false
        property bool big: false
        signal clicked
        implicitWidth: cb.big ? 86 : 54
        implicitHeight: cb.big ? 86 : 54
        width: implicitWidth
        height: implicitHeight
        opacity: cb.enabled ? 1 : 0.35
        scale: cbMouse.pressed ? 0.9 : (cbMouse.containsMouse ? 1.1 : 1)
        Behavior on scale {
            enabled: Appearance.animationsEnabled
            NumberAnimation { duration: 100 }
        }
        Rectangle {
            visible: cb.big
            anchors.fill: parent
            radius: width / 2
            color: ColorUtils.applyAlpha(root.colPrimary, cbMouse.containsMouse ? 0.24 : 0.06)
            border.width: 4
            border.color: ColorUtils.applyAlpha(root.colAccent2, 0.85 + root._flash * 0.15)
        }
        MaterialSymbol {
            anchors.centerIn: parent
            text: cb.icon
            iconSize: cb.big ? 48 : 34
            fill: 1
            color: cb.active ? root.colAccent2 : root.colText
        }
        MouseArea {
            id: cbMouse
            anchors.fill: parent
            hoverEnabled: true
            enabled: cb.enabled
            cursorShape: Qt.PointingHandCursor
            onClicked: cb.clicked()
        }
    }

    component SysRow: Item {
        id: sr
        property string k: ""
        property string v: ""
        height: 32.4
        StyledText {
            x: 2
            width: 100
            anchors.verticalCenter: parent.verticalCenter
            text: sr.k
            font.family: Appearance.font.family.main
            font.pixelSize: 30
            renderType: Text.QtRendering
            color: root.colAccent2
        }
        StyledText {
            x: 106
            width: parent.width - 106
            anchors.verticalCenter: parent.verticalCenter
            text: sr.v
            font.family: Appearance.font.family.main
            font.pixelSize: 30
            renderType: Text.QtRendering
            color: root.colText
            elide: Text.ElideRight
        }
        Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width
            height: 1
            color: ColorUtils.applyAlpha(root.colPrimary, 0.28)
        }
    }

    component Gauge: Item {
        id: g
        property string label: ""
        property real value: 0
        property string sub: ""
        width: 120
        height: 150
        onValueChanged: gaugeCanvas.requestPaint()
        Item {
            x: 5
            y: 0
            width: 110
            height: 110
            Canvas {
                id: gaugeCanvas
                anchors.fill: parent
                Component.onCompleted: requestPaint()
                onPaint: {
                    const ctx = getContext("2d");
                    ctx.reset();
                    const c = width / 2, R = 48, TAU = Math.PI * 2, a0 = -Math.PI / 2;
                    ctx.lineCap = "round";
                    ctx.strokeStyle = root.colPrimary;
                    ctx.globalAlpha = 0.25;
                    ctx.lineWidth = 5;
                    ctx.beginPath();
                    ctx.arc(c, c, R, 0, TAU);
                    ctx.stroke();
                    if (g.value > 0.002) {
                        ctx.strokeStyle = root.colAccent2;
                        ctx.globalAlpha = 0.22;
                        ctx.lineWidth = 10;
                        ctx.beginPath();
                        ctx.arc(c, c, R, a0, a0 + TAU * g.value, false);
                        ctx.stroke();
                        ctx.globalAlpha = 1;
                        ctx.lineWidth = 5;
                        ctx.beginPath();
                        ctx.arc(c, c, R, a0, a0 + TAU * g.value, false);
                        ctx.stroke();
                    }
                }
            }
            Column {
                anchors.centerIn: parent
                spacing: -2
                StyledText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: g.label
                    font.pixelSize: 28
                    renderType: Text.QtRendering
                    color: root.colText
                }
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 1
                    StyledText {
                        text: Math.round(g.value * 100)
                        font.pixelSize: 38
                        renderType: Text.QtRendering
                        font.weight: Font.DemiBold
                        color: root.colText
                    }
                    StyledText {
                        y: 9
                        text: "%"
                        font.pixelSize: 26
                        renderType: Text.QtRendering
                        color: root.colText
                    }
                }
            }
        }
        StyledText {
            x: -10
            y: 108
            width: parent.width + 20
            horizontalAlignment: Text.AlignHCenter
            text: g.sub
            font.pixelSize: 26
            renderType: Text.QtRendering
            color: ColorUtils.applyAlpha(root.colText, 0.85)
            elide: Text.ElideRight
        }
        Timer {
            interval: 600
            repeat: true
            running: root.visible
            onTriggered: gaugeCanvas.requestPaint()
        }
    }
}
