// Lluvia Viva — custom iNiR desktop widget
// Rain falling over the wallpaper when the weather says so (or always, if you
// want). Canvas particles, theme-tinted, costs nothing while there is no rain.

import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.background.widgets

AbstractBackgroundWidget {
    id: root

    configEntryName: "custom.rain-live"
    defaultConfig: ({
        placementStrategy: "free", widgetScale: 100, widgetOpacity: 100,
        colorMode: "auto", dim: 0,
        x: 0, y: 0,
        drops: 70, speed: 100, dropOpacity: 30, dropLength: 100, always: false
    })

    // ── Config ────────────────────────────────────────────────
    readonly property int cfgDrops: {
        const v = Number(root._readConfigKey("drops") ?? 70)
        return Math.max(10, Math.min(240, Math.round(Number.isFinite(v) ? v : 70)))
    }
    readonly property real cfgSpeed: {
        const v = Number(root._readConfigKey("speed") ?? 100)
        return Math.max(0.25, Math.min(3, (Number.isFinite(v) ? v : 100) / 100))
    }
    readonly property real cfgDropOpacity: {
        const v = Number(root._readConfigKey("dropOpacity") ?? 30)
        return Math.max(0.05, Math.min(1, (Number.isFinite(v) ? v : 30) / 100))
    }
    readonly property real cfgLengthFactor: {
        const v = Number(root._readConfigKey("dropLength") ?? 100)
        return Math.max(0.35, Math.min(2.5, (Number.isFinite(v) ? v : 100) / 100))
    }
    readonly property bool cfgAlways: Boolean(root._readConfigKey("always") ?? false)

    // ── Rain detection (WWO weather codes) ────────────────────
    readonly property var rainCodes: ["176", "200", "293", "296", "299", "302", "305",
        "308", "311", "314", "353", "356", "359", "362", "365", "386", "389", "392", "395"]
    readonly property bool weatherRaining: {
        if (!Weather.enabled)
            return false
        const code = String(Weather.data ? Weather.data.wCode : "")
        return root.rainCodes.indexOf(code) >= 0
    }
    readonly property bool active: root.visible && (root.cfgAlways || root.weatherRaining)

    readonly property color dropColor: ColorUtils.mix(root.colText, Appearance.colors.colPrimary, 0.4)

    // ── Geometry (free resize) ────────────────────────────────
    implicitWidth: Math.round(Number(root._readConfigKey("contentWidth") ?? 1920) * root.scaleFactor)
    implicitHeight: Math.round(Number(root._readConfigKey("contentHeight") ?? 1080) * root.scaleFactor)
    resizeMinWidth: 200
    resizeMinHeight: 150
    resizableAxes: ({ width: "contentWidth", height: "contentHeight" })

    // ── Particles ─────────────────────────────────────────────
    property var _drops: []

    function _reseed(): void {
        const w = Math.max(1, rainCanvas.width)
        const h = Math.max(1, rainCanvas.height)
        const arr = []
        for (let i = 0; i < root.cfgDrops; i++) {
            arr.push({
                x: Math.random() * w,
                y: Math.random() * h,
                sp: h * (0.45 + Math.random() * 0.35),
                len: (8 + Math.random() * 14) * root.scaleFactor * root.cfgLengthFactor,
                a: 0.35 + Math.random() * 0.65
            })
        }
        root._drops = arr
    }

    function _step(): void {
        const w = rainCanvas.width
        const h = rainCanvas.height
        const dt = 0.033
        const drops = root._drops
        for (let i = 0; i < drops.length; i++) {
            const d = drops[i]
            d.y += d.sp * dt * root.cfgSpeed
            d.x += d.sp * dt * root.cfgSpeed * 0.16
            if (d.y > h + d.len) {
                d.y = -d.len - Math.random() * h * 0.12
                d.x = Math.random() * w
            } else if (d.x > w + 60) {
                d.x = -30 + Math.random() * 30
            }
        }
        rainCanvas.requestPaint()
    }

    Timer {
        id: reseedTimer
        interval: 120
        repeat: false
        onTriggered: root._reseed()
    }

    Canvas {
        id: rainCanvas
        anchors.fill: parent
        visible: root.active
        renderStrategy: Canvas.Cooperative

        onWidthChanged: reseedTimer.restart()
        onHeightChanged: reseedTimer.restart()
        Component.onCompleted: root._reseed()

        onPaint: {
            const ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            if (!root.active)
                return
            const c = root.dropColor
            const rgb = Math.round(c.r * 255) + "," + Math.round(c.g * 255) + "," + Math.round(c.b * 255)
            ctx.lineCap = "round"
            ctx.lineWidth = Math.max(1, 1.4 * root.scaleFactor)
            const drops = root._drops
            for (let i = 0; i < drops.length; i++) {
                const d = drops[i]
                const alpha = Math.max(0.02, Math.min(0.9, d.a * root.cfgDropOpacity))
                ctx.strokeStyle = "rgba(" + rgb + "," + alpha.toFixed(3) + ")"
                ctx.beginPath()
                ctx.moveTo(d.x, d.y)
                ctx.lineTo(d.x + d.len * 0.16, d.y + d.len)
                ctx.stroke()
            }
        }
    }

    Timer {
        interval: 33
        repeat: true
        running: root.active
        onTriggered: root._step()
    }

    // ── Quick settings popover ────────────────────────────────
    editPopoverContent: Component {
        ColumnLayout {
            id: rainQuickRoot
            readonly property string path: "background.widgets.custom.rain-live."
            spacing: 14

            component RainSlider: WidgetQuickSlider {
                id: rainSlider
                required property string key
                required property int minimum
                required property int maximum
                property int step: 5
                property real fallback: minimum
                property string suffix: ""
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                Layout.maximumWidth: Number.POSITIVE_INFINITY
                from: rainSlider.minimum
                to: rainSlider.maximum
                stepSize: rainSlider.step
                unit: rainSlider.suffix
                value: {
                    const v = Number(Config.getNestedValue("background.widgets.custom.rain-live." + rainSlider.key, rainSlider.fallback))
                    return v >= rainSlider.minimum && v <= rainSlider.maximum ? v : rainSlider.fallback
                }
                onCommitted: v => Config.setNestedValue("background.widgets.custom.rain-live." + rainSlider.key, Math.round(v))
            }

            WidgetQuickSection {
                title: Translation.tr("Lluvia")
                RainSlider {
                    title: Translation.tr("Gotas")
                    key: "drops"
                    minimum: 10
                    maximum: 240
                    step: 5
                    fallback: 70
                }
                RainSlider {
                    title: Translation.tr("Velocidad")
                    key: "speed"
                    minimum: 25
                    maximum: 300
                    step: 5
                    fallback: 100
                    suffix: "%"
                }
                RainSlider {
                    title: Translation.tr("Opacidad")
                    key: "dropOpacity"
                    minimum: 5
                    maximum: 100
                    step: 5
                    fallback: 30
                    suffix: "%"
                }
                RainSlider {
                    title: Translation.tr("Largo")
                    key: "dropLength"
                    minimum: 40
                    maximum: 250
                    step: 10
                    fallback: 100
                    suffix: "%"
                }
                WidgetQuickToggle {
                    iconName: "water_drop"
                    label: Translation.tr("Siempre activa")
                    checked: Config.getNestedValue(rainQuickRoot.path + "always", false)
                    onToggled: Config.setNestedValue(rainQuickRoot.path + "always", !checked)
                }
            }
        }
    }
}
