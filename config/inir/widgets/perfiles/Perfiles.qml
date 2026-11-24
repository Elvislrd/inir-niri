pragma ComponentBehavior: Bound

// Perfiles — un botón que aparece en modo edición y permite cambiar entre
// layouts completos del escritorio, con backup y vuelta al layout Actual.

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.background.widgets

AbstractBackgroundWidget {
    id: root

    configEntryName: "custom.perfiles"
    defaultConfig: ({
        enable: true,
        placementStrategy: "free",
        x: 24,
        y: 24,
        widgetScale: 100,
        widgetOpacity: 100,
        dim: 0,
        colorMode: "auto"
    })

    readonly property string profilesPath: Directories.configPath + "/inir/desktop-profiles/profiles.json"
    readonly property string backupPath: Directories.configPath + "/inir/desktop-profiles/backup-before-apply.json"
    readonly property var profileOrder: ["actual", "musica", "hud", "minimal", "sticker"]
    readonly property var builtinWidgetKeys: [
        "battery", "calendarUpcoming", "clock", "controls", "customImage",
        "dateBadge", "dayProgress", "editorial", "imageConverter",
        "japaneseTypography", "mascot", "mediaControls", "monthCalendar",
        "newsTicker", "notes", "screenTime", "shape", "systemMonitor",
        "timers", "todo", "uptime", "userCard", "visualizer", "weather",
        "worldClock"
    ]

    property var profiles: ({})
    property string activeProfile: ""
    property string statusText: ""
    property var _backupSnapshot: null
    property var _pendingSnapshot: null
    property string _pendingProfileName: ""
    property bool _savingProfiles: false
    property int _profileLoadRetries: 0

    readonly property var profileList: {
        const result = []
        for (const id of root.profileOrder) {
            const profile = root.profiles[id]
            if (profile && typeof profile === "object")
                result.push(Object.assign({ id: id }, profile))
        }
        for (const id of Object.keys(root.profiles ?? {})) {
            if (root.profileOrder.includes(id))
                continue
            const profile = root.profiles[id]
            if (profile && typeof profile === "object")
                result.push(Object.assign({ id: id }, profile))
        }
        return result
    }

    implicitWidth: Math.round(128 * root.scaleFactor)
    implicitHeight: Math.round(40 * root.scaleFactor)
    visible: GlobalStates.widgetEditMode
    visibleWhenLocked: false
    resizableAxes: ({ uniform: "widgetScale" })

    function _clone(value): var {
        try {
            return JSON.parse(JSON.stringify(value ?? null))
        } catch (error) {
            return null
        }
    }

    function _captureSnapshot(): var {
        let widgets = null
        try {
            widgets = JSON.parse(JSON.stringify(Config.options?.background?.widgets ?? {}))
        } catch (error) {
            widgets = null
        }
        if (!widgets || typeof widgets !== "object")
            return null
        widgets.custom = root._clone(Config.customWidgetData ?? {}) ?? {}
        const mascotInstances = root._clone(Config.mascotInstances ?? {}) ?? {}
        if (Object.keys(mascotInstances).length > 0)
            widgets.mascotInstances = mascotInstances
        return {
            widgets: widgets,
            capturedAt: new Date().toISOString()
        }
    }

    function _ensureSwitcher(snapshot): var {
        if (!snapshot || typeof snapshot !== "object" || !snapshot.widgets)
            return snapshot
        if (!snapshot.widgets.custom || typeof snapshot.widgets.custom !== "object")
            snapshot.widgets.custom = {}
        const current = snapshot.widgets.custom["perfiles"] ?? {}
        snapshot.widgets.custom["perfiles"] = Object.assign({}, current, {
            enable: true,
            placementStrategy: "free",
            x: 24,
            y: 24,
            widgetScale: 100,
            widgetOpacity: 100,
            dim: 0,
            colorMode: "auto"
        })
        const overrides = Array.isArray(snapshot.widgets.outputOverrides)
            ? snapshot.widgets.outputOverrides : []
        for (const record of overrides) {
            if (!record || typeof record !== "object")
                continue
            if (!record.widgets || typeof record.widgets !== "object")
                record.widgets = {}
            const currentOverride = record.widgets["custom.perfiles"] ?? {}
            record.widgets["custom.perfiles"] = Object.assign({}, currentOverride, {
                enable: true,
                placementStrategy: "free",
                x: 24,
                y: 24,
                widgetScale: 100
            })
        }
        return snapshot
    }

    function _mergedCustom(incomingCustom): var {
        const current = root._clone(Config.customWidgetData ?? {}) ?? {}
        const incoming = root._clone(incomingCustom ?? {}) ?? {}
        const merged = current
        for (const id of Object.keys(incoming)) {
            merged[id] = Object.assign({}, merged[id] ?? {}, incoming[id] ?? {})
        }
        // Un perfil manda: los widgets instalados después de guardarlo quedan
        // apagados en ese perfil, pero conservan su configuración.
        for (const id of Object.keys(merged)) {
            if (!(id in incoming) && merged[id] && typeof merged[id] === "object")
                merged[id].enable = false
        }
        merged["perfiles"] = Object.assign({}, merged["perfiles"] ?? {}, {
            enable: true,
            placementStrategy: "free",
            x: 24,
            y: 24,
            widgetScale: 100,
            widgetOpacity: 100,
            dim: 0,
            colorMode: "auto"
        })
        return merged
    }

    function _cleanOutputRecords(profileRecords): var {
        const current = root._clone(Config.options?.background?.widgets?.outputOverrides ?? []) ?? []
        const result = []
        const seen = ({})
        const records = Array.isArray(profileRecords) ? profileRecords : []
        for (const raw of records) {
            const record = root._clone(raw) ?? {}
            const output = String(record?.output ?? "")
            if (!output || seen[output])
                continue
            seen[output] = true
            if (!output.startsWith("lock:")) {
                const valuesByKey = record.widgets
                if (valuesByKey && typeof valuesByKey === "object") {
                    for (const key of Object.keys(valuesByKey)) {
                        if (valuesByKey[key] && typeof valuesByKey[key] === "object")
                            delete valuesByKey[key].enable
                    }
                }
            }
            result.push(record)
        }
        // Otras salidas o el layout de bloqueo no se borran al aplicar un perfil.
        for (const raw of current) {
            const record = root._clone(raw) ?? {}
            const output = String(record?.output ?? "")
            if (!output || seen[output])
                continue
            seen[output] = true
            result.push(record)
        }
        return result
    }

    function _applySnapshot(snapshot): bool {
        if (!snapshot || typeof snapshot !== "object" || !snapshot.widgets)
            return false
        const widgets = snapshot.widgets
        const updates = {}
        for (const key of Object.keys(widgets)) {
            if (key === "custom" || key === "outputOverrides")
                continue
            updates["background.widgets." + key] = root._clone(widgets[key])
        }
        // Los widgets personalizados se tocan uno por uno. El selector
        // (perfiles) se deja intacto para que no se recargue mientras aplica.
        const custom = root._mergedCustom(widgets.custom)
        for (const id of Object.keys(custom)) {
            if (id === "perfiles")
                continue
            updates["background.widgets.custom." + id] = root._clone(custom[id])
        }
        try {
            Config.setNestedValues(updates)

            // El encendido/apagado es global en un perfil. Lo fijamos por ruta
            // plana y quitamos los `enable` por salida; así un perfil no queda
            // medio aplicado cuando una salida tenía un override viejo.
            const enableUpdates = {}
            for (const key of root.builtinWidgetKeys)
                enableUpdates["background.widgets." + key + ".enable"] = Boolean(widgets[key]?.enable)
            for (const id of Object.keys(custom)) {
                if (id === "perfiles")
                    continue
                enableUpdates["background.widgets.custom." + id + ".enable"] = Boolean(custom[id]?.enable)
            }
            Config.setNestedValues(enableUpdates)

            // Reemplazamos el layout por salida con el del perfil, no lo
            // fusionamos: así no quedan restos de estilo del perfil anterior.
            Config.setNestedValue("background.widgets.outputOverrides",
                root._cleanOutputRecords(widgets.outputOverrides))
            Config.setNestedValues(enableUpdates)
            DesktopWidgetLayout.clearEnableOverrides()
        } catch (error) {
            console.warn("[Perfiles] No pude aplicar el snapshot:", error)
            root.statusText = "Ese perfil tiene un ajuste incompatible."
            return false
        }
        return true
    }

    function _writeBackup(snapshot): bool {
        if (!snapshot)
            return false
        root._backupSnapshot = root._clone(snapshot)
        if (!root._backupSnapshot)
            return false
        backupFile.setText(JSON.stringify({
            version: 1,
            savedAt: new Date().toISOString(),
            snapshot: root._backupSnapshot
        }, null, 2))
        return true
    }

    function applyProfile(id: string): string {
        const key = String(id ?? "").trim()
        const profile = root.profiles[key]
        if (!profile || !profile.snapshot) {
            root.statusText = "Ese perfil no tiene datos."
            return "missing profile: " + key
        }
        const current = root._captureSnapshot()
        if (!root._writeBackup(current)) {
            root.statusText = "No pude leer tu layout actual; no cambié nada."
            return "backup failed"
        }
        const snapshot = root._ensureSwitcher(root._clone(profile.snapshot))
        if (!snapshot) {
            root.statusText = "No pude preparar el perfil."
            return "prepare failed"
        }
        // Guardamos primero el perfil activo. Al aplicar el layout, los
        // widgets personalizados pueden recargarse y este selector también.
        root.activeProfile = key
        root._saveProfiles()
        root._pendingSnapshot = snapshot
        root._pendingProfileName = String(profile.name ?? key)
        root.statusText = "Aplicando: " + root._pendingProfileName
        applyProfileTimer.restart()
        return "applying " + key
    }

    function saveCurrent(): string {
        const snapshot = root._captureSnapshot()
        if (!snapshot) {
            root.statusText = "No pude leer tu layout actual."
            return "capture failed"
        }
        const saved = root._ensureSwitcher(root._clone(snapshot))
        const previous = root.profiles["actual"] ?? {}
        root.profiles["actual"] = Object.assign({}, previous, {
            id: "actual",
            name: "Actual",
            icon: "dashboard",
            description: "Tu layout guardado. Vuelve aquí si algo no te gusta.",
            snapshot: saved
        })
        root.profiles = Object.assign({}, root.profiles)
        root._saveProfiles()
        root.statusText = "Perfil Actual actualizado."
        statusTimer.restart()
        return "saved"
    }

    function restoreBackup(): string {
        let snapshot = root._backupSnapshot
        if (!snapshot) {
            try {
                const data = JSON.parse(backupFile.text())
                snapshot = data?.snapshot ?? null
            } catch (error) {
                snapshot = null
            }
        }
        if (!snapshot) {
            root.statusText = "Todavía no hay un backup para restaurar."
            return "no backup"
        }
        if (!root._applySnapshot(root._ensureSwitcher(root._clone(snapshot)))) {
            root.statusText = "No pude restaurar el backup."
            return "restore failed"
        }
        root.statusText = "Backup restaurado."
        statusTimer.restart()
        return "restored"
    }

    function openPicker(): string {
        if (!GlobalStates.widgetEditMode)
            GlobalStates.setWidgetEditMode(true)
        GlobalStates.selectDesktopWidget(root.editInstanceKey)
        root.openQuickControls("widget")
        return "opened"
    }

    function _bootstrapProfiles(): void {
        const snapshot = root._captureSnapshot()
        if (!snapshot) {
            root.statusText = "No pude crear el perfil Actual."
            return
        }
        root.profiles = {
            actual: {
                id: "actual",
                name: "Actual",
                icon: "dashboard",
                description: "Tu layout guardado. Vuelve aquí si algo no te gusta.",
                snapshot: root._ensureSwitcher(snapshot)
            }
        }
        root.activeProfile = "actual"
        root._saveProfiles()
    }

    function _loadProfiles(text: string): void {
        if (root._savingProfiles) {
            root._savingProfiles = false
            saveGuard.stop()
            return
        }
        try {
            const data = JSON.parse(text)
            if (!data || typeof data !== "object" || !data.profiles || typeof data.profiles !== "object")
                throw new Error("invalid profiles file")
            root.profiles = data.profiles
            root.activeProfile = String(data.active ?? "actual")
            if (!root.profiles[root.activeProfile])
                root.activeProfile = Object.keys(root.profiles)[0] ?? ""
            root._profileLoadRetries = 0
            root.statusText = ""
        } catch (error) {
            // Un guardado externo puede coincidir con la recarga y dejar el
            // archivo a medio leer. Reintentamos sin borrar los perfiles.
            console.warn("[Perfiles] No pude leer profiles.json:", error)
            if (root._profileLoadRetries < 4) {
                root._profileLoadRetries += 1
                profilesRetryTimer.restart()
            } else {
                root.statusText = "No pude leer profiles.json. No cambié nada."
            }
        }
    }

    function _saveProfiles(): void {
        const data = {
            version: 1,
            active: root.activeProfile,
            savedAt: new Date().toISOString(),
            profiles: root.profiles
        }
        root._savingProfiles = true
        saveGuard.restart()
        profilesFile.setText(JSON.stringify(data, null, 2))
    }

    FileView {
        id: profilesFile
        path: root.profilesPath
        blockLoading: true
        watchChanges: true
        printErrors: false

        onLoaded: root._loadProfiles(text())
        onFileChanged: reload()
        onLoadFailed: error => {
            if (error === FileViewError.FileNotFound)
                root._bootstrapProfiles()
        }
    }

    FileView {
        id: backupFile
        path: root.backupPath
        blockLoading: true
        printErrors: false

        onLoaded: {
            try {
                const data = JSON.parse(text())
                if (data?.snapshot)
                    root._backupSnapshot = data.snapshot
            } catch (error) {}
        }
    }

    Timer {
        id: saveGuard
        interval: 1200
        onTriggered: root._savingProfiles = false
    }

    Timer {
        id: profilesRetryTimer
        interval: 350
        onTriggered: {
            if (!root._savingProfiles)
                profilesFile.reload()
        }
    }

    Timer {
        id: applyProfileTimer
        interval: 320
        onTriggered: {
            const snapshot = root._pendingSnapshot
            root._pendingSnapshot = null
            const name = root._pendingProfileName
            root._pendingProfileName = ""
            if (!snapshot)
                return
            if (!root._applySnapshot(snapshot)) {
                root.statusText = "No pude aplicar el perfil."
            } else {
                root.statusText = "Aplicado: " + name
            }
            statusTimer.restart()
        }
    }

    Timer {
        id: statusTimer
        interval: 4500
        onTriggered: root.statusText = ""
    }

    IpcHandler {
        target: "perfiles"

        function list(): string {
            return JSON.stringify(root.profileList.map(p => ({
                id: p.id,
                name: p.name,
                description: p.description
            })))
        }

        function status(): string {
            return JSON.stringify({
                active: root.activeProfile,
                profiles: Object.keys(root.profiles ?? {})
            })
        }

        function debug(): string {
            const screen = Quickshell.screens?.[0]?.name ?? "eDP-1"
            return JSON.stringify({
                screen: screen,
                baseImage: Config.getNestedValue("background.widgets.customImage", null),
                imageOverride: DesktopWidgetLayout.widgetOverride(screen, "customImage"),
                imageEnabled: DesktopWidgetLayout.enabled(screen, "customImage", false),
                baseSystem: Config.getNestedValue("background.widgets.systemMonitor", null),
                systemOverride: DesktopWidgetLayout.widgetOverride(screen, "systemMonitor"),
                systemEnabled: DesktopWidgetLayout.enabled(screen, "systemMonitor", false)
            })
        }

        function apply(id: string): string {
            return root.applyProfile(id)
        }

        function save(): string {
            return root.saveCurrent()
        }

        function restore(): string {
            return root.restoreBackup()
        }

        function open(): string {
            return root.openPicker()
        }
    }

    // ── Botón visible en modo edición ─────────────────────────
    Rectangle {
        id: button
        anchors.fill: parent
        radius: height / 2
        color: buttonMouse.containsMouse
            ? ColorUtils.applyAlpha(Appearance.colors.colPrimary, 0.24)
            : ColorUtils.applyAlpha(Appearance.colors.colLayer2, 0.82)
        border.width: 1
        border.color: ColorUtils.applyAlpha(
            Appearance.colors.colPrimary, buttonMouse.containsMouse ? 0.55 : 0.22)
        antialiasing: true

        Behavior on color {
            enabled: Appearance.animationsEnabled
            ColorAnimation { duration: 140 }
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Math.round(12 * root.scaleFactor)
            anchors.rightMargin: Math.round(12 * root.scaleFactor)
            spacing: Math.round(7 * root.scaleFactor)

            MaterialSymbol {
                text: "view_quilt"
                iconSize: Math.round(18 * root.scaleFactor)
                color: Appearance.colors.colPrimary
            }

            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("Perfiles")
                elide: Text.ElideRight
                color: Appearance.colors.colOnLayer1
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.weight: Font.Medium
            }
        }

        MouseArea {
            id: buttonMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.openPicker()
        }
    }

    // ── Selector dentro de los controles rápidos ──────────────
    editPopoverContent: Component {
        ColumnLayout {
            id: picker
            spacing: 10

            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("Elige un layout. Antes de cambiar guardo tu layout actual como backup.")
                wrapMode: Text.Wrap
                color: ColorUtils.applyAlpha(Appearance.colors.colOnLayer1, 0.68)
                font.pixelSize: Appearance.font.pixelSize.smaller
            }

            Repeater {
                model: root.profileList

                Rectangle {
                    id: profileCard
                    required property var modelData
                    property bool hovered: false
                    Layout.fillWidth: true
                    Layout.preferredHeight: 54
                    radius: Appearance.rounding.small
                    color: {
                        if (root.activeProfile === profileCard.modelData.id)
                            return ColorUtils.applyAlpha(Appearance.colors.colPrimary, 0.16)
                        return profileCard.hovered
                            ? ColorUtils.applyAlpha(Appearance.colors.colOnLayer1, 0.08)
                            : ColorUtils.applyAlpha(Appearance.colors.colOnLayer1, 0.035)
                    }
                    border.width: 1
                    border.color: root.activeProfile === profileCard.modelData.id
                        ? ColorUtils.applyAlpha(Appearance.colors.colPrimary, 0.48)
                        : ColorUtils.applyAlpha(Appearance.colors.colOnLayer1, 0.08)
                    antialiasing: true

                    Behavior on color {
                        enabled: Appearance.animationsEnabled
                        ColorAnimation { duration: 120 }
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        spacing: 10

                        MaterialSymbol {
                            text: profileCard.modelData.icon ?? "dashboard"
                            iconSize: 21
                            color: root.activeProfile === profileCard.modelData.id
                                ? Appearance.colors.colPrimary
                                : ColorUtils.applyAlpha(Appearance.colors.colOnLayer1, 0.72)
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1

                            StyledText {
                                Layout.fillWidth: true
                                text: profileCard.modelData.name ?? profileCard.modelData.id
                                elide: Text.ElideRight
                                color: Appearance.colors.colOnLayer1
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.weight: Font.DemiBold
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: profileCard.modelData.description ?? ""
                                elide: Text.ElideRight
                                color: ColorUtils.applyAlpha(Appearance.colors.colOnLayer1, 0.6)
                                font.pixelSize: Appearance.font.pixelSize.smaller
                            }
                        }

                        MaterialSymbol {
                            visible: root.activeProfile === profileCard.modelData.id
                            text: "check_circle"
                            iconSize: 18
                            color: Appearance.colors.colPrimary
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: profileCard.hovered = true
                        onExited: profileCard.hovered = false
                        onClicked: root.applyProfile(profileCard.modelData.id)
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                WidgetEditAction {
                    iconName: "save"
                    label: Translation.tr("Guardar actual")
                    onClicked: root.saveCurrent()
                }

                WidgetEditAction {
                    iconName: "restore"
                    label: Translation.tr("Restaurar backup")
                    onClicked: root.restoreBackup()
                }
            }

            StyledText {
                Layout.fillWidth: true
                visible: root.statusText.length > 0
                text: root.statusText
                wrapMode: Text.Wrap
                color: ColorUtils.applyAlpha(Appearance.colors.colPrimary, 0.92)
                font.pixelSize: Appearance.font.pixelSize.smaller
            }
        }
    }
}
