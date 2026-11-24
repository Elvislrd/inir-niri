pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services
import Quickshell
import QtQuick
import QtQuick.Layouts

/**
 * ResourcesPopup — estilo Caelestia (pestaña "Rendimiento"), versión ancha.
 *
 *  Fila 1:  CPU (temp + "Uso")  ·  GPU (temp + "Uso")  ·  Batería (píldora alta a la derecha)
 *  Fila 2:  Almacenamiento (aro grande)  ·  Actividad (gráfica + valores)  ·  Memoria (aro)
 *  Acento por estado: normal = tema, aviso = amarillo, crítico = rojo.
 *  Sin fondo propio (cristal de StyledPopup). Sin procesos externos.
 */
StyledPopup {
    id: root
    sticky: true

    property QtObject resourceMonitor: ResourceUsageMonitor { active: root.active }

    // ───────── componentes reutilizables (sin ids externos) ─────────

    // Aro de progreso (270°) con texto al centro
    component Ring: Item {
        id: ring
        property real value: 0
        property color accent: "white"
        property color track: "#33ffffff"
        property color textColor: "white"
        property string label: ""
        property real shown: value
        property bool animate: Appearance.animationsEnabled ?? true

        Behavior on shown {
            NumberAnimation {
                duration: ring.animate ? 600 : 0
                easing.type: Easing.OutCubic
            }
        }
        onShownChanged: cv.requestPaint()
        onAccentChanged: cv.requestPaint()
        onTrackChanged: cv.requestPaint()
        onWidthChanged: cv.requestPaint()

        Canvas {
            id: cv
            anchors.fill: parent
            onPaint: {
                const ctx = getContext("2d");
                ctx.clearRect(0, 0, width, height);
                const lw = Math.max(6, ring.width * 0.085);
                const r = Math.min(width, height) / 2 - lw;
                const cx = width / 2, cy = height / 2;
                const a0 = Math.PI * 0.75;
                const full = Math.PI * 1.5;
                ctx.lineWidth = lw;
                ctx.lineCap = "round";
                ctx.beginPath();
                ctx.arc(cx, cy, r, a0, a0 + full);
                ctx.strokeStyle = ring.track;
                ctx.stroke();
                const v = Math.max(0, Math.min(1, ring.shown));
                if (v > 0.005) {
                    ctx.beginPath();
                    ctx.arc(cx, cy, r, a0, a0 + full * v);
                    ctx.strokeStyle = ring.accent;
                    ctx.stroke();
                }
            }
        }
        Column {
            anchors.centerIn: parent
            spacing: 0
            StyledText {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Math.round(ring.value * 100) + "%"
                font.pixelSize: Math.max(14, ring.width * 0.26)
                font.weight: Font.DemiBold
                color: ring.textColor
            }
            StyledText {
                anchors.horizontalCenter: parent.horizontalCenter
                text: ring.label
                font.pixelSize: Appearance.font.pixelSize.small
                color: ColorUtils.applyAlpha(ring.textColor, 0.6)
            }
        }
    }

    // Barra con punto al final (temperatura)
    component TempBar: Item {
        id: tb
        property real value: 0
        property color accent: "white"
        property color track: "#33ffffff"
        property bool animate: Appearance.animationsEnabled ?? true
        implicitHeight: 12

        Rectangle {
            id: trk
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            height: 6
            radius: 3
            color: tb.track
        }
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            height: 6
            radius: 3
            color: tb.accent
            width: Math.max(6, trk.width * Math.max(0, Math.min(1, tb.value)))
            Behavior on width {
                NumberAnimation {
                    duration: tb.animate ? 500 : 0
                    easing.type: Easing.OutCubic
                }
            }
        }
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 10
            height: 10
            radius: 5
            color: tb.accent
            x: Math.min(trk.width - 10, Math.max(0, trk.width * Math.max(0, Math.min(1, tb.value)) - 5))
            Behavior on x {
                NumberAnimation {
                    duration: tb.animate ? 500 : 0
                    easing.type: Easing.OutCubic
                }
            }
        }
    }

    // Gráfica de líneas suaves (varias series 0..1)
    component Spark: Canvas {
        id: sp
        property var series: []
        property var colors: []
        property int points: 40
        onSeriesChanged: requestPaint()
        onColorsChanged: requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onPaint: {
            const ctx = getContext("2d");
            ctx.clearRect(0, 0, width, height);
            const W = width, H = height - 6;
            const step = W / (sp.points - 1);
            // línea base
            ctx.beginPath();
            ctx.moveTo(0, H + 3);
            ctx.lineTo(W, H + 3);
            ctx.lineWidth = 1;
            ctx.strokeStyle = ColorUtils.applyAlpha(sp.colors[0], 0.25);
            ctx.stroke();
            for (let s = 0; s < sp.series.length; s++) {
                const d = sp.series[s];
                if (!d || d.length < 2)
                    continue;
                const off = sp.points - d.length;
                const px = i => (off + i) * step;
                const py = i => 3 + H - Math.max(0, Math.min(1, d[i])) * H;
                ctx.beginPath();
                ctx.moveTo(px(0), py(0));
                for (let i = 1; i < d.length; i++) {
                    const mx = (px(i - 1) + px(i)) / 2;
                    ctx.bezierCurveTo(mx, py(i - 1), mx, py(i), px(i), py(i));
                }
                ctx.lineWidth = 1.8;
                ctx.lineJoin = "round";
                ctx.strokeStyle = sp.colors[s];
                ctx.stroke();
                if (s === 0) {
                    ctx.lineTo(px(d.length - 1), H + 3);
                    ctx.lineTo(px(0), H + 3);
                    ctx.closePath();
                    const g = ctx.createLinearGradient(0, 0, 0, height);
                    g.addColorStop(0, ColorUtils.applyAlpha(sp.colors[s], 0.30));
                    g.addColorStop(1, ColorUtils.applyAlpha(sp.colors[s], 0));
                    ctx.fillStyle = g;
                    ctx.fill();
                }
            }
        }
    }

    // ───────── contenido ─────────
    Item {
        id: body
        implicitWidth: 720
        implicitHeight: mainRow.implicitHeight
        anchors.centerIn: parent

        readonly property bool live: root.active

        // ── tema ──
        readonly property color colText: Appearance.angelEverywhere ? Appearance.angel.colText
            : Appearance.inirEverywhere ? Appearance.inir.colText : Appearance.colors.colOnLayer1
        readonly property color colMuted: ColorUtils.applyAlpha(body.colText, 0.62)
        // Tarjetas de fondo: poner true si quieres cajas suaves detrás de cada bloque
        readonly property bool cards: false
        readonly property color colCard: cards ? ColorUtils.applyAlpha(body.colText, 0.07) : "transparent"
        readonly property color colTrack: ColorUtils.applyAlpha(body.colText, 0.16)
        readonly property color colWarn: "#f9c74f"
        readonly property real cardRadius: Appearance.rounding.normal ?? 14

        function sevColor(s) {
            return s >= 2 ? Appearance.colors.colError : s === 1 ? body.colWarn : Appearance.colors.colPrimary;
        }

        // ── umbrales ──
        readonly property real cpuWarn: Config.options?.resources?.cpuWarningThreshold ?? 90
        readonly property real gpuWarn: Config.options?.resources?.gpuWarningThreshold ?? 90
        readonly property real memWarn: Config.options?.resources?.memoryWarningThreshold ?? 90
        readonly property real tCaution: Config.options?.resources?.tempCautionThreshold ?? 65
        readonly property real tWarn: Config.options?.resources?.tempWarningThreshold ?? 80

        // ── datos ──
        function clamp01(x) {
            return Math.max(0, Math.min(1, Number(x) || 0));
        }
        readonly property real cpu: clamp01(ResourceUsage.cpuUsage)
        readonly property real cpuT: Number(ResourceUsage.cpuTemp) || 0
        readonly property bool gpuOk: ResourceUsage.gpuUsageAvailable ?? false
        readonly property real gpu: gpuOk ? clamp01(ResourceUsage.gpuUsage) : 0
        readonly property real gpuT: Number(ResourceUsage.gpuTemp) || 0
        readonly property real memTotal: Number(ResourceUsage.memoryTotal) || 0
        readonly property real memUsed: Number(ResourceUsage.memoryUsed) || 0
        readonly property real memFrac: memTotal > 0 ? clamp01(memUsed / memTotal) : 0
        readonly property real diskTotal: Number(ResourceUsage.diskTotal) || 0
        readonly property real diskUsed: Number(ResourceUsage.diskUsed) || 0
        readonly property real diskFrac: diskTotal > 0 ? clamp01(diskUsed / diskTotal) : 0
        readonly property real swapTotal: Number(ResourceUsage.swapTotal) || 0
        readonly property real swapUsed: Number(ResourceUsage.swapUsed) || 0
        readonly property bool batOk: Battery.available ?? true
        readonly property real batPct: {
            const p = Number(Battery.percentage) || 0;
            return clamp01(p > 1 ? p / 100 : p);
        }
        readonly property bool batCharging: Battery.isCharging ?? false
        readonly property bool batPlugged: Battery.isPluggedIn ?? false

        // ── severidades (0 normal · 1 aviso · 2 crítico) ──
        function sevUse(frac, warn) {
            const p = frac * 100;
            return p >= warn ? 2 : p >= warn - 20 ? 1 : 0;
        }
        function sevTemp(t) {
            return t >= tWarn ? 2 : t >= tCaution ? 1 : 0;
        }
        readonly property int cpuSev: Math.max(sevUse(cpu, cpuWarn), sevTemp(cpuT))
        readonly property int gpuSev: gpuOk ? Math.max(sevUse(gpu, gpuWarn), sevTemp(gpuT)) : 0
        readonly property int memSev: sevUse(memFrac, memWarn)
        readonly property int diskSev: diskFrac >= 0.9 ? 2 : diskFrac >= 0.8 ? 1 : 0
        readonly property int batSev: batCharging ? 0 : batPct <= 0.15 ? 2 : batPct <= 0.30 ? 1 : 0

        // ── formato ──
        // Memoria y swap vienen en KiB; el disco viene en bytes.
        function gibFromKb(kb) {
            return fmtGib(kb / (1024 * 1024));
        }
        function gibFromBytes(b) {
            return fmtGib(b / (1024 * 1024 * 1024));
        }
        function fmtGib(g) {
            return g >= 100 ? Math.round(g) + " GiB" : g.toFixed(1) + " GiB";
        }
        function pct(x) {
            return Math.round(x * 100) + "%";
        }
        readonly property string batState: !batOk ? "Sin batería"
            : batCharging ? "Cargando"
            : batPct >= 0.99 ? "Completa"
            : batPlugged ? "Conectada" : "En uso"

        // ── historial para la gráfica ──
        property var hist: [[], [], []]
        function pushHist() {
            const N = 40;
            const vals = [body.cpu, body.gpu, body.memFrac];
            const out = [];
            for (let i = 0; i < 3; i++) {
                const a = body.hist[i].slice(Math.max(0, body.hist[i].length - (N - 1)));
                a.push(vals[i]);
                out.push(a);
            }
            body.hist = out;
        }
        Timer {
            interval: 1000
            repeat: true
            running: body.live
            triggeredOnStart: true
            onTriggered: body.pushHist()
        }

        RowLayout {
            id: mainRow
            width: body.width
            spacing: 14

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignTop
                spacing: 14

                // ───────── Fila 1: CPU · GPU ─────────
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 14

                    // CPU
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        Layout.preferredHeight: 118
                        radius: body.cardRadius
                        color: body.colCard

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 10

                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                spacing: 2
                                RowLayout {
                                    spacing: 6
                                    MaterialSymbol {
                                        text: "memory"
                                        iconSize: 22
                                        color: body.sevColor(body.cpuSev)
                                    }
                                    StyledText {
                                        text: "CPU"
                                        font.pixelSize: 20
                                        font.weight: Font.DemiBold
                                        color: body.colText
                                    }
                                }
                                StyledText {
                                    text: "Procesador"
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    color: body.colMuted
                                }
                                Item { Layout.fillHeight: true }
                                RowLayout {
                                    spacing: 5
                                    MaterialSymbol {
                                        text: "device_thermostat"
                                        iconSize: 18
                                        color: body.colMuted
                                    }
                                    StyledText {
                                        text: body.cpuT > 0 ? Math.round(body.cpuT) + "°C" : "—"
                                        font.pixelSize: Appearance.font.pixelSize.normal
                                        color: body.colText
                                    }
                                }
                                TempBar {
                                    Layout.fillWidth: true
                                    value: body.cpuT / 100
                                    accent: body.sevColor(body.sevTemp(body.cpuT))
                                    track: body.colTrack
                                }
                            }
                            ColumnLayout {
                                Layout.alignment: Qt.AlignVCenter
                                spacing: 4
                                StyledText {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: "Uso"
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    color: body.colMuted
                                }
                                Rectangle {
                                    Layout.alignment: Qt.AlignHCenter
                                    implicitWidth: 84
                                    implicitHeight: 84
                                    radius: 30
                                    color: ColorUtils.applyAlpha(body.sevColor(body.cpuSev), 0.22)
                                    StyledText {
                                        anchors.centerIn: parent
                                        text: body.pct(body.cpu)
                                        font.pixelSize: 26
                                        font.weight: Font.DemiBold
                                        color: body.sevColor(body.cpuSev)
                                    }
                                }
                            }
                        }
                    }

                    // GPU
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        Layout.preferredHeight: 118
                        radius: body.cardRadius
                        color: body.colCard
                        opacity: body.gpuOk ? 1 : 0.55

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 10

                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                spacing: 2
                                RowLayout {
                                    spacing: 6
                                    MaterialSymbol {
                                        text: "desktop_windows"
                                        iconSize: 22
                                        color: body.sevColor(body.gpuSev)
                                    }
                                    StyledText {
                                        text: "GPU"
                                        font.pixelSize: 20
                                        font.weight: Font.DemiBold
                                        color: body.colText
                                    }
                                }
                                StyledText {
                                    text: body.gpuOk ? "Gráficos" : "Sin GPU"
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    color: body.colMuted
                                }
                                Item { Layout.fillHeight: true }
                                RowLayout {
                                    spacing: 5
                                    MaterialSymbol {
                                        text: "device_thermostat"
                                        iconSize: 18
                                        color: body.colMuted
                                    }
                                    StyledText {
                                        text: body.gpuOk && body.gpuT > 0 ? Math.round(body.gpuT) + "°C" : "—"
                                        font.pixelSize: Appearance.font.pixelSize.normal
                                        color: body.colText
                                    }
                                }
                                TempBar {
                                    Layout.fillWidth: true
                                    value: body.gpuOk ? body.gpuT / 100 : 0
                                    accent: body.sevColor(body.sevTemp(body.gpuT))
                                    track: body.colTrack
                                }
                            }
                            ColumnLayout {
                                Layout.alignment: Qt.AlignVCenter
                                spacing: 4
                                StyledText {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: "Uso"
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    color: body.colMuted
                                }
                                Rectangle {
                                    Layout.alignment: Qt.AlignHCenter
                                    implicitWidth: 84
                                    implicitHeight: 84
                                    radius: 30
                                    color: ColorUtils.applyAlpha(body.sevColor(body.gpuSev), 0.22)
                                    StyledText {
                                        anchors.centerIn: parent
                                        text: body.gpuOk ? body.pct(body.gpu) : "—"
                                        font.pixelSize: 26
                                        font.weight: Font.DemiBold
                                        color: body.sevColor(body.gpuSev)
                                    }
                                }
                            }
                        }
                    }
                }

                // ───────── Fila 2: Almacenamiento · Actividad · Memoria ─────────
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 14

                    // Almacenamiento
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 220
                        Layout.preferredHeight: 156
                        radius: body.cardRadius
                        color: body.colCard

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 10
                            Ring {
                                Layout.preferredWidth: 100
                                Layout.preferredHeight: 100
                                Layout.alignment: Qt.AlignVCenter
                                value: body.diskFrac
                                accent: body.sevColor(body.diskSev)
                                track: body.colTrack
                                textColor: body.colText
                                label: "Usado"
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignVCenter
                                spacing: 3
                                StyledText {
                                    Layout.fillWidth: true
                                    text: "Almacenamiento"
                                    font.pixelSize: Appearance.font.pixelSize.normal
                                    font.weight: Font.DemiBold
                                    color: body.colText
                                    elide: Text.ElideRight
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    text: body.gibFromBytes(body.diskUsed) + " / " + body.gibFromBytes(body.diskTotal)
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    color: body.colMuted
                                    elide: Text.ElideRight
                                }
                            }
                        }
                    }

                    // Actividad (en lugar de Red)
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 190
                        Layout.preferredHeight: 156
                        radius: body.cardRadius
                        color: body.colCard

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 4
                            RowLayout {
                                spacing: 6
                                MaterialSymbol {
                                    text: "monitoring"
                                    iconSize: 20
                                    color: Appearance.colors.colPrimary
                                }
                                StyledText {
                                    text: "Actividad"
                                    font.pixelSize: Appearance.font.pixelSize.large
                                    font.weight: Font.DemiBold
                                    color: body.colText
                                }
                            }
                            Spark {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                series: body.hist
                                colors: [Appearance.colors.colPrimary, Appearance.colors.colSecondary, Appearance.colors.colTertiary]
                            }
                            Repeater {
                                model: [
                                    { i: "memory", n: "CPU", v: body.pct(body.cpu), c: Appearance.colors.colPrimary },
                                    { i: "desktop_windows", n: "GPU", v: body.gpuOk ? body.pct(body.gpu) : "—", c: Appearance.colors.colSecondary },
                                    { i: "developer_board", n: "RAM", v: body.pct(body.memFrac), c: Appearance.colors.colTertiary }
                                ]
                                delegate: RowLayout {
                                    id: leg
                                    required property var modelData
                                    Layout.fillWidth: true
                                    spacing: 6
                                    MaterialSymbol {
                                        text: leg.modelData.i
                                        iconSize: 14
                                        color: leg.modelData.c
                                    }
                                    StyledText {
                                        text: leg.modelData.n
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        color: body.colMuted
                                    }
                                    Item { Layout.fillWidth: true }
                                    StyledText {
                                        text: leg.modelData.v
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        font.weight: Font.Medium
                                        color: body.colText
                                    }
                                }
                            }
                        }
                    }

                    // Memoria
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 170
                        Layout.preferredHeight: 156
                        radius: body.cardRadius
                        color: body.colCard

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 4
                            RowLayout {
                                Layout.alignment: Qt.AlignHCenter
                                spacing: 6
                                MaterialSymbol {
                                    text: "developer_board"
                                    iconSize: 18
                                    color: body.sevColor(body.memSev)
                                }
                                StyledText {
                                    text: "Memoria"
                                    font.pixelSize: Appearance.font.pixelSize.large
                                    font.weight: Font.DemiBold
                                    color: body.colText
                                }
                            }
                            Ring {
                                Layout.alignment: Qt.AlignHCenter
                                Layout.preferredWidth: 82
                                Layout.preferredHeight: 82
                                value: body.memFrac
                                accent: body.sevColor(body.memSev)
                                track: body.colTrack
                                textColor: body.colText
                                label: "Usado"
                            }
                            StyledText {
                                Layout.alignment: Qt.AlignHCenter
                                text: body.gibFromKb(body.memUsed) + " / " + body.gibFromKb(body.memTotal)
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: body.colMuted
                            }
                        }
                    }
                }
            }

            // ───────── Batería (píldora alta) ─────────
            Rectangle {
                id: batPill
                Layout.preferredWidth: 112
                Layout.fillHeight: true
                radius: 34
                color: ColorUtils.applyAlpha(body.sevColor(body.batSev), 0.14)
                opacity: body.batOk ? 1 : 0.55

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    radius: batPill.radius
                    height: batPill.height * (body.batOk ? body.batPct : 0)
                    color: ColorUtils.applyAlpha(body.sevColor(body.batSev), 0.30)
                    Behavior on height {
                        NumberAnimation {
                            duration: (Appearance.animationsEnabled ?? true) ? 600 : 0
                            easing.type: Easing.OutCubic
                        }
                    }
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.topMargin: 18
                    anchors.bottomMargin: 18
                    spacing: 8

                    MaterialSymbol {
                        Layout.alignment: Qt.AlignHCenter
                        text: body.batCharging ? "battery_charging_full" : "battery_full"
                        iconSize: 30
                        color: body.sevColor(body.batSev)
                    }
                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: "Batería"
                        font.pixelSize: Appearance.font.pixelSize.large
                        font.weight: Font.DemiBold
                        color: body.colText
                    }
                    Item { Layout.fillHeight: true }
                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: body.batState
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: body.colMuted
                    }
                    RowLayout {
                        Layout.alignment: Qt.AlignHCenter
                        spacing: 0
                        MaterialSymbol {
                            visible: body.batCharging
                            text: "bolt"
                            iconSize: 22
                            color: body.sevColor(body.batSev)
                        }
                        StyledText {
                            text: body.batOk ? body.pct(body.batPct) : "—"
                            font.pixelSize: 28
                            font.weight: Font.Bold
                            color: body.colText
                        }
                    }
                }
            }
        }
    }
}
