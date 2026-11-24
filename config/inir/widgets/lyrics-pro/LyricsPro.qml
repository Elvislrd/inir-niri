// Lyrics Pro — custom iNiR desktop widget
// Second-generation lyrics display: karaoke fill on the active line, optional
// neon glow and a sync offset, on top of everything the previous Lyrics widget
// did (YTMusic/InnerTube first, LyricsService/LRCLIB fallback). Fully
// independent from the original "Lyrics" custom — both can coexist.

import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import qs
import qs.services
import qs.services.deferred
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.background.widgets

AbstractBackgroundWidget {
    id: root

    configEntryName: "custom.lyrics-pro"
    defaultConfig: ({
        placementStrategy: "free", widgetScale: 100, widgetOpacity: 100,
        colorMode: "auto", dim: 0,
        showBackground: false, useBlur: false, showBorder: false,
        backgroundOpacity: 0.16, borderWidth: 1, borderOpacity: 0.2, cornerRadius: -1,
        x: 630, y: 300,
        fontSize: 26, fontFamily: "theme", weight: "medium", italic: false,
        textCase: "normal", lineSpacing: 0.4, lines: 5, align: "center",
        scrollStyle: "smooth", activeScale: 1.18,
        karaoke: true, syncOffset: 0, glow: 55, accent: true, shadow: true,
        placeholder: true
    })

    // ── Config ────────────────────────────────────────────────
    readonly property int cfgFontSize: Math.max(10, Math.round(Number(root._readConfigKey("fontSize") ?? 26)))
    readonly property int cfgLines: Math.max(1, Math.min(9, Math.round(Number(root._readConfigKey("lines") ?? 5))))
    readonly property int cfgFalloff: Math.max(0, Math.floor((root.cfgLines - 1) / 2))
    readonly property string cfgWeight: String(root._readConfigKey("weight") ?? "medium")
    readonly property bool cfgItalic: Boolean(root._readConfigKey("italic") ?? false)
    readonly property string cfgCase: String(root._readConfigKey("textCase") ?? "normal")
    readonly property real cfgLineSpacing: Math.max(0, Number(root._readConfigKey("lineSpacing") ?? 0.4))
    readonly property string cfgAlign: String(root._readConfigKey("align") ?? "center")
    readonly property string cfgScroll: String(root._readConfigKey("scrollStyle") ?? "smooth")
    readonly property real cfgActiveScale: Math.max(1.0, Number(root._readConfigKey("activeScale") ?? 1.18))
    readonly property bool cfgKaraoke: Boolean(root._readConfigKey("karaoke") ?? true)
    readonly property real cfgSyncOffsetSec: Math.max(-3, Math.min(3,
        Number(root._readConfigKey("syncOffset") ?? 0) / 1000))
    readonly property real cfgGlow: {
        const v = Number(root._readConfigKey("glow") ?? 0)
        return Math.max(0, Math.min(1, (Number.isFinite(v) ? v : 0) / 100))
    }
    readonly property bool cfgAccent: Boolean(root._readConfigKey("accent") ?? true)
    readonly property bool cfgShadow: Boolean(root._readConfigKey("shadow") ?? true)
    readonly property bool cfgPlaceholder: Boolean(root._readConfigKey("placeholder") ?? true)
    readonly property string cfgFamilyRaw: String(root._readConfigKey("fontFamily") ?? "theme")
    readonly property string fontFamily: (root.cfgFamilyRaw === "" || root.cfgFamilyRaw === "theme")
        ? Appearance.font.family.main : root.cfgFamilyRaw

    function weightValue(): int {
        switch (root.cfgWeight) {
        case "light": return Font.Light;
        case "normal": return Font.Normal;
        case "medium": return Font.Medium;
        case "semibold": return Font.DemiBold;
        case "bold": return Font.Bold;
        case "black": return Font.Black;
        default: return Font.Medium;
        }
    }

    function applyCase(t: string): string {
        if (!t)
            return t;
        switch (root.cfgCase) {
        case "upper": return t.toUpperCase();
        case "lower": return t.toLowerCase();
        case "title": return t.replace(/\b\w/g, c => c.toUpperCase());
        default: return t;
        }
    }

    // Scroll/transition easing parameters
    readonly property bool _scrollInstant: root.cfgScroll === "instant"
    readonly property int scrollDuration: root._scrollInstant ? 0
        : root.cfgScroll === "fast" ? Appearance.animation.elementMoveFast.duration
        : Appearance.animation.elementMove.duration
    readonly property int scrollEase: root.cfgScroll === "linear" ? Easing.Linear
        : root.cfgScroll === "spring" ? Easing.OutBack
        : root.cfgScroll === "fast" ? Appearance.animation.elementMoveFast.type
        : Appearance.animation.elementMove.type
    readonly property var scrollBezier: root.cfgScroll === "fast"
        ? Appearance.animation.elementMoveFast.bezierCurve
        : Appearance.animation.elementMove.bezierCurve

    // ── Theme-adaptive colours ────────────────────────────────
    readonly property color inkColor: root.colText
    readonly property color activeInk: root.cfgAccent ? Appearance.colors.colPrimary : root.colText
    readonly property color karaokeBase: {
        const c = root.inkColor
        return Qt.rgba(c.r, c.g, c.b, 0.38)
    }
    readonly property color haloColor: ColorUtils.relativeLuminance(root.inkColor) > 0.5
        ? Qt.rgba(0, 0, 0, 0.55) : Qt.rgba(1, 1, 1, 0.65)
    readonly property int textAlign: root.cfgAlign === "left" ? Text.AlignLeft
        : root.cfgAlign === "right" ? Text.AlignRight : Text.AlignHCenter

    // ── Lyrics source: YouTube Music (InnerTube) first, LRCLIB fallback ──
    readonly property var itSynced: {
        const l = (typeof InnerTube !== "undefined") ? InnerTube.lyrics : null;
        const s = l ? l.synced : null;
        return (s && s.length > 0) ? s : null;
    }
    readonly property bool usingIt: root.itSynced !== null && root.itSynced !== undefined && MprisController.isYtMusicActive
    readonly property var lines: root.usingIt
        ? root.itSynced.map(x => ({ text: x.line ?? "", time: Number(x.t ?? 0) }))
        : LyricsService.lyricsLines
    readonly property bool hasLyrics: root.lines.length > 0

    // Ensure InnerTube has lyrics for the current YTMusic track
    property string _loadedVideoId: ""
    function ensureInnerTubeLyrics(): void {
        const vid = YtMusic.currentVideoId;
        if (!vid || vid === root._loadedVideoId)
            return;
        if (typeof InnerTube === "undefined" || !InnerTube.available)
            return;
        root._loadedVideoId = vid;
        InnerTube.loadLyrics(vid, YtMusic.currentTitle, YtMusic.currentArtist, YtMusic.currentDuration);
    }
    Connections {
        target: YtMusic
        function onCurrentVideoIdChanged() { root.ensureInnerTubeLyrics(); }
    }
    Connections {
        target: (typeof InnerTube !== "undefined") ? InnerTube : null
        function onAvailableChanged() { root.ensureInnerTubeLyrics(); }
    }

    // Fallback subscription for LRCLIB when YTMusic has no synced lyrics
    property bool _subscribed: false
    function syncSubscription(): void {
        const should = root.visible && !root.usingIt;
        if (should === root._subscribed)
            return;
        root._subscribed = should;
        if (should)
            LyricsService.subscribe();
        else
            LyricsService.unsubscribe();
    }
    onVisibleChanged: syncSubscription()
    onUsingItChanged: syncSubscription()
    Component.onCompleted: {
        ensureInnerTubeLyrics();
        syncSubscription();
    }
    Component.onDestruction: if (root._subscribed) {
        root._subscribed = false;
        LyricsService.unsubscribe();
    }

    // ── Playback position (anchored + extrapolated, like LyricsService) ──
    readonly property var _activePlayer: MprisController.activePlayer
    readonly property bool _playing: root._activePlayer?.isPlaying ?? false
    property real _posSample: -1
    property real _posSampleMs: 0
    property real posEstimate: -1

    function _rawPos(): real {
        if (root.usingIt) {
            const p = Number(YtMusic.currentPosition)
            return Number.isFinite(p) ? p : -1
        }
        if (typeof LyricsService._estimatedPosition === "function") {
            const p = Number(LyricsService._estimatedPosition())
            return Number.isFinite(p) ? p : -1
        }
        return -1
    }
    function _resample(): void {
        const raw = root._rawPos()
        if (!(raw >= 0))
            return
        const now = Date.now()
        if (!root._playing || raw !== root._posSample) {
            root._posSample = raw
            root._posSampleMs = now
        }
        root.posEstimate = root._playing
            ? root._posSample + (now - root._posSampleMs) / 1000
            : raw
    }
    Timer {
        id: posTicker
        interval: 150
        repeat: true
        running: root.visible && root.hasLyrics
        onTriggered: root._resample()
    }

    readonly property real effectivePos: root.posEstimate < 0 ? -1 : root.posEstimate + root.cfgSyncOffsetSec

    readonly property int displayActiveIdx: {
        if (root.effectivePos < 0) {
            if (root.usingIt) {
                const s = root.itSynced
                if (!s) return -1
                const pos = Number(YtMusic.currentPosition ?? 0)
                let idx = 0
                for (let i = 0; i < s.length; i++) {
                    if (s[i].t <= pos) idx = i
                    else break
                }
                return idx
            }
            return LyricsService.activeIndex
        }
        const arr = root.lines
        let idx = -1
        for (let i = 0; i < arr.length; i++) {
            if (Number(arr[i].time ?? 0) <= root.effectivePos) idx = i
            else break
        }
        return idx
    }

    // ── Karaoke fill ──────────────────────────────────────────
    function escHtml(s): string {
        return String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
    }
    function richLine(text, fillChars): string {
        const head = root.escHtml(String(text).slice(0, fillChars))
        const tail = root.escHtml(String(text).slice(fillChars))
        return "<font color=\"" + root.activeInk.toString() + "\">" + head + "</font>" + tail
    }
    function fillCharsFor(text, index): int {
        if (!root.cfgKaraoke || root.effectivePos < 0 || !text || text.length === 0 || text === "♪")
            return -1
        const arr = root.lines
        if (index < 0 || index >= arr.length)
            return -1
        const start = Number(arr[index].time ?? 0)
        let end
        if (index + 1 < arr.length) {
            end = Number(arr[index + 1].time ?? start)
        } else {
            const dur = Number(MprisController.lengthOf(root._activePlayer) ?? 0)
            end = (dur > start + 1) ? dur : start + 15
        }
        // Cap the fill so it does not stretch across instrumental gaps: the
        // karaoke should finish roughly when the voice does, not at the next line.
        const naturalSpan = Math.max(1.6, text.length * 0.26 + 0.7)
        const span = Math.max(0.8, Math.min(end - start, naturalSpan))
        const progress = Math.max(0, Math.min(1, (root.effectivePos - start) / span))
        return Math.max(0, Math.min(text.length, Math.floor(progress * text.length + 1e-4)))
    }

    // ── Geometry ──────────────────────────────────────────────
    implicitWidth: Math.round(660 * root.scaleFactor)
    implicitHeight: Math.round(root.cfgFontSize * root.cfgLines * (1.4 + root.cfgLineSpacing)) + Math.round(16 * root.scaleFactor)
    resizeMinWidth: 240
    resizeMinHeight: 80
    resizableAxes: ({ uniform: "widgetScale" })

    // ── Lyrics viewport ───────────────────────────────────────
    Item {
        id: viewport
        anchors.fill: parent
        clip: true
        opacity: root.hasLyrics ? 1 : 0
        visible: opacity > 0

        Behavior on opacity {
            enabled: Appearance.animationsEnabled && !root._scrollInstant
            NumberAnimation {
                duration: root.scrollDuration
                easing.type: root.scrollEase
                easing.bezierCurve: root.scrollBezier
            }
        }

        Column {
            id: lyricColumn
            width: Math.floor(viewport.width / Math.max(1, root.cfgActiveScale))
            x: root.textAlign === Text.AlignHCenter
                ? Math.round((viewport.width - width) / 2)
                : root.textAlign === Text.AlignRight ? viewport.width - width : 0
            spacing: Math.round(root.cfgFontSize * root.cfgLineSpacing)

            readonly property real targetY: {
                const count = lyricRepeater.count;
                if (count === 0)
                    return 0;
                const item = lyricRepeater.itemAt(Math.max(0, Math.min(root.displayActiveIdx, count - 1)));
                if (!item)
                    return 0;
                return Math.round(viewport.height / 2 - (item.y + item.height / 2));
            }
            y: targetY

            Behavior on y {
                enabled: Appearance.animationsEnabled && !root._scrollInstant
                NumberAnimation {
                    duration: root.scrollDuration
                    easing.type: root.scrollEase
                    easing.bezierCurve: root.scrollBezier
                }
            }

            Repeater {
                id: lyricRepeater
                model: root.lines

                delegate: Item {
                    id: lineWrap
                    required property int index
                    required property var modelData

                    readonly property string lineText: root.applyCase(
                        (lineWrap.modelData && lineWrap.modelData.text && lineWrap.modelData.text.length > 0)
                            ? lineWrap.modelData.text : "♪")
                    readonly property bool isActive: lineWrap.index === root.displayActiveIdx
                    readonly property int fillChars: lineWrap.isActive
                        ? root.fillCharsFor(lineWrap.lineText, lineWrap.index) : -1
                    readonly property bool karaokeActive: lineWrap.fillChars >= 0
                    readonly property int distance: Math.abs(lineWrap.index - root.displayActiveIdx)

                    width: lyricColumn.width
                    implicitHeight: lyricText.implicitHeight

                    transformOrigin: root.textAlign === Text.AlignHCenter ? Item.Center
                        : root.textAlign === Text.AlignRight ? Item.Right : Item.Left
                    scale: lineWrap.isActive ? root.cfgActiveScale : 1.0

                    opacity: {
                        if (lineWrap.isActive)
                            return 1.0;
                        if (lineWrap.distance > root.cfgFalloff)
                            return 0.0;
                        return Math.max(0.06, 0.55 - (lineWrap.distance - 1) * 0.16);
                    }

                    // Neon glow around the active line
                    layer.enabled: lineWrap.isActive && root.cfgGlow > 0.01
                    layer.effect: MultiEffect {
                        shadowEnabled: true
                        shadowColor: root.activeInk
                        shadowOpacity: Math.min(1, root.cfgGlow * 1.3)
                        shadowBlur: 0.35 + root.cfgGlow * 0.55
                        blurMax: Math.max(10, Math.round(22 * root.scaleFactor))
                        shadowHorizontalOffset: 0
                        shadowVerticalOffset: 0
                        autoPaddingEnabled: true
                    }

                    Text {
                        id: lyricText
                        width: parent.width
                        horizontalAlignment: root.textAlign
                        wrapMode: Text.WordWrap
                        maximumLineCount: 3
                        elide: Text.ElideRight
                        renderType: Text.QtRendering
                        textFormat: lineWrap.karaokeActive ? Text.RichText : Text.PlainText
                        text: lineWrap.karaokeActive
                            ? root.richLine(lineWrap.lineText, lineWrap.fillChars)
                            : lineWrap.lineText

                        font.pixelSize: root.cfgFontSize
                        font.family: root.fontFamily
                        font.weight: root.weightValue()
                        font.italic: root.cfgItalic
                        color: lineWrap.isActive
                            ? (lineWrap.karaokeActive ? root.karaokeBase : root.activeInk)
                            : root.inkColor
                        style: root.cfgShadow ? Text.Outline : Text.Normal
                        styleColor: root.cfgShadow ? root.haloColor : "transparent"
                    }

                    Behavior on opacity {
                        enabled: Appearance.animationsEnabled && !root._scrollInstant
                        NumberAnimation {
                            duration: root.scrollDuration
                            easing.type: root.scrollEase
                            easing.bezierCurve: root.scrollBezier
                        }
                    }
                    Behavior on scale {
                        enabled: Appearance.animationsEnabled && !root._scrollInstant
                        NumberAnimation {
                            duration: root.scrollDuration
                            easing.type: root.scrollEase
                            easing.bezierCurve: root.scrollBezier
                        }
                    }
                }
            }
        }
    }

    // ── Placeholder when there is nothing to show ─────────────
    Text {
        anchors.centerIn: parent
        visible: !root.hasLyrics && root.cfgPlaceholder
        text: "♪"
        font.pixelSize: root.cfgFontSize
        font.family: root.fontFamily
        color: root.inkColor
        opacity: 0.35
    }

    // ── Quick settings popover ────────────────────────────────
    editPopoverContent: Component {
        ColumnLayout {
            id: lyricsProQuickRoot
            readonly property string path: "background.widgets.custom.lyrics-pro."
            spacing: 14

            component ProSlider: WidgetQuickSlider {
                id: proSlider
                required property string key
                required property int minimum
                required property int maximum
                property int step: 5
                property real fallback: minimum
                property string suffix: ""
                property real scale: 1
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                Layout.maximumWidth: Number.POSITIVE_INFINITY
                from: proSlider.minimum
                to: proSlider.maximum
                stepSize: proSlider.step
                unit: proSlider.suffix
                value: {
                    const stored = Number(Config.getNestedValue("background.widgets.custom.lyrics-pro." + proSlider.key, proSlider.fallback / proSlider.scale))
                    const scaled = stored * proSlider.scale
                    return scaled >= proSlider.minimum && scaled <= proSlider.maximum ? scaled : proSlider.fallback
                }
                onCommitted: v => Config.setNestedValue("background.widgets.custom.lyrics-pro." + proSlider.key,
                    proSlider.scale === 1 ? Math.round(v) : Math.round(v) / proSlider.scale)
            }

            WidgetQuickSection {
                title: Translation.tr("Karaoke")
                WidgetQuickToggle {
                    iconName: "format_color_fill"
                    label: Translation.tr("Relleno karaoke")
                    checked: Config.getNestedValue(lyricsProQuickRoot.path + "karaoke", true)
                    onToggled: Config.setNestedValue(lyricsProQuickRoot.path + "karaoke", !checked)
                }
                ProSlider {
                    title: Translation.tr("Sincronía")
                    key: "syncOffset"
                    minimum: -3000
                    maximum: 3000
                    step: 25
                    fallback: 0
                    suffix: " ms"
                }
            }

            WidgetQuickSection {
                title: Translation.tr("Texto")
                ProSlider {
                    title: Translation.tr("Tamaño")
                    key: "fontSize"
                    minimum: 14
                    maximum: 56
                    step: 1
                    fallback: 26
                    suffix: " px"
                }
                ProSlider {
                    title: Translation.tr("Líneas visibles")
                    key: "lines"
                    minimum: 1
                    maximum: 9
                    step: 1
                    fallback: 5
                }
                ProSlider {
                    title: Translation.tr("Espaciado")
                    key: "lineSpacing"
                    minimum: 0
                    maximum: 150
                    step: 5
                    fallback: 40
                    suffix: "%"
                    scale: 100
                }
                WidgetQuickChoices {
                    maxColumns: 3
                    current: root.cfgFamilyRaw
                    model: [
                        { label: Translation.tr("Tema"), icon: "palette", value: "theme" },
                        { label: "Space Grotesk", icon: "font_download", value: "Space Grotesk" },
                        { label: "Inter", icon: "font_download", value: "Inter" },
                        { label: "JetBrains Mono", icon: "font_download", value: "JetBrains Mono" },
                        { label: "Noto Sans", icon: "font_download", value: "Noto Sans" },
                        { label: "Roboto", icon: "font_download", value: "Roboto" },
                        { label: "DejaVu Sans", icon: "font_download", value: "DejaVu Sans" },
                        { label: "Ubuntu", icon: "font_download", value: "Ubuntu" },
                        { label: "Segoe UI", icon: "font_download", value: "Segoe UI" },
                        { label: "Serif", icon: "font_download", value: "serif" },
                        { label: "Mono", icon: "font_download", value: "monospace" }
                    ]
                    onPicked: value => Config.setNestedValue(lyricsProQuickRoot.path + "fontFamily", value)
                }
                WidgetQuickToggle {
                    iconName: "music_note"
                    label: Translation.tr("Mostrar ♪")
                    checked: Config.getNestedValue(lyricsProQuickRoot.path + "placeholder", true)
                    onToggled: Config.setNestedValue(lyricsProQuickRoot.path + "placeholder", !checked)
                }
            }

            WidgetQuickSection {
                title: Translation.tr("Estilo")
                WidgetQuickChoices {
                    maxColumns: 3
                    current: root.cfgWeight
                    model: [
                        { label: Translation.tr("Fina"), icon: "format_bold", value: "light" },
                        { label: Translation.tr("Normal"), icon: "format_bold", value: "normal" },
                        { label: "Media", icon: "format_bold", value: "medium" },
                        { label: Translation.tr("Semi"), icon: "format_bold", value: "semibold" },
                        { label: Translation.tr("Negrita"), icon: "format_bold", value: "bold" },
                        { label: Translation.tr("Black"), icon: "format_bold", value: "black" }
                    ]
                    onPicked: value => Config.setNestedValue(lyricsProQuickRoot.path + "weight", value)
                }
                WidgetQuickChoices {
                    maxColumns: 4
                    current: root.cfgCase
                    model: [
                        { label: Translation.tr("Normal"), icon: "text_fields", value: "normal" },
                        { label: Translation.tr("MAYÚS"), icon: "keyboard_capslock", value: "upper" },
                        { label: Translation.tr("minús"), icon: "text_fields", value: "lower" },
                        { label: Translation.tr("Título"), icon: "text_fields", value: "title" }
                    ]
                    onPicked: value => Config.setNestedValue(lyricsProQuickRoot.path + "textCase", value)
                }
                WidgetQuickChoices {
                    maxColumns: 3
                    current: root.cfgAlign
                    model: [
                        { label: Translation.tr("Izquierda"), icon: "format_align_left", value: "left" },
                        { label: Translation.tr("Centro"), icon: "format_align_center", value: "center" },
                        { label: Translation.tr("Derecha"), icon: "format_align_right", value: "right" }
                    ]
                    onPicked: value => Config.setNestedValue(lyricsProQuickRoot.path + "align", value)
                }
                WidgetQuickToggle {
                    iconName: "format_italic"
                    label: Translation.tr("Cursiva")
                    checked: Config.getNestedValue(lyricsProQuickRoot.path + "italic", false)
                    onToggled: Config.setNestedValue(lyricsProQuickRoot.path + "italic", !checked)
                }
                WidgetQuickToggle {
                    iconName: "border_color"
                    label: Translation.tr("Contorno de texto")
                    checked: Config.getNestedValue(lyricsProQuickRoot.path + "shadow", true)
                    onToggled: Config.setNestedValue(lyricsProQuickRoot.path + "shadow", !checked)
                }
            }

            WidgetQuickSection {
                title: Translation.tr("Movimiento")
                WidgetQuickChoices {
                    maxColumns: 3
                    current: root.cfgScroll
                    model: [
                        { label: Translation.tr("Suave"), icon: "animation", value: "smooth" },
                        { label: Translation.tr("Rápido"), icon: "bolt", value: "fast" },
                        { label: Translation.tr("Resorte"), icon: "linear_scale", value: "spring" },
                        { label: Translation.tr("Lineal"), icon: "straighten", value: "linear" },
                        { label: Translation.tr("Instantáneo"), icon: "flash_on", value: "instant" }
                    ]
                    onPicked: value => Config.setNestedValue(lyricsProQuickRoot.path + "scrollStyle", value)
                }
                ProSlider {
                    title: Translation.tr("Escala de línea activa")
                    key: "activeScale"
                    minimum: 100
                    maximum: 200
                    step: 2
                    fallback: 118
                    suffix: "%"
                    scale: 100
                }
            }

            WidgetQuickSection {
                title: Translation.tr("Neón")
                ProSlider {
                    title: Translation.tr("Glow")
                    key: "glow"
                    minimum: 0
                    maximum: 100
                    step: 5
                    fallback: 55
                }
                WidgetQuickToggle {
                    iconName: "colors"
                    label: Translation.tr("Acento en la línea activa")
                    checked: Config.getNestedValue(lyricsProQuickRoot.path + "accent", true)
                    onToggled: Config.setNestedValue(lyricsProQuickRoot.path + "accent", !checked)
                }
            }
        }
    }
}
