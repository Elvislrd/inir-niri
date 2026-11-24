pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services
import Quickshell
import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import QtQuick.Effects

/**
 * ClockWidgetTooltip — Dashboard estilo Caelestia (740 x 388)
 *
 *  Clima · perfil + uptime · reloj vertical · calendario · aros de recursos · reproductor · gato bongo
 *
 *  Todo es interactivo (la línea de abajo explica cada cosa al pasar el mouse):
 *   · Clima ........ clic: alterna descripción / sensación térmica / humedad
 *   · Avatar ....... clic: alterna entorno / usuario · chip de batería: clic copia el %
 *   · Reloj ........ clic: 12 h / 24 h · clic derecho: copia la hora
 *   · Calendario ... ‹ › o rueda: cambiar de mes · clic en el título: hoy · clic en un día: seleccionarlo
 *                    doble clic: copia la fecha (AAAA-MM-DD)
 *   · Aros ......... clic o rueda: cambiar métrica (CPU↔GPU, RAM↔Swap, Disco↔Batería) · clic derecho: fijar %
 *   · Música ....... clic en la carátula: play/pausa · arrastra el arco: buscar · rueda: volumen
 *                    ⏮ ⏯ ⏭ · clic en el título: copia "artista – título"
 *   · Gato ......... clic: ¡bonk!  (también toca al ritmo cuando suena música)
 */
StyledPopup {
    id: root

    // ── Mantener el popup abierto mientras el mouse está encima (para poder hacer clic) ──
    property bool grace: false
    readonly property bool hovering: root.hoverTarget ? (root.hoverTarget.containsMouse ?? false) : false
    onHoveringChanged: {
        if (!root.hovering && !root.popupHovered) {
            root.grace = true;
            body.graceTimer.restart();
        } else {
            root.grace = false;
        }
    }
    onPopupHoveredChanged: {
        if (root.popupHovered) {
            root.grace = false;
        } else if (!root.hovering && root.active) {
            root.grace = true;
            body.graceTimer.restart();
        }
    }
    active: root.hoverActivates && root.hoverTarget && (root.hovering || root.popupHovered || root.grace)

    Item {
        id: body
        implicitWidth: 740
        implicitHeight: 388
        anchors.centerIn: parent

        property alias graceTimer: graceTimerObj

        readonly property bool live: root.active
        property var now: new Date()
        property bool hour12: true
        property int viewY: new Date().getFullYear()
        property int viewM: new Date().getMonth()
        property var selDate: new Date()
        property string toast: ""
        property var hoverOwner: null
        property int weatherMode: 0
        property int avatarMode: 0
        property int bonks: 0

        // ── Tokens de tema ───────────────────────────────────
        readonly property color colAccent: Appearance.colors.colPrimary
        readonly property color colAccent2: body.colAccent
        readonly property color colText: ColorUtils.mix("#ffffff", body.colAccent, 0.82)
        readonly property color colMuted: ColorUtils.applyAlpha(body.colText, 0.58)
        readonly property color colOnAccent: body.colAccent.hslLightness > 0.6 ? "#0d0d12" : "#ffffff"
        readonly property color colWarn: "#ffb454"
        readonly property color colCrit: Appearance.colors.colError

        // ── Modelo de tiempo ─────────────────────────────────
        readonly property int firstDow: Qt.locale().firstDayOfWeek
        readonly property int curY: body.now.getFullYear()
        readonly property int curM: body.now.getMonth()
        readonly property int curD: body.now.getDate()
        readonly property int hh: body.now.getHours()
        readonly property int mm: body.now.getMinutes()
        readonly property int ss: body.now.getSeconds()
        readonly property string hourStr: body.pad2(body.hour12 ? ((body.hh % 12) || 12) : body.hh)
        readonly property string minStr: body.pad2(body.mm)
        readonly property string ampm: body.hh < 12 ? "A.M." : "P.M."

        readonly property string monthTitle: body.cap(Qt.locale().monthName(body.viewM, Locale.LongFormat)) + " " + body.viewY
        readonly property var dowNames: {
            const out = [];
            for (let i = 0; i < 7; i++) {
                const idx = (body.firstDow + i) % 7;
                out.push(Qt.locale().dayName(idx, Locale.ShortFormat).replace(".", "").substring(0, 3).toLowerCase());
            }
            return out;
        }
        readonly property var cells: {
            const first = new Date(body.viewY, body.viewM, 1);
            const lead = (first.getDay() - body.firstDow + 7) % 7;
            const out = [];
            for (let i = 0; i < 42; i++) {
                const d = new Date(body.viewY, body.viewM, 1 - lead + i);
                out.push({ y: d.getFullYear(), m: d.getMonth(), d: d.getDate(), cur: d.getMonth() === body.viewM });
            }
            return out;
        }
        readonly property string selLine: {
            const d = body.selDate;
            return body.cap(Qt.locale().toString(d, "dddd d 'de' MMMM yyyy")) + "  ·  semana " + body.isoWeek(d) + "  ·  día " + body.dayOfYear(d) + " del año";
        }

        // ── Clima ────────────────────────────────────────────
        readonly property var wd: Weather.data ?? ({})
        readonly property string tempStr: {
            const t = body.wd.temp ?? body.wd.temperature;
            if (t === undefined || t === null || t === "")
                return "--°";
            const s = String(t);
            return s.indexOf("°") >= 0 ? s : s + "°C";
        }
        readonly property string weatherDesc: String(body.wd.description ?? body.wd.condition ?? body.wd.desc ?? body.wd.text ?? "")
        readonly property string weatherFeels: body.wd.tempFeelsLike !== undefined ? ("Sensación " + body.wd.tempFeelsLike) : ""
        readonly property string weatherHum: body.wd.humidity !== undefined ? ("Humedad " + body.wd.humidity + (String(body.wd.humidity).indexOf("%") >= 0 ? "" : "%")) : ""
        readonly property string weatherLine: {
            if (body.weatherMode === 1 && body.weatherFeels !== "")
                return body.weatherFeels;
            if (body.weatherMode === 2 && body.weatherHum !== "")
                return body.weatherHum;
            return body.weatherDesc !== "" ? body.weatherDesc : "Clima";
        }
        readonly property real nowMin: body.hh * 60 + body.mm
        readonly property real srMin: {
            const v = Weather._timeToMinutes(Weather.data?.sunrise);
            return v < 0 ? 360 : v;
        }
        readonly property real ssMin: {
            const v = Weather._timeToMinutes(Weather.data?.sunset);
            return v < 0 ? 1080 : v;
        }
        readonly property bool isDay: body.nowMin >= body.srMin && body.nowMin < body.ssMin
        readonly property string weatherIcon: {
            const d = body.weatherDesc.toLowerCase();
            if (d.indexOf("lluv") >= 0 || d.indexOf("rain") >= 0)
                return "rainy";
            if (d.indexOf("torment") >= 0 || d.indexOf("storm") >= 0)
                return "thunderstorm";
            if (d.indexOf("nub") >= 0 || d.indexOf("cloud") >= 0 || d.indexOf("nublado") >= 0)
                return "cloud";
            if (d.indexOf("nieve") >= 0 || d.indexOf("snow") >= 0)
                return "ac_unit";
            return body.isDay ? "wb_sunny" : "dark_mode";
        }

        // ── Sistema ──────────────────────────────────────────
        readonly property real cpu: ResourceUsage.cpuUsage ?? 0
        readonly property real gpu: ResourceUsage.gpuUsage ?? 0
        readonly property bool gpuOk: ResourceUsage.gpuUsageAvailable ?? false
        readonly property real ram: (ResourceUsage.memoryTotal ?? 0) > 0 ? ResourceUsage.memoryUsed / ResourceUsage.memoryTotal : 0
        readonly property real swap: (ResourceUsage.swapTotal ?? 0) > 0 ? ResourceUsage.swapUsed / ResourceUsage.swapTotal : 0
        readonly property bool swapOk: (ResourceUsage.swapTotal ?? 0) > 0
        readonly property real disk: (ResourceUsage.diskTotal ?? 0) > 0 ? ResourceUsage.diskUsed / ResourceUsage.diskTotal : 0
        readonly property bool batOk: Battery.available ?? false
        readonly property real bat: (Battery.percentage ?? 0) / 100

        readonly property var ringCpu: {
            const l = [{ label: "CPU", icon: "memory", v: body.cpu, warn: Config.options?.resources?.cpuWarningThreshold ?? 90,
                info: "CPU " + Math.round(body.cpu * 100) + "%  ·  " + Math.round(ResourceUsage.cpuTemp ?? 0) + " °C" }];
            if (body.gpuOk)
                l.push({ label: "GPU", icon: "developer_board", v: body.gpu, warn: Config.options?.resources?.gpuWarningThreshold ?? 90,
                    info: "GPU " + Math.round(body.gpu * 100) + "%  ·  " + Math.round(ResourceUsage.gpuTemp ?? 0) + " °C" });
            return l;
        }
        readonly property var ringRam: {
            const l = [{ label: "RAM", icon: "memory_alt", v: body.ram, warn: Config.options?.resources?.memoryWarningThreshold ?? 90,
                info: "RAM " + body.fmtBytes(ResourceUsage.memoryUsed ?? 0) + " / " + body.fmtBytes(ResourceUsage.memoryTotal ?? 0) }];
            if (body.swapOk)
                l.push({ label: "Swap", icon: "swap_horiz", v: body.swap, warn: 80,
                    info: "Swap " + body.fmtBytes(ResourceUsage.swapUsed ?? 0) + " / " + body.fmtBytes(ResourceUsage.swapTotal ?? 0) });
            return l;
        }
        readonly property var ringDisk: {
            const l = [{ label: "Disco", icon: "hard_drive", v: body.disk, warn: 90,
                info: "Disco " + body.fmtBytes(ResourceUsage.diskUsed ?? 0) + " / " + body.fmtBytes(ResourceUsage.diskTotal ?? 0) }];
            if (body.batOk)
                l.push({ label: "Batería", icon: (Battery.isCharging ?? false) ? "bolt" : "battery_full", v: body.bat, warn: -1,
                    info: "Batería " + Math.round(body.bat * 100) + "%" + ((Battery.isCharging ?? false) ? "  ·  cargando" : "") });
            return l;
        }

        // ── Música ───────────────────────────────────────────
        readonly property var player: MprisController.activePlayer
        readonly property bool playing: body.player?.isPlaying ?? false
        readonly property string trackTitle: body.player?.trackTitle ?? ""
        readonly property string trackArtist: body.player?.trackArtist ?? ""
        readonly property string trackAlbum: body.player?.trackAlbum ?? ""
        // Carátula: artUrlOf arregla las miniaturas de YouTube/Firefox y, si el
        // player no publica arte (mpv/ytmusic), se usa la del servicio YtMusic.
        readonly property string artUrl: {
            const direct = MprisController.artUrlOf(body.player) ?? ""
            return direct.length > 0 ? direct : (YtMusic.currentThumbnail ?? "")
        }
        readonly property real pos: body.player?.position ?? 0
        readonly property real len: body.player?.length ?? 0
        readonly property real mediaFrac: body.len > 0 ? Math.max(0, Math.min(1, body.pos / body.len)) : 0

        // ── Funciones ────────────────────────────────────────
        function cap(s) {
            const str = String(s ?? "");
            return str.length > 0 ? str.charAt(0).toUpperCase() + str.slice(1) : str;
        }
        function pad2(n) {
            return (n < 10 ? "0" : "") + Math.floor(n);
        }
        function fmtBytes(b) {
            const g = (b ?? 0) / 1073741824;
            return g >= 100 ? Math.round(g) + " GB" : g.toFixed(1) + " GB";
        }
        function fmtTime(sec) {
            const s = Math.max(0, Math.round(sec));
            return Math.floor(s / 60) + ":" + body.pad2(s % 60);
        }
        function isoWeek(d) {
            const t = new Date(Date.UTC(d.getFullYear(), d.getMonth(), d.getDate()));
            const dn = t.getUTCDay() || 7;
            t.setUTCDate(t.getUTCDate() + 4 - dn);
            const y0 = new Date(Date.UTC(t.getUTCFullYear(), 0, 1));
            return Math.ceil(((t - y0) / 86400000 + 1) / 7);
        }
        function dayOfYear(d) {
            return Math.round((new Date(d.getFullYear(), d.getMonth(), d.getDate()) - new Date(d.getFullYear(), 0, 0)) / 86400000);
        }
        function stateColor(v, warn) {
            if (warn < 0)
                return v <= 0.15 ? body.colCrit : (v <= 0.3 ? body.colWarn : body.colAccent2);
            const p = v * 100;
            if (p >= warn)
                return body.colCrit;
            if (p >= warn - 15)
                return body.colWarn;
            return body.colAccent2;
        }
        function showToast(s) {
            body.toast = s;
            toastTimer.restart();
        }
        function copy(txt, msg) {
            Quickshell.execDetached(["wl-copy", txt]);
            body.showToast(msg);
        }
        function hov(owner, on) {
            if (on)
                body.hoverOwner = owner;
            else if (body.hoverOwner === owner)
                body.hoverOwner = null;
        }
        function shiftMonth(n) {
            const d = new Date(body.viewY, body.viewM + n, 1);
            body.viewY = d.getFullYear();
            body.viewM = d.getMonth();
        }
        function goToday() {
            const n = new Date();
            body.now = n;
            body.viewY = n.getFullYear();
            body.viewM = n.getMonth();
            body.selDate = new Date(n.getFullYear(), n.getMonth(), n.getDate());
        }
        function togglePlay() {
            if (body.player && (body.player.canTogglePlaying ?? true))
                body.player.togglePlaying();
        }
        function seekTo(frac) {
            if (body.player && body.len > 0 && (body.player.canSeek ?? false)) {
                body.player.position = frac * body.len;
                body.showToast("⏩ " + body.fmtTime(frac * body.len) + " / " + body.fmtTime(body.len));
            }
        }
        function changeVolume(dv) {
            const p = body.player;
            if (p && (p.volumeSupported ?? false)) {
                p.volume = Math.max(0, Math.min(1, (p.volume ?? 0) + dv));
                body.showToast("🔊 Volumen " + Math.round(p.volume * 100) + "%");
            }
        }

        onLiveChanged: {
            if (body.live)
                body.goToday();
        }

        Timer {
            id: graceTimerObj
            interval: 400
            onTriggered: root.grace = false
        }
        Timer {
            id: toastTimer
            interval: 2200
            onTriggered: body.toast = ""
        }
        Timer {
            interval: 1000
            repeat: true
            running: body.live
            onTriggered: {
                body.now = new Date();
                if (body.playing && body.player)
                    body.player.positionChanged();
            }
        }

        // ═════════════════════ CLIMA ═════════════════════
        Item {
            id: weatherBlock
            x: 22
            y: 24
            width: 175
            height: 64
            property string infoText: "Clima · clic: cambiar detalle" + (body.weatherFeels !== "" ? "  ·  " + body.weatherFeels : "") + (body.weatherHum !== "" ? "  ·  " + body.weatherHum : "")
            scale: wMouse.containsMouse ? 1.04 : 1
            transformOrigin: Item.Left
            Behavior on scale {
                enabled: Appearance.animationsEnabled
                NumberAnimation { duration: 160; easing.type: Easing.OutBack }
            }

            MaterialSymbol {
                id: wIcon
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: body.weatherIcon
                iconSize: 46
                fill: 0
                color: body.colAccent2
            }
            ColumnLayout {
                anchors.left: wIcon.right
                anchors.leftMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                spacing: 0
                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: body.tempStr
                    font.pixelSize: 26
                    font.weight: Font.Bold
                    color: body.colAccent2
                }
                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: body.weatherLine
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: body.colText
                    elide: Text.ElideRight
                    Layout.maximumWidth: 100
                }
            }
            MouseArea {
                id: wMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onContainsMouseChanged: body.hov(weatherBlock, containsMouse)
                onClicked: body.weatherMode = (body.weatherMode + 1) % 3
            }
        }

        // ═════════════════════ PERFIL ═════════════════════
        Item {
            id: profile
            x: 214
            y: 14
            width: 220
            height: 90

            // Avatar
            Item {
                id: avatar
                x: 54
                y: 0
                width: 68
                height: 68
                property string infoText: "Clic: alternar entorno / usuario"
                scale: avMouse.containsMouse ? 1.07 : 1
                Behavior on scale {
                    enabled: Appearance.animationsEnabled
                    NumberAnimation { duration: 160; easing.type: Easing.OutBack }
                }
                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: ColorUtils.applyAlpha(body.colAccent, 0.22)
                    border.width: 2
                    border.color: ColorUtils.applyAlpha(body.colAccent2, 0.8)
                }
                Image {
                    id: faceImg
                    anchors.fill: parent
                    anchors.margins: 3
                    source: "file://" + Quickshell.env("HOME") + "/.face"
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    sourceSize: Qt.size(140, 140)
                    visible: false
                }
                Rectangle {
                    id: faceMask
                    anchors.fill: faceImg
                    radius: width / 2
                    visible: false
                }
                OpacityMask {
                    anchors.fill: faceImg
                    source: faceImg
                    maskSource: faceMask
                    visible: faceImg.status === Image.Ready
                }
                MaterialSymbol {
                    anchors.centerIn: parent
                    visible: faceImg.status !== Image.Ready
                    text: "account_circle"
                    iconSize: 44
                    fill: 0
                    color: body.colAccent2
                }
                MouseArea {
                    id: avMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onContainsMouseChanged: body.hov(avatar, containsMouse)
                    onClicked: body.avatarMode = (body.avatarMode + 1) % 2
                }
            }

            // Chip superior izquierdo: batería / energía
            Rectangle {
                id: batChip
                x: 8
                y: 6
                width: 30
                height: 30
                radius: 9
                property string infoText: body.batOk ? ("Batería " + Math.round(body.bat * 100) + "%" + ((Battery.isCharging ?? false) ? " · cargando" : "") + " · clic: copiar") : "Sin batería · conectado a la corriente"
                color: ColorUtils.applyAlpha(body.colAccent, batMouse.containsMouse ? 0.45 : 0.28)
                border.width: 1
                border.color: ColorUtils.applyAlpha(body.colAccent2, 0.5)
                scale: batMouse.containsMouse ? 1.1 : 1
                Behavior on scale {
                    enabled: Appearance.animationsEnabled
                    NumberAnimation { duration: 140; easing.type: Easing.OutBack }
                }
                MaterialSymbol {
                    anchors.centerIn: parent
                    text: !body.batOk ? "power" : ((Battery.isCharging ?? false) ? "bolt" : "battery_full")
                    iconSize: 18
                    fill: 0
                    color: body.colAccent2
                }
                MouseArea {
                    id: batMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onContainsMouseChanged: body.hov(batChip, containsMouse)
                    onClicked: {
                        if (body.batOk)
                            body.copy(Math.round(body.bat * 100) + "%", "Batería copiada");
                    }
                }
            }

            // Pastilla superior derecha: entorno / usuario
            Rectangle {
                id: deChip
                x: 134
                y: 2
                width: Math.min(86, deTxt.implicitWidth + 34)
                height: 24
                radius: 12
                property string deName: Quickshell.env("XDG_CURRENT_DESKTOP") || "Niri"
                property string userName: Quickshell.env("USER") || "usuario"
                property string infoText: "Clic: copiar \"" + (body.avatarMode === 0 ? deName : userName) + "\""
                color: ColorUtils.applyAlpha(body.colAccent, deMouse.containsMouse ? 0.36 : 0.2)
                MaterialSymbol {
                    x: 7
                    anchors.verticalCenter: parent.verticalCenter
                    text: body.avatarMode === 0 ? "terminal" : "person"
                    iconSize: 14
                    fill: 0
                    color: body.colText
                }
                StyledText {
                    id: deTxt
                    x: 25
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 30
                    text: body.avatarMode === 0 ? deChip.deName : deChip.userName
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: body.colText
                    elide: Text.ElideRight
                }
                MouseArea {
                    id: deMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onContainsMouseChanged: body.hov(deChip, containsMouse)
                    onClicked: body.copy(body.avatarMode === 0 ? deChip.deName : deChip.userName, "Copiado")
                }
            }

            // Uptime
            Item {
                id: upRow
                x: 0
                y: 70
                width: 220
                height: 22
                property string infoText: "Tiempo encendido · clic: copiar"
                Rectangle {
                    id: upChip
                    x: 4
                    width: 22
                    height: 22
                    radius: 7
                    color: ColorUtils.applyAlpha(body.colAccent, upMouse.containsMouse ? 0.45 : 0.25)
                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "schedule"
                        iconSize: 14
                        fill: 0
                        color: body.colAccent2
                    }
                }
                StyledText {
                    anchors.left: upChip.right
                    anchors.leftMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    text: "activo " + (DateTime.uptime ?? "")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: upMouse.containsMouse ? body.colAccent2 : body.colText
                }
                MouseArea {
                    id: upMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onContainsMouseChanged: body.hov(upRow, containsMouse)
                    onClicked: body.copy(String(DateTime.uptime ?? ""), "Uptime copiado")
                }
            }
        }

        // ═════════════════════ RELOJ VERTICAL ═════════════════════
        Item {
            id: vclock
            x: 22
            y: 118
            width: 62
            height: 160
            property string infoText: body.pad2(body.hh) + ":" + body.pad2(body.mm) + ":" + body.pad2(body.ss) + "  ·  clic: 12 h / 24 h  ·  clic derecho: copiar"
            scale: cMouse.containsMouse ? 1.05 : 1
            Behavior on scale {
                enabled: Appearance.animationsEnabled
                NumberAnimation { duration: 160; easing.type: Easing.OutBack }
            }
            Column {
                anchors.centerIn: parent
                spacing: 6
                StyledText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: body.hourStr
                    font.pixelSize: 36
                    font.weight: Font.Bold
                    font.features: { "tnum": 1 }
                    color: body.colText
                }
                Column {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 4
                    Repeater {
                        model: 3
                        Rectangle {
                            required property int index
                            width: 5
                            height: 5
                            radius: 2.5
                            color: body.colAccent2
                            opacity: (body.ss % 2 === 0) ? (index === 1 ? 1 : 0.55) : (index === 1 ? 0.55 : 1)
                            Behavior on opacity {
                                enabled: Appearance.animationsEnabled
                                NumberAnimation { duration: 350 }
                            }
                        }
                    }
                }
                StyledText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: body.minStr
                    font.pixelSize: 36
                    font.weight: Font.Bold
                    font.features: { "tnum": 1 }
                    color: body.colText
                }
                StyledText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: body.hour12 ? body.ampm : "24 H"
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.Medium
                    color: body.colAccent2
                }
            }
            MouseArea {
                id: cMouse
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                cursorShape: Qt.PointingHandCursor
                onContainsMouseChanged: body.hov(vclock, containsMouse)
                onClicked: mouse => {
                    if (mouse.button === Qt.RightButton)
                        body.copy(body.pad2(body.hh) + ":" + body.pad2(body.mm), "Hora copiada");
                    else
                        body.hour12 = !body.hour12;
                }
            }
        }

        // ═════════════════════ CALENDARIO ═════════════════════
        Item {
            id: cal
            x: 98
            y: 104
            width: 260
            height: 240

            WheelHandler {
                onWheel: event => body.shiftMonth(event.angleDelta.y > 0 ? -1 : 1)
            }

            // Encabezado
            Item {
                id: calHead
                width: parent.width
                height: 26
                NavButton {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    label: "‹"
                    onClicked: body.shiftMonth(-1)
                    onHoveredChanged: body.hov(prevInfo, hovered)
                }
                NavButton {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    label: "›"
                    onClicked: body.shiftMonth(1)
                    onHoveredChanged: body.hov(nextInfo, hovered)
                }
                Item {
                    id: titleArea
                    anchors.centerIn: parent
                    width: 150
                    height: 24
                    property string infoText: "Clic: volver a hoy  ·  rueda: cambiar de mes"
                    StyledText {
                        anchors.centerIn: parent
                        text: body.monthTitle
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.Bold
                        color: titleMouse.containsMouse ? body.colAccent2 : body.colText
                    }
                    MouseArea {
                        id: titleMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        cursorShape: Qt.PointingHandCursor
                        onContainsMouseChanged: body.hov(titleArea, containsMouse)
                        onClicked: body.goToday()
                    }
                }
                QtObject {
                    id: prevInfo
                    property string infoText: "Mes anterior"
                }
                QtObject {
                    id: nextInfo
                    property string infoText: "Mes siguiente"
                }
            }

            // Días de la semana
            Row {
                y: 30
                Repeater {
                    model: body.dowNames
                    StyledText {
                        required property string modelData
                        width: 260 / 7
                        horizontalAlignment: Text.AlignHCenter
                        text: modelData
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: Font.DemiBold
                        color: body.colText
                    }
                }
            }

            // Cuadrícula
            Grid {
                y: 54
                columns: 7
                rowSpacing: 2
                columnSpacing: 0
                Repeater {
                    model: body.cells
                    Item {
                        id: cell
                        required property var modelData
                        readonly property bool isToday: modelData.y === body.curY && modelData.m === body.curM && modelData.d === body.curD
                        readonly property bool isSel: modelData.y === body.selDate.getFullYear() && modelData.m === body.selDate.getMonth() && modelData.d === body.selDate.getDate()
                        property string infoText: body.cap(Qt.locale().toString(new Date(modelData.y, modelData.m, modelData.d), "dddd d 'de' MMMM")) + "  ·  clic: seleccionar  ·  doble clic: copiar fecha"
                        width: 260 / 7
                        height: 30

                        Rectangle {
                            anchors.centerIn: parent
                            width: 28
                            height: 28
                            radius: cell.isToday ? 10 : 14
                            color: cell.isToday ? ColorUtils.applyAlpha(body.colAccent, 0.75)
                                : (dMouse.containsMouse ? ColorUtils.applyAlpha(body.colAccent, 0.2) : "transparent")
                            border.width: cell.isSel && !cell.isToday ? 1.5 : 0
                            border.color: body.colAccent2
                            scale: dMouse.containsMouse ? 1.12 : 1
                            Behavior on scale {
                                enabled: Appearance.animationsEnabled
                                NumberAnimation { duration: 130; easing.type: Easing.OutBack }
                            }
                            Behavior on color {
                                enabled: Appearance.animationsEnabled
                                ColorAnimation { duration: 130 }
                            }
                        }
                        StyledText {
                            anchors.centerIn: parent
                            text: cell.modelData.d
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: cell.isToday || cell.isSel ? Font.Bold : Font.Normal
                            font.features: { "tnum": 1 }
                            color: cell.isToday ? body.colOnAccent : (cell.modelData.cur ? body.colText : ColorUtils.applyAlpha(body.colText, 0.3))
                        }
                        MouseArea {
                            id: dMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onContainsMouseChanged: body.hov(cell, containsMouse)
                            onClicked: {
                                body.selDate = new Date(cell.modelData.y, cell.modelData.m, cell.modelData.d);
                                if (!cell.modelData.cur) {
                                    body.viewY = cell.modelData.y;
                                    body.viewM = cell.modelData.m;
                                }
                            }
                            onDoubleClicked: body.copy(Qt.formatDate(new Date(cell.modelData.y, cell.modelData.m, cell.modelData.d), "yyyy-MM-dd"), "Fecha copiada")
                        }
                    }
                }
            }
        }

        // ═════════════════════ AROS DE RECURSOS ═════════════════════
        Column {
            id: ringsCol
            x: 382
            y: 106
            spacing: 14
            Ring { items: body.ringCpu }
            Ring { items: body.ringRam }
            Ring { items: body.ringDisk }
        }

        // ═════════════════════ MÚSICA ═════════════════════
        Item {
            id: media
            x: 462
            y: 14
            width: 256
            height: 240

            // Aro de progreso + carátula
            Item {
                id: artArea
                anchors.horizontalCenter: parent.horizontalCenter
                width: 118
                height: 118
                property string infoText: (body.player
                    ? body.fmtTime(artMouse.seeking ? artMouse.dragFrac * body.len : body.pos) + " / " + body.fmtTime(body.len) + "  ·  arrastra el aro: buscar  ·  clic: play/pausa  ·  rueda: volumen"
                    : "Sin reproductor activo")
                scale: artMouse.containsMouse ? 1.03 : 1
                Behavior on scale {
                    enabled: Appearance.animationsEnabled
                    NumberAnimation { duration: 160; easing.type: Easing.OutBack }
                }

                // Progreso: arco tipo eclipse encima del álbum
                Canvas {
                    id: progArc
                    anchors.fill: parent
                    z: 5
                    antialiasing: true
                    readonly property real frac: artMouse.seeking ? artMouse.dragFrac : body.mediaFrac
                    onFracChanged: requestPaint()
                    onWidthChanged: requestPaint()
                    onHeightChanged: requestPaint()
                    Connections {
                        target: body
                        function onColAccentChanged() { progArc.requestPaint(); }
                    }
                    onPaint: {
                        const ctx = getContext("2d");
                        ctx.reset();
                        const cx = width / 2, cy = height / 2;
                        const r = Math.min(width, height) * 0.475;
                        const a0 = Math.PI, a1 = Math.PI * 2;
                        ctx.lineWidth = 5;
                        ctx.lineCap = "round";
                        ctx.strokeStyle = Qt.rgba(body.colAccent.r, body.colAccent.g, body.colAccent.b, 0.22);
                        ctx.beginPath();
                        ctx.arc(cx, cy, r, a0, a1);
                        ctx.stroke();
                        const f = Math.max(0.01, Math.min(1, progArc.frac));
                        ctx.strokeStyle = body.colAccent2;
                        ctx.beginPath();
                        ctx.arc(cx, cy, r, a0, a0 + (a1 - a0) * f);
                        ctx.stroke();
                    }
                }
                Item {
                    id: artWrap
                    anchors.centerIn: parent
                    width: 76
                    height: 76
                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: -4
                        radius: 24
                        color: "transparent"
                        border.width: 1.5
                        border.color: ColorUtils.applyAlpha(body.colAccent2, 0.55)
                        antialiasing: true
                        z: 2
                    }
                    Image {
                        id: artImg
                        anchors.fill: parent
                        source: body.artUrl
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        sourceSize: Qt.size(200, 200)
                        visible: false
                    }
                    Rectangle {
                        id: artMask
                        anchors.fill: parent
                        radius: 16
                        visible: false
                    }
                    OpacityMask {
                        anchors.fill: parent
                        source: artImg
                        maskSource: artMask
                        visible: artImg.status === Image.Ready
                    }
                    Rectangle {
                        anchors.fill: parent
                        radius: 16
                        visible: artImg.status !== Image.Ready
                        color: ColorUtils.applyAlpha(body.colAccent, 0.2)
                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "music_note"
                            iconSize: 38
                            fill: 0
                            color: body.colAccent2
                        }
                    }
                    // icono de pausa al pasar el mouse
                    Rectangle {
                        anchors.fill: parent
                        radius: 16
                        color: "#66000000"
                        opacity: artMouse.containsMouse && !artMouse.seeking && artMouse.inside ? 1 : 0
                        Behavior on opacity {
                            enabled: Appearance.animationsEnabled
                            NumberAnimation { duration: 140 }
                        }
                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: body.playing ? "pause" : "play_arrow"
                            iconSize: 34
                            fill: 1
                            color: "#ffffff"
                        }
                    }
                }
                MouseArea {
                    id: artMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    property bool seeking: false
                    property real dragFrac: 0
                    property bool inside: true
                    function dist(mx, my) {
                        return Math.hypot(mx - width / 2, my - height / 2);
                    }
                    function fracAt(mx, my) {
                        let a = Math.atan2(my - height / 2, mx - width / 2);
                        if (a > 0) a -= Math.PI * 2;
                        return Math.max(0, Math.min(1, (a + Math.PI) / Math.PI));
                    }
                    cursorShape: Qt.PointingHandCursor
                    onContainsMouseChanged: body.hov(artArea, containsMouse)
                    onPressed: mouse => {
                        if (mouse.y < height / 2 && dist(mouse.x, mouse.y) > 42) {
                            seeking = true;
                            dragFrac = fracAt(mouse.x, mouse.y);
                        }
                    }
                    onPositionChanged: mouse => {
                        inside = dist(mouse.x, mouse.y) <= 42;
                        if (seeking)
                            dragFrac = fracAt(mouse.x, mouse.y);
                    }
                    onReleased: mouse => {
                        if (seeking) {
                            seeking = false;
                            body.seekTo(dragFrac);
                        } else {
                            body.togglePlay();
                        }
                    }
                    onCanceled: seeking = false
                    onWheel: wheel => body.changeVolume(wheel.angleDelta.y > 0 ? 0.05 : -0.05)
                }
            }

            // Título / artista / álbum
            Item {
                id: titleBlock
                y: 126
                width: parent.width
                height: 58
                property string infoText: body.trackTitle !== "" ? "Clic: copiar \"" + body.trackArtist + " – " + body.trackTitle + "\"" : "Nada sonando"
                Column {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: parent.width - 8
                    spacing: 1
                    StyledText {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: body.trackTitle !== "" ? body.trackTitle : "Sin reproducción"
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.weight: Font.Bold
                        color: tMouse.containsMouse ? body.colAccent2 : body.colText
                        elide: Text.ElideRight
                    }
                    StyledText {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: body.trackArtist
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: body.colMuted
                        elide: Text.ElideRight
                    }
                    StyledText {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: body.trackAlbum
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: body.colText
                        elide: Text.ElideRight
                    }
                }
                MouseArea {
                    id: tMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onContainsMouseChanged: body.hov(titleBlock, containsMouse)
                    onClicked: {
                        if (body.trackTitle !== "")
                            body.copy(body.trackArtist + " – " + body.trackTitle, "Canción copiada");
                    }
                }
            }

            // Controles
            Row {
                id: controls
                y: 190
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 8
                MediaBtn {
                    icon: "skip_previous"
                    w: 38
                    tip: "Anterior"
                    onActivated: {
                        if (body.player)
                            body.player.previous();
                    }
                }
                MediaBtn {
                    icon: body.playing ? "pause" : "play_arrow"
                    w: 58
                    strong: true
                    tip: body.playing ? "Pausar" : "Reproducir"
                    onActivated: body.togglePlay()
                }
                MediaBtn {
                    icon: "skip_next"
                    w: 38
                    tip: "Siguiente"
                    onActivated: {
                        if (body.player)
                            body.player.next();
                    }
                }
            }
        }

        // ═════════════════════ GATO BONGO (GIF) ═════════════════════
        AnimatedImage {
            id: catGif
            x: 520
            y: 254
            width: 140
            height: 104
            source: "file://" + Quickshell.env("HOME") + "/.config/quickshell/caelestia/assets/bongocat.gif"
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            cache: false
            playing: true
            smooth: true
            layer.enabled: true
            layer.effect: MultiEffect {
                colorization: 1.0
                colorizationColor: body.colAccent2
            }
            scale: catMouse.containsMouse ? 1.05 : 1
            transformOrigin: Item.Bottom
            Behavior on scale {
                enabled: Appearance.animationsEnabled
                NumberAnimation { duration: 160; easing.type: Easing.OutBack }
            }
            MouseArea {
                id: catMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    body.bonks++;
                    body.showToast("Clic: ¡bonk!  (" + body.bonks + " bonks)");
                }
            }
        }

        // ═════════════════════ LÍNEA DE ESTADO ═════════════════════
        StyledText {
            x: 22
            y: 356
            width: 696
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            text: body.toast !== "" ? body.toast : body.selLine
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: body.toast !== "" ? body.colAccent2 : body.colMuted
        }
    }

    // ═════════════════════ COMPONENTES ═════════════════════

    // Aro de progreso con métricas intercambiables
    component Ring: Item {
        id: rg
        property var items: []
        property int idx: 0
        property bool pinPct: false
        readonly property var cur: rg.items.length > 0 ? rg.items[rg.idx % rg.items.length] : ({ label: "", icon: "help", v: 0, warn: 90, info: "" })
        readonly property color tint: body.stateColor(rg.cur.v, rg.cur.warn)
        property real shown: rg.cur.v
        readonly property bool hov: rMouse.containsMouse
        property string infoText: rg.cur.info + (rg.items.length > 1 ? "  ·  clic: cambiar métrica" : "") + "  ·  clic derecho: fijar %"
        width: 58
        height: 58
        scale: rg.hov ? 1.08 : 1

        Behavior on scale {
            enabled: Appearance.animationsEnabled
            NumberAnimation { duration: 160; easing.type: Easing.OutBack }
        }
        Behavior on shown {
            enabled: Appearance.animationsEnabled
            NumberAnimation { duration: 600; easing.type: Easing.OutCubic }
        }
        onShownChanged: rcv.requestPaint()
        onTintChanged: rcv.requestPaint()

        Canvas {
            id: rcv
            anchors.fill: parent
            antialiasing: true
            onPaint: {
                const ctx = getContext("2d");
                ctx.reset();
                const c = width / 2, r = c - 5;
                const t = rg.tint;
                ctx.lineWidth = 5;
                ctx.lineCap = "round";
                ctx.strokeStyle = Qt.rgba(t.r, t.g, t.b, 0.2);
                ctx.beginPath();
                ctx.arc(c, c, r, 0, Math.PI * 2);
                ctx.stroke();
                ctx.strokeStyle = t;
                ctx.beginPath();
                ctx.arc(c, c, r, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * Math.max(0.03, Math.min(1, rg.shown)));
                ctx.stroke();
            }
        }
        MaterialSymbol {
            anchors.centerIn: parent
            visible: !(rg.hov || rg.pinPct)
            text: rg.cur.icon
            iconSize: 24
            fill: 0
            color: rg.tint
        }
        StyledText {
            anchors.centerIn: parent
            visible: rg.hov || rg.pinPct
            text: Math.round(rg.cur.v * 100) + "%"
            font.pixelSize: Appearance.font.pixelSize.small
            font.weight: Font.Bold
            font.features: { "tnum": 1 }
            color: body.colText
        }
        MouseArea {
            id: rMouse
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            cursorShape: Qt.PointingHandCursor
            onContainsMouseChanged: body.hov(rg, containsMouse)
            onClicked: mouse => {
                if (mouse.button === Qt.RightButton)
                    rg.pinPct = !rg.pinPct;
                else if (rg.items.length > 1)
                    rg.idx = (rg.idx + 1) % rg.items.length;
            }
            onWheel: wheel => {
                if (rg.items.length > 1)
                    rg.idx = (rg.idx + (wheel.angleDelta.y > 0 ? 1 : rg.items.length - 1)) % rg.items.length;
            }
        }
    }

    // Botón de reproductor
    component MediaBtn: Rectangle {
        id: mb
        property string icon: ""
        property real w: 38
        property bool strong: false
        property string tip: ""
        property string infoText: mb.tip
        signal activated
        width: mb.w
        height: 28
        radius: 14
        color: mb.strong ? (mbMouse.containsMouse ? body.colAccent2 : body.colAccent)
            : ColorUtils.applyAlpha(body.colAccent, mbMouse.containsMouse ? 0.4 : 0.2)
        scale: mbMouse.pressed ? 0.92 : (mbMouse.containsMouse ? 1.08 : 1)
        Behavior on scale {
            enabled: Appearance.animationsEnabled
            NumberAnimation { duration: 120; easing.type: Easing.OutBack }
        }
        MaterialSymbol {
            anchors.centerIn: parent
            text: mb.icon
            iconSize: 20
            fill: 1
            color: mb.strong ? body.colOnAccent : body.colText
        }
        MouseArea {
            id: mbMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onContainsMouseChanged: body.hov(mb, containsMouse)
            onClicked: mb.activated()
        }
    }

    // Botones ‹ ›
    component NavButton: Rectangle {
        id: nav
        property string label: ""
        readonly property bool hovered: navMouse.containsMouse
        signal clicked
        implicitWidth: 26
        implicitHeight: 26
        radius: 13
        color: nav.hovered ? ColorUtils.applyAlpha(body.colAccent, 0.28) : "transparent"
        scale: nav.hovered ? 1.12 : 1
        Behavior on scale {
            enabled: Appearance.animationsEnabled
            NumberAnimation { duration: 140; easing.type: Easing.OutBack }
        }
        StyledText {
            anchors.centerIn: parent
            text: nav.label
            font.pixelSize: Appearance.font.pixelSize.large
            color: body.colText
        }
        MouseArea {
            id: navMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: nav.clicked()
        }
    }

    // Gato bongo: toca al ritmo de la música y hace "bonk" al hacer clic
    component Cat: Item {
        id: ct
        property bool bonking: false
        property real liftL: 0
        property real liftR: 0
        property string infoText: "Clic: ¡bonk!  (" + body.bonks + " bonks)"
        readonly property int mood: ct.bonking ? 2 : (body.playing ? 1 : 0)
        property bool nextLeft: true

        scale: cMouse2.containsMouse ? 1.05 : 1
        transformOrigin: Item.Bottom
        Behavior on scale {
            enabled: Appearance.animationsEnabled
            NumberAnimation { duration: 160; easing.type: Easing.OutBack }
        }
        onMoodChanged: head.requestPaint()

        function bonk(left) {
            ct.bonking = true;
            bonkReset.restart();
            if (left)
                lAnim.restart();
            else
                rAnim.restart();
        }

        Canvas {
            id: head
            anchors.fill: parent
            antialiasing: true
            Connections {
                target: body
                function onColAccentChanged() { head.requestPaint(); }
            }
            onPaint: {
                const ctx = getContext("2d");
                ctx.reset();
                const w = width;
                const fillC = body.colAccent2;
                const dark = body.colOnAccent;
                ctx.fillStyle = fillC;
                // orejas
                ctx.beginPath();
                ctx.moveTo(w * 0.10, 34);
                ctx.lineTo(w * 0.16, 4);
                ctx.lineTo(w * 0.40, 26);
                ctx.closePath();
                ctx.fill();
                ctx.beginPath();
                ctx.moveTo(w * 0.90, 34);
                ctx.lineTo(w * 0.84, 4);
                ctx.lineTo(w * 0.60, 26);
                ctx.closePath();
                ctx.fill();
                // cabeza
                ctx.beginPath();
                ctx.roundedRect(2, 20, w - 4, 54, 26, 26);
                ctx.fill();
                // cara
                ctx.strokeStyle = dark;
                ctx.lineWidth = 3;
                ctx.lineCap = "round";
                const ey = 44, ex1 = w * 0.30, ex2 = w * 0.70;
                if (ct.mood === 1) {
                    ctx.beginPath(); ctx.arc(ex1, ey + 3, 6, Math.PI * 1.1, Math.PI * 1.9); ctx.stroke();
                    ctx.beginPath(); ctx.arc(ex2, ey + 3, 6, Math.PI * 1.1, Math.PI * 1.9); ctx.stroke();
                } else if (ct.mood === 2) {
                    ctx.beginPath(); ctx.moveTo(ex1 - 5, ey - 5); ctx.lineTo(ex1 + 4, ey); ctx.lineTo(ex1 - 5, ey + 5); ctx.stroke();
                    ctx.beginPath(); ctx.moveTo(ex2 + 5, ey - 5); ctx.lineTo(ex2 - 4, ey); ctx.lineTo(ex2 + 5, ey + 5); ctx.stroke();
                } else {
                    ctx.beginPath(); ctx.moveTo(ex1 - 6, ey); ctx.lineTo(ex1 + 6, ey); ctx.stroke();
                    ctx.beginPath(); ctx.moveTo(ex2 - 6, ey); ctx.lineTo(ex2 + 6, ey); ctx.stroke();
                }
                // boca "w"
                const mx = w / 2, my = 54;
                ctx.beginPath(); ctx.arc(mx - 5, my, 5, 0.1 * Math.PI, 0.9 * Math.PI); ctx.stroke();
                ctx.beginPath(); ctx.arc(mx + 5, my, 5, 0.1 * Math.PI, 0.9 * Math.PI); ctx.stroke();
            }
        }

        // patas
        Rectangle {
            x: ct.width * 0.14
            y: ct.height - 22 - ct.liftL * 14
            width: 38
            height: 22
            radius: 11
            color: body.colAccent2
            border.width: 2
            border.color: body.colOnAccent
        }
        Rectangle {
            x: ct.width * 0.86 - 38
            y: ct.height - 22 - ct.liftR * 14
            width: 38
            height: 22
            radius: 11
            color: body.colAccent2
            border.width: 2
            border.color: body.colOnAccent
        }

        SequentialAnimation {
            id: lAnim
            NumberAnimation { target: ct; property: "liftL"; to: 1; duration: 70; easing.type: Easing.OutQuad }
            NumberAnimation { target: ct; property: "liftL"; to: 0; duration: 110; easing.type: Easing.InQuad }
        }
        SequentialAnimation {
            id: rAnim
            NumberAnimation { target: ct; property: "liftR"; to: 1; duration: 70; easing.type: Easing.OutQuad }
            NumberAnimation { target: ct; property: "liftR"; to: 0; duration: 110; easing.type: Easing.InQuad }
        }
        Timer {
            id: bonkReset
            interval: 220
            onTriggered: ct.bonking = false
        }
        // toca al ritmo cuando suena música
        Timer {
            interval: 420
            repeat: true
            running: body.live && body.playing
            onTriggered: {
                ct.bonk(ct.nextLeft);
                ct.nextLeft = !ct.nextLeft;
            }
        }

        MouseArea {
            id: cMouse2
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onContainsMouseChanged: body.hov(ct, containsMouse)
            onClicked: mouse => {
                body.bonks++;
                ct.bonk(mouse.x < ct.width / 2);
                body.showToast(body.bonks % 10 === 0 ? "¡miau! 🐾 " + body.bonks + " bonks" : "bonk!");
            }
        }
    }
}
