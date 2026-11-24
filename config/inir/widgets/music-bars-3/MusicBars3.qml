pragma ComponentBehavior: Bound

// Music Bars 3 — custom iNiR desktop widget
// Independent twin of the built-in Visualizer: bars, wave and organic modes,
// with its own settings under background.widgets.custom.music-bars-3.

import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Services.Mpris
import Quickshell.Widgets
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.models
import qs.modules.common.widgets
import qs.modules.background.widgets

AbstractBackgroundWidget {
    id: root

    configEntryName: "custom.music-bars-3"
    defaultConfig: ({
        placementStrategy: "free", preset: "default", vizType: "bars", waveOpacity: -1,
        paletteMode: "cava", barsOrigin: "bottom", waveMode: "fill",
        frequencyProfile: "flat", smoothing: 2, fillRatio: 90, barOpacity: 100,
        organicSensitivity: 25, organicPulse: 150, organicMotionSpeed: 250, organicIdleMotion: 18,
        organicOpacity: 100, organicGlow: 100, organicCoverSize: 51, organicRange: 20,
        organicCompression: 0,
        barCount: 48, barSpacing: 2, barRadius: 2, barMinHeight: 1,
        lineWidth: 2, edgeInset: 0, edgeSoftness: 28, accentStrength: 70,
        contentWidth: 304, contentHeight: 104, dim: 0,
        widgetScale: 100, widgetOpacity: 100, colorMode: "auto",
        showBackground: false, useBlur: false, showBorder: false,
        backgroundOpacity: 0.16, borderWidth: 1, borderOpacity: 0.2,
        cornerRadius: -1, x: 640, y: 560, rotation: 0, glow: 65
    })

    visibleWhenLocked: false
    needsColText: true
    resizableAxes: ({ width: "contentWidth", height: "contentHeight" })
    resizeMinWidth: 120
    resizeMinHeight: 48

    // ── Orientation ────────────────────────────────────────────
    // Stored contentWidth/contentHeight are always the physical on-screen box;
    // rotation turns the visual inside it. Picking vertical swaps the stored
    // width/height in the popover so the widget becomes tall/wide.
    readonly property int rotationSetting: {
        const v = Number(root._readConfigKey("rotation") ?? 0)
        return (v === 90 || v === 180 || v === 270) ? v : 0
    }
    readonly property bool verticalOrientation: root.rotationSetting === 90
        || root.rotationSetting === 270

    // ── Neon glow ──────────────────────────────────────────────
    // A zero-offset shadow drawn around the whole visual (see rotCanvas):
    // the bars/wave get a neon halo in the palette's first colour.
    readonly property real glowAmount: {
        const v = Number(root._readConfigKey("glow") ?? 0)
        return Math.max(0, Math.min(1, (Number.isFinite(v) ? v : 0) / 100))
    }
    readonly property color glowColor: {
        const pal = root.spectrumPalette
        if (pal && pal.length > 0)
            return pal[0]
        return root.widgetAccentVisible
    }

    readonly property string vizType: Config.getNestedValue("background.widgets.custom.music-bars-3.vizType", "bars")
    readonly property int waveOpacity: Config.getNestedValue("background.widgets.custom.music-bars-3.waveOpacity", -1)
    readonly property string paletteMode: Config.getNestedValue(
        "background.widgets.custom.music-bars-3.paletteMode", "cava")
    // Album is artwork-owned, so the shared semantic palette editor is only
    // relevant for the widget semantic color modes.
    semanticPaletteQuickControls: root.paletteMode === "accent"
        || root.paletteMode === "primary"
    readonly property var spectrumPalette: {
        // iRiS draws its widgets from one solved palette; Cava's colours are Material's.
        if (root.paletteMode === "accent" || (root.widgetIris && root.paletteMode === "cava"))
            return [root.widgetAccentVisible, root.widgetAccent2Visible, root.widgetAccent3Visible]
        if (root.paletteMode === "primary")
            return [root.widgetAccent]
        if (root.paletteMode === "album") {
            const colors = albumArtworkQuantizer?.colors ?? []
            if (colors.length > 0)
                return colors
            return [root.widgetAccentVisible, root.widgetAccent2Visible, root.widgetAccent3Visible]
        }
        return CavaTheme.visualizerColors
    }
    readonly property int smoothing: Config.getNestedValue(
        "background.widgets.custom.music-bars-3.smoothing", 2)
    readonly property string frequencyProfile: Config.getNestedValue(
        "background.widgets.custom.music-bars-3.frequencyProfile", "flat")
    readonly property real accentStrength: Config.getNestedValue(
        "background.widgets.custom.music-bars-3.accentStrength", 70) / 100
    readonly property real organicSensitivitySetting: Config.getNestedValue(
        "background.widgets.custom.music-bars-3.organicSensitivity", 25) / 100
    // Keep the useful low end almost linear, then progressively compress the
    // upper half. The raw 25-200 slider used to multiply deformation linearly,
    // making 100-200 jump far more than the visual control implied.
    readonly property real organicSensitivity: root.organicSensitivitySetting <= 0.4
        ? root.organicSensitivitySetting
        : 0.4 + 0.85 * (1 - Math.exp(-(root.organicSensitivitySetting - 0.4) * 1.4))
    readonly property real organicPulse: Config.getNestedValue(
        "background.widgets.custom.music-bars-3.organicPulse", 150) / 100
    readonly property real organicCompression: Config.getNestedValue(
        "background.widgets.custom.music-bars-3.organicCompression", 0) / 100
    readonly property real organicMotionSpeed: Config.getNestedValue(
        "background.widgets.custom.music-bars-3.organicMotionSpeed", 250) / 100
    readonly property real organicIdleMotion: Config.getNestedValue(
        "background.widgets.custom.music-bars-3.organicIdleMotion", 18) / 100
    readonly property real organicOpacity: Config.getNestedValue(
        "background.widgets.custom.music-bars-3.organicOpacity", 100) / 100
    readonly property real organicGlow: Config.getNestedValue(
        "background.widgets.custom.music-bars-3.organicGlow", 100) / 100
    readonly property real organicCoverSize: Config.getNestedValue(
        "background.widgets.custom.music-bars-3.organicCoverSize", 51) / 100
    readonly property real organicRange: Config.getNestedValue(
        "background.widgets.custom.music-bars-3.organicRange", 20) / 100
    // The Organic texture renders larger than the widget so peaks have room.
    // Compensate that overscan when cutting the centre hole: the inner edge
    // should track the artwork itself, not an arbitrary shader-space radius.
    readonly property real organicRenderOverscan: 1.34
    // The original Organic kept roughly 0.075-0.08 radial units of body between
    // the artwork edge and the resting outer contour. Derive the resting radius
    // from the actual cover instead of letting a fixed blob radius make smaller
    // covers look disproportionately thick.
    readonly property real organicBaseRadius: Math.min(0.78,
        root.organicCoverSize / root.organicRenderOverscan + 0.078)
    // Let the Organic body continue underneath the artwork. Matching two
    // antialiased edges exactly leaves a wallpaper-colored seam; underlapping
    // the halo means the cover is always the visual owner of the centre edge.
    readonly property real organicCoverUnderlap: 0.055
    readonly property real organicHollowAmount: Math.max(0, Math.min(1,
        ((root.organicCoverSize - root.organicCoverUnderlap)
            / root.organicRenderOverscan) / 0.565))

    editPopoverContent: Component {
        ColumnLayout {
            id: visualizerQuickRoot
            readonly property string path: "background.widgets.custom.music-bars-3."
            spacing: 14

            component VizSlider: WidgetQuickSlider {
                id: vizSlider
                required property string key
                required property int minimum
                required property int maximum
                property int step: 5
                property real fallback: minimum
                property string suffix: "%"
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                Layout.maximumWidth: Number.POSITIVE_INFINITY
                from: vizSlider.minimum
                to: vizSlider.maximum
                stepSize: vizSlider.step
                unit: vizSlider.suffix
                value: {
                    const stored = Number(Config.getNestedValue("background.widgets.custom.music-bars-3." + vizSlider.key, vizSlider.fallback))
                    return stored >= vizSlider.minimum ? stored : vizSlider.fallback
                }
                onCommitted: v => Config.setNestedValue("background.widgets.custom.music-bars-3." + vizSlider.key, Math.round(v))
            }

            WidgetQuickSection {
                title: Translation.tr("Style")
                WidgetQuickChoices {
                    current: root.vizType
                    model: [
                        { label: Translation.tr("Bars"), icon: "equalizer", value: "bars" },
                        { label: Translation.tr("Wave"), icon: "graphic_eq", value: "wave" },
                        { label: Translation.tr("Organic"), icon: "bubble_chart", value: "organic" }
                    ]
                    onPicked: value => Config.setNestedValue(visualizerQuickRoot.path + "vizType", value)
                }
            }

            WidgetQuickSection {
                title: Translation.tr("Orientación")
                WidgetQuickChoices {
                    maxColumns: 2
                    current: root.rotationSetting
                    model: [
                        { label: Translation.tr("Horizontal"), icon: "crop_landscape", value: 0 },
                        { label: Translation.tr("De cabeza"), icon: "flip", value: 180 },
                        { label: Translation.tr("Vertical →"), icon: "east", value: 90 },
                        { label: Translation.tr("Vertical ←"), icon: "west", value: 270 }
                    ]
                    onPicked: value => {
                        const wasVertical = root.verticalOrientation
                        const isVertical = (value === 90 || value === 270)
                        const updates = { rotation: value }
                        if (wasVertical !== isVertical) {
                            updates.contentWidth = Number(root._readConfigKey("contentHeight") ?? 104)
                            updates.contentHeight = Number(root._readConfigKey("contentWidth") ?? 304)
                        }
                        root._setOutputValues(updates)
                    }
                }
            }

            WidgetQuickSection {
                title: Translation.tr("Colour")
                WidgetQuickChoices {
                    maxColumns: 4
                    current: root.paletteMode
                    model: [
                        { label: Translation.tr("Cava"), icon: "palette", value: "cava" },
                        { label: Translation.tr("Accent"), icon: "colors", value: "accent" },
                        { label: Translation.tr("Primary"), icon: "format_color_fill", value: "primary" },
                        { label: Translation.tr("Album"), icon: "album", value: "album" }
                    ]
                    onPicked: value => Config.setNestedValue(visualizerQuickRoot.path + "paletteMode", value)
                }
            }

            // Neon halo drawn around the visual; 0 turns it off completely.
            WidgetQuickSection {
                title: Translation.tr("Efectos")
                VizSlider {
                    title: Translation.tr("Neón")
                    key: "glow"
                    minimum: 0
                    maximum: 100
                    step: 5
                    fallback: 65
                }
            }

            // Surface / frame, right on the widget. "None" is a true frameless
            // state: with both the plate and the border off the WidgetSurface
            // goes invisible and only the bars/wave float over the wallpaper.
            // The aurora and angel dialects render the plate at a high fixed
            // alpha, so the Background toggle (not the opacity slider) is what
            // removes its milky card.
            WidgetQuickSection {
                title: Translation.tr("Surface")
                WidgetQuickChoices {
                    maxColumns: 3
                    isSelected: entry => {
                        const bg = Boolean(Config.getNestedValue(visualizerQuickRoot.path + "showBackground", true))
                        const bd = Boolean(Config.getNestedValue(visualizerQuickRoot.path + "showBorder", true))
                        const r = Number(Config.getNestedValue(visualizerQuickRoot.path + "cornerRadius", -1))
                        if (entry.value === "none")
                            return !bg && !bd
                        if (entry.value === "card")
                            return bg && bd && !(r > 20)
                        return bg && bd && r > 20
                    }
                    model: [
                        { label: Translation.tr("None"), icon: "crop_free", value: "none" },
                        { label: Translation.tr("Card"), icon: "rectangle", value: "card" },
                        { label: Translation.tr("Pill"), icon: "rounded_corner", value: "pill" }
                    ]
                    onPicked: value => {
                        const path = visualizerQuickRoot.path
                        if (value === "none") {
                            Config.setNestedValue(path + "showBackground", false)
                            Config.setNestedValue(path + "showBorder", false)
                        } else if (value === "card") {
                            Config.setNestedValue(path + "showBackground", true)
                            Config.setNestedValue(path + "showBorder", true)
                            Config.setNestedValue(path + "cornerRadius", -1)
                        } else {
                            Config.setNestedValue(path + "showBackground", true)
                            Config.setNestedValue(path + "showBorder", true)
                            Config.setNestedValue(path + "cornerRadius", 40)
                        }
                    }
                }
                WidgetQuickToggle {
                    iconName: "format_color_fill"
                    label: Translation.tr("Background")
                    checked: Config.getNestedValue(visualizerQuickRoot.path + "showBackground", true)
                    onToggled: Config.setNestedValue(visualizerQuickRoot.path + "showBackground", !checked)
                }
                WidgetQuickToggle {
                    iconName: "border_style"
                    label: Translation.tr("Border")
                    checked: Config.getNestedValue(visualizerQuickRoot.path + "showBorder", true)
                    onToggled: Config.setNestedValue(visualizerQuickRoot.path + "showBorder", !checked)
                }
                WidgetQuickToggle {
                    visible: Config.getNestedValue(visualizerQuickRoot.path + "showBackground", true)
                    iconName: "blur_on"
                    label: Translation.tr("Blur background")
                    checked: Config.getNestedValue(visualizerQuickRoot.path + "useBlur", false)
                    onToggled: Config.setNestedValue(visualizerQuickRoot.path + "useBlur", !checked)
                }
                WidgetQuickSlider {
                    visible: Config.getNestedValue(visualizerQuickRoot.path + "showBackground", true)
                    title: Translation.tr("Background opacity")
                    from: 0
                    to: 100
                    stepSize: 1
                    unit: "%"
                    value: {
                        const stored = Number(Config.getNestedValue(
                            visualizerQuickRoot.path + "backgroundOpacity", 0.16))
                        if (!Number.isFinite(stored))
                            return 16
                        return Math.max(0, Math.min(100, Math.round(stored <= 1 ? stored * 100 : stored)))
                    }
                    onCommitted: v => Config.setNestedValue(
                        visualizerQuickRoot.path + "backgroundOpacity", Math.round(v) / 100)
                }
            }

            WidgetQuickSection {
                visible: root.vizType !== "organic"
                title: root.vizType === "bars" ? Translation.tr("Bars grow from") : Translation.tr("Wave")
                WidgetQuickChoices {
                    maxColumns: 4
                    current: root.vizType === "bars"
                        ? Config.getNestedValue(visualizerQuickRoot.path + "barsOrigin", "bottom")
                        : Config.getNestedValue(visualizerQuickRoot.path + "waveMode", "fill")
                    model: root.vizType === "bars" ? [
                        { label: Translation.tr("Bottom"), icon: "vertical_align_bottom", value: "bottom" },
                        { label: Translation.tr("Top"), icon: "vertical_align_top", value: "top" },
                        { label: Translation.tr("Center"), icon: "center_focus_strong", value: "center" },
                        { label: Translation.tr("Mirror"), icon: "unfold_more", value: "mirror" }
                    ] : [
                        { label: Translation.tr("Fill"), icon: "waves", value: "fill" },
                        { label: Translation.tr("Line"), icon: "line_weight", value: "line" },
                        { label: Translation.tr("Ribbon"), icon: "unfold_more", value: "ribbon" }
                    ]
                    onPicked: value => Config.setNestedValue(visualizerQuickRoot.path
                        + (root.vizType === "bars" ? "barsOrigin" : "waveMode"), value)
                }
            }

            GridLayout {
                visible: root.vizType !== "organic"
                Layout.fillWidth: true
                columns: 2
                columnSpacing: 16
                rowSpacing: 10
                VizSlider {
                    title: root.vizType === "bars" ? Translation.tr("Bar count") : Translation.tr("Wave opacity")
                    key: root.vizType === "bars" ? "barCount" : "waveOpacity"
                    minimum: root.vizType === "bars" ? 8 : 5
                    maximum: root.vizType === "bars" ? 128 : 100
                    step: root.vizType === "bars" ? 4 : 5
                    fallback: root.vizType === "bars" ? 48 : (Config.options?.appearance?.cava?.waveOpacity ?? 30)
                    suffix: root.vizType === "bars" ? "" : "%"
                }
                VizSlider { title: Translation.tr("Smoothing"); key: "smoothing"; minimum: 0; maximum: 8; step: 1; fallback: 2; suffix: "" }
            }

            GridLayout {
                visible: root.vizType === "organic"
                Layout.fillWidth: true
                columns: 2
                columnSpacing: 16
                rowSpacing: 10
                VizSlider { title: Translation.tr("Sensitivity"); key: "organicSensitivity"; minimum: 25; maximum: 200 }
                VizSlider { title: Translation.tr("Pulse"); key: "organicPulse"; minimum: 0; maximum: 150 }
                VizSlider { title: Translation.tr("Compression"); key: "organicCompression"; minimum: 0; maximum: 100 }
                VizSlider { title: Translation.tr("Motion"); key: "organicMotionSpeed"; minimum: 20; maximum: 250 }
                VizSlider { title: Translation.tr("Cover"); key: "organicCoverSize"; minimum: 30; maximum: 90; step: 1 }
                VizSlider { title: Translation.tr("Glow"); key: "organicGlow"; minimum: 0; maximum: 100 }
                VizSlider { title: Translation.tr("Presence"); key: "organicOpacity"; minimum: 10; maximum: 100 }
                VizSlider { title: Translation.tr("Idle"); key: "organicIdleMotion"; minimum: 0; maximum: 100 }
                VizSlider { title: Translation.tr("Range"); key: "organicRange"; minimum: 20; maximum: 100 }
            }
        }
    }

    readonly property bool _active: root.visible
        && root.motionActive && MprisController.isPlaying
    readonly property MprisPlayer _activePlayer: MprisController.activePlayer
    readonly property bool _organicPresent: root.visible && root.powerActive
        && root.vizType === "organic" && root._activePlayer !== null
    readonly property string _activeArt: organicArtworkResolver.displaySource
    property string _organicDisplayedArt: ""
    property string _organicDisplayedArtIdentity: ""
    property string _organicPendingArt: ""
    property string _organicPendingArtIdentity: ""
    property real _organicReveal: 1
    readonly property var _organicSilentPoints: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]

    function _organicArtIdentity(source: string): string {
        const value = source ?? ""
        let marker = value.indexOf("?inir_art=")
        if (marker < 0)
            marker = value.indexOf("&inir_art=")
        return marker >= 0 ? value.slice(0, marker) : value
    }
    readonly property color _organicPrimary: {
        const palette = root.spectrumPalette ?? []
        return palette.length > 0 ? palette[0] : root.widgetAccentVisible
    }
    readonly property color _organicSecondary: {
        const palette = root.spectrumPalette ?? []
        if (palette.length > 2)
            return palette[Math.floor((palette.length - 1) / 2)]
        if (palette.length > 1)
            return palette[1]
        return root._organicPrimary
    }
    readonly property color _organicTertiary: {
        const palette = root.spectrumPalette ?? []
        if (palette.length > 2)
            return palette[palette.length - 1]
        return root._organicSecondary
    }

    MediaArtworkResolver {
        id: organicArtworkResolver
        sourceUrl: (root.vizType === "organic" || root.paletteMode === "album")
            ? MprisController.effectiveArtUrl(root._activePlayer) : ""
        title: MprisController.titleOf(root._activePlayer) ?? ""
        artist: MprisController.artistOf(root._activePlayer) ?? ""
        album: root._activePlayer?.trackAlbum ?? ""
    }

    ColorQuantizer {
        id: albumArtworkQuantizer
        source: root.paletteMode === "album" ? organicArtworkResolver.displaySource : ""
        depth: 2
        rescaleSize: 24
    }

    on_ActiveArtChanged: {
        const next = root._activeArt
        if (next.length === 0)
            return
        const identity = root._organicArtIdentity(next)
        if (root._organicDisplayedArt.length === 0) {
            root._organicDisplayedArt = next
            root._organicDisplayedArtIdentity = identity
            return
        }
        if (identity === root._organicDisplayedArtIdentity) {
            root._organicDisplayedArt = next
            return
        }
        if (organicArtTransition.running
                && identity === root._organicPendingArtIdentity) {
            root._organicPendingArt = next
            return
        }
        root._organicPendingArt = next
        root._organicPendingArtIdentity = identity
        organicArtTransition.restart()
    }

    SequentialAnimation {
        id: organicArtTransition
        NumberAnimation {
            target: root
            property: "_organicReveal"
            to: 0
            duration: Appearance.calcEffectiveDuration(170)
            easing.type: Easing.InCubic
        }
        ScriptAction {
            script: {
                root._organicDisplayedArt = root._organicPendingArt
                root._organicDisplayedArtIdentity = root._organicPendingArtIdentity
            }
        }
        NumberAnimation {
            target: root
            property: "_organicReveal"
            to: 1
            duration: Appearance.calcEffectiveDuration(300)
            easing.type: Easing.OutBack
            easing.overshoot: 1.08
        }
    }

    // ── Style tokens ───────────────────────────────────────────
    readonly property real cardRadius: root.widgetCardRadius

    CavaProcess {
        id: cavaProcess
        active: root._active
        sampleCount: Math.max(50,
            Config.getNestedValue("background.widgets.custom.music-bars-3.barCount", 48))
    }

    // ── Card background ────────────────────────────────────────
    // ── Orientation canvas ─────────────────────────────────────
    // The whole visual turns here; the item itself stays axis-aligned so
    // dragging, resizing and the edit outline keep working in screen space.
    Item {
        id: rotCanvas
        anchors.centerIn: parent
        width: root.verticalOrientation ? root.height : root.width
        height: root.verticalOrientation ? root.width : root.height
        rotation: root.rotationSetting

        // Neon glow: everything drawn here renders into its own layer and
        // gets a zero-offset shadow — a halo hugging the bars/wave shape.
        layer.enabled: root.glowAmount > 0.01
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: root.glowColor
            shadowOpacity: Math.min(1, root.glowAmount * 1.3)
            shadowBlur: 0.35 + root.glowAmount * 0.55
            blurMax: Math.max(12, Math.round(30 * root.scaleFactor))
            shadowHorizontalOffset: 0
            shadowVerticalOffset: 0
            autoPaddingEnabled: true
        }

        WidgetSurface {
            regionBrightness: root.regionBrightness
            id: cardBg
            anchors.centerIn: parent
            width: parent.width
            height: parent.height
            surfaceRadius: root.cornerRadiusOverride >= 0 ? root.cornerRadiusOverride : root.cardRadius
            surfaceOpacity: root.backgroundOpacity
            surfaceBorderWidth: root.borderWidth
            surfaceBorderOpacity: root.borderOpacity
            surfaceColor: root.widgetSurfaceInk
            colorMode: root.colorMode
            surfaceAccent: root.widgetAccent
            surfaceFill: root.widgetPlateColor
            surfaceUseBlur: root.effectiveBlur
            screenX: root.x
            screenY: root.y
            screenWidth: root.scaledScreenWidth
            screenHeight: root.scaledScreenHeight
            shown: root.backgroundOpacity > 0 || root.borderWidth > 0 || root.effectiveBlur
        }

        // ── Visualizer rendering ─────────────────────────────────────
        // The field and the artwork on top of it move out together (LiveLayer): in their own surface, in their own
        // order, so a still widget does not repaint the whole desktop every frame. The card stays in the host, below.
        LiveLayer {
            anchors.fill: parent
            live: root.motionActive && (root.vizType === "organic"
                ? root._organicPresent
                : root._active && cavaProcess.audioSignalActive)
            content: vizContent
        }
    }

    Component {
        id: vizContent
        Item {
            id: vizDrawn
            property bool drawing: false

            AudioVisualizerLayer {
                id: visualizerLayer
                anchors.fill: parent
                anchors.margins: Appearance.angelEverywhere || Appearance.inirEverywhere ? 4 : 0
                points: root.vizType === "organic"
                    ? (root._active && cavaProcess.audioSignalActive
                        ? cavaProcess.points : root._organicSilentPoints)
                    : cavaProcess.points
                active: root.vizType === "organic"
                    ? root._organicPresent
                    : root._active && cavaProcess.audioSignalActive
                animate: root.motionActive && vizDrawn.drawing
                visualizerType: root.vizType
                normalizationCeiling: cavaProcess.normalizationCeiling
                spectrumColors: root.spectrumPalette
                spectrumColor: root.widgetAccentVisible
                spectrumOpacity: (root.vizType === "wave"
                    ? (root.waveOpacity >= 0 ? root.waveOpacity
                        : (Config.options?.appearance?.cava?.waveOpacity ?? 30))
                    : Config.getNestedValue("background.widgets.custom.music-bars-3.barOpacity", 100)) / 100
                fillRatio: root.vizType === "organic" ? root.organicRange
                    : Config.getNestedValue("background.widgets.custom.music-bars-3.fillRatio", 90) / 100
                barCount: Config.getNestedValue("background.widgets.custom.music-bars-3.barCount", 48)
                barSpacing: Config.getNestedValue("background.widgets.custom.music-bars-3.barSpacing", 2)
                barMinHeight: Config.getNestedValue("background.widgets.custom.music-bars-3.barMinHeight", 1)
                barRadius: Config.getNestedValue("background.widgets.custom.music-bars-3.barRadius", 2)
                barsOrigin: Config.getNestedValue("background.widgets.custom.music-bars-3.barsOrigin", "bottom")
                smoothing: root.smoothing
                waveMode: Config.getNestedValue("background.widgets.custom.music-bars-3.waveMode", "fill")
                lineWidth: Config.getNestedValue("background.widgets.custom.music-bars-3.lineWidth", 2)
                edgeInset: Config.getNestedValue("background.widgets.custom.music-bars-3.edgeInset", 0)
                edgeSoftness: Config.getNestedValue("background.widgets.custom.music-bars-3.edgeSoftness", 28) / 100
                frequencyProfile: root.frequencyProfile
                accentStrength: root.accentStrength
                organicSensitivity: root.organicSensitivity
                organicPulse: root.organicPulse
                organicCompression: root.organicCompression
                organicMotionSpeed: root.organicMotionSpeed
                organicIdleMotion: root.organicIdleMotion
                organicOpacity: root.organicOpacity
                organicGlow: root.organicGlow
                organicOverscan: root.organicRenderOverscan
                organicBaseRadius: root.organicBaseRadius
                organicHollowAmount: root.organicHollowAmount
            }

            Item {
                id: organicCluster
                anchors.fill: parent
                anchors.margins: Math.round(4 * root.scaleFactor)
                visible: root.vizType === "organic"

                ClippingRectangle {
                    id: organicArtwork
                    readonly property real span: Math.min(organicCluster.width, organicCluster.height)

                    width: Math.round(span * root.organicCoverSize)
                    height: width
                    anchors.centerIn: parent
                    visible: root._organicPresent
                    scale: 0.70 + root._organicReveal * 0.30
                    opacity: 0.18 + root._organicReveal * 0.82
                    radius: width * 0.36
                    color: root.widgetSemanticContainer(root.widgetSurfaceRole)
                    border.width: Math.max(1, Math.round(root.scaleFactor))
                    border.color: ColorUtils.applyAlpha(root._organicPrimary, 0.34)

                    Image {
                        anchors.fill: parent
                        source: root._organicDisplayedArt
                        sourceSize: Qt.size(Math.max(128, Math.ceil(width * 2)),
                            Math.max(128, Math.ceil(height * 2)))
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        retainWhileLoading: true
                        cache: true
                        smooth: true
                        mipmap: true
                        visible: status === Image.Ready
                    }

                    MaterialSymbol {
                        anchors.centerIn: parent
                        visible: root._organicDisplayedArt.length === 0
                        text: "music_note"
                        fill: 1
                        iconSize: Math.round(organicArtwork.width * 0.34)
                        color: root.widgetSemanticOnContainer(root.widgetSurfaceRole)
                    }
                }
            }
        }
    }
}
