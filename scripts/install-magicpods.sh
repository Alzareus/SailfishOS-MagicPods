#!/bin/sh
# Installe harbour-magicpods : interface QML + icone.
# A lancer en root : devel-su sh install-magicpods.sh
#
# Desinstallation complete :
#   devel-su rm -rf /usr/share/harbour-magicpods \
#     /usr/share/applications/harbour-magicpods.desktop \
#     /usr/share/icons/hicolor/*/apps/harbour-magicpods.png

set -e

APPDIR=/usr/share/harbour-magicpods
ICONROOT=/usr/share/icons/hicolor

if [ "$(id -u)" != "0" ]; then
    echo "Ce script doit etre lance en root : devel-su sh install-magicpods.sh"
    exit 1
fi

rm -rf "$APPDIR"
mkdir -p "$APPDIR/qml/pages" "$APPDIR/qml/cover"

cat > "$APPDIR/qml/harbour-magicpods.qml" << 'MAGICPODS_EOF'
import QtQuick 2.6
import Sailfish.Silica 1.0
import "pages"
import "cover"

ApplicationWindow {
    id: app

    Backend {
        id: backendItem
    }

    initialPage: Component {
        MainPage {
            backend: backendItem
        }
    }

    cover: Component {
        CoverPage {
            backend: backendItem
        }
    }

    allowedOrientations: Orientation.All
}
MAGICPODS_EOF

cat > "$APPDIR/qml/Backend.qml" << 'MAGICPODS_EOF'
import QtQuick 2.6
import QtWebSockets 1.0

// Client WebSocket vers magicpodscore (127.0.0.1:2020).
// Expose l'etat courant sous forme de proprietes liables par l'interface.
Item {
    id: backend

    // Etat de la liaison avec le demon
    property bool linked: false
    // Dernier objet "info" recu : l'appareil actif et ses capacites
    property var info: ({})
    // Liste des appareils connus du demon
    property var headphones: []
    // Etat de l'adaptateur Bluetooth
    property bool adapterEnabled: false

    readonly property var caps: (info && info.capabilities) ? info.capabilities : ({})
    readonly property bool hasDevice: info !== undefined && info.address !== undefined
    readonly property string deviceName: (hasDevice && info.name) ? info.name : ""
    readonly property bool deviceConnected: hasDevice && info.connected === true

    width: 0
    height: 0

    function send(obj) {
        if (socket.status === WebSocket.Open)
            socket.sendTextMessage(JSON.stringify(obj))
    }

    function refresh() {
        send({ method: "GetAll" })
    }

    function setCapability(name, value) {
        if (!hasDevice)
            return

        var payload = {}
        payload[name] = { selected: value }

        send({
            method: "SetCapabilities",
            arguments: { address: info.address, capabilities: payload }
        })
    }

    function connectDevice(address) {
        send({ method: "ConnectDevice", arguments: { address: address } })
    }

    function disconnectDevice(address) {
        send({ method: "DisconnectDevice", arguments: { address: address } })
    }

    function reconnectSocket() {
        socket.active = false
        socket.active = true
    }

    WebSocket {
        id: socket

        url: "ws://127.0.0.1:2020"
        active: true

        onStatusChanged: {
            if (status === WebSocket.Open) {
                backend.linked = true
                backend.refresh()
            } else if (status === WebSocket.Closed || status === WebSocket.Error) {
                backend.linked = false
                reconnectTimer.start()
            }
        }

        onTextMessageReceived: {
            var json

            try {
                json = JSON.parse(message)
            } catch (error) {
                return
            }

            if (json.headphones !== undefined)
                backend.headphones = json.headphones

            if (json.info !== undefined)
                backend.info = json.info

            if (json.defaultbluetooth !== undefined)
                backend.adapterEnabled = json.defaultbluetooth.enabled === true
        }
    }

    Timer {
        id: reconnectTimer

        interval: 3000
        repeat: false
        onTriggered: backend.reconnectSocket()
    }
}
MAGICPODS_EOF

cat > "$APPDIR/qml/Modes.js" << 'MAGICPODS_EOF'
.pragma library

// Drapeaux universels des modes de controle du bruit, tels que le demon les expose
// dans capabilities.anc.options et capabilities.anc.selected.
var OFF = 1
var TRANSPARENCY = 2
var ADAPTIVE = 4
var WIND = 8
var NOISE_CANCELLATION = 16

var ALL = [OFF, TRANSPARENCY, ADAPTIVE, WIND, NOISE_CANCELLATION]

function ancName(flag) {
    switch (flag) {
    case OFF:
        return qsTr("Desactive")
    case TRANSPARENCY:
        return qsTr("Transparence")
    case ADAPTIVE:
        return qsTr("Adaptatif")
    case WIND:
        return qsTr("Anti-vent")
    case NOISE_CANCELLATION:
        return qsTr("Reduction de bruit")
    }
    return qsTr("Inconnu")
}

function batteryName(key) {
    switch (key) {
    case "left":
        return qsTr("Gauche")
    case "right":
        return qsTr("Droite")
    case "case":
        return qsTr("Boitier")
    case "single":
        return qsTr("Ecouteurs")
    }
    return key
}

// status : 0 indisponible, 1 deconnecte, 2 connecte, 3 en cache
function batteryEntries(battery) {
    var out = []

    if (!battery)
        return out

    var keys = ["left", "right", "single", "case"]

    for (var i = 0; i < keys.length; i++) {
        var entry = battery[keys[i]]

        if (entry && entry.status >= 2) {
            out.push({
                "key": keys[i],
                "label": batteryName(keys[i]),
                "level": entry.battery,
                "charging": entry.charging === true,
                "stale": entry.status === 3
            })
        }
    }

    return out
}

function ancEntries(anc) {
    var out = []

    if (!anc || anc.options === undefined)
        return out

    for (var i = 0; i < ALL.length; i++) {
        if (anc.options & ALL[i])
            out.push({ "flag": ALL[i], "label": ancName(ALL[i]) })
    }

    return out
}
MAGICPODS_EOF

cat > "$APPDIR/qml/pages/MainPage.qml" << 'MAGICPODS_EOF'
import QtQuick 2.6
import Sailfish.Silica 1.0
import "../Modes.js" as Modes

Page {
    id: page

    property var backend

    readonly property var caps: backend ? backend.caps : ({})
    readonly property var battery: caps.battery
    readonly property var anc: caps.anc
    readonly property var adaptiveNoise: caps.adaptiveAudioNoise

    allowedOrientations: Orientation.All

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        PullDownMenu {
            MenuItem {
                text: qsTr("Reglages avances")
                visible: backend !== undefined && backend.hasDevice
                onClicked: pageStack.push(Qt.resolvedUrl("SettingsPage.qml"), { backend: page.backend })
            }

            MenuItem {
                text: qsTr("Rafraichir")
                onClicked: backend.refresh()
            }

            MenuItem {
                text: qsTr("Reconnecter le service")
                visible: backend !== undefined && !backend.linked
                onClicked: backend.reconnectSocket()
            }
        }

        Column {
            id: column

            width: page.width
            spacing: Theme.paddingMedium

            PageHeader {
                title: backend && backend.deviceName ? backend.deviceName : qsTr("MagicPods")
            }

            // Etats degrades : service absent, ou aucun appareil
            Label {
                width: parent.width - 2 * Theme.horizontalPageMargin
                x: Theme.horizontalPageMargin
                wrapMode: Text.WordWrap
                color: Theme.highlightColor
                visible: backend !== undefined && !backend.linked
                text: qsTr("Service indisponible. Verifiez que magicpodscore est demarre.")
            }

            Label {
                width: parent.width - 2 * Theme.horizontalPageMargin
                x: Theme.horizontalPageMargin
                wrapMode: Text.WordWrap
                color: Theme.secondaryHighlightColor
                visible: backend !== undefined && backend.linked && !backend.hasDevice
                text: qsTr("Aucun ecouteur compatible detecte. Connectez-les puis rafraichissez.")
            }

            Label {
                width: parent.width - 2 * Theme.horizontalPageMargin
                x: Theme.horizontalPageMargin
                wrapMode: Text.WordWrap
                color: Theme.secondaryHighlightColor
                visible: backend !== undefined && backend.hasDevice && !backend.deviceConnected
                text: qsTr("Ecouteurs connus mais non connectes.")
            }

            // Batterie
            Repeater {
                model: Modes.batteryEntries(page.battery)

                DetailItem {
                    label: modelData.label
                    value: modelData.level + " %"
                        + (modelData.charging ? " " + qsTr("(en charge)") : "")
                        + (modelData.stale ? " " + qsTr("(derniere valeur)") : "")
                }
            }

            // Controle du bruit
            SectionHeader {
                text: qsTr("Controle du bruit")
                visible: ancRepeater.count > 0
            }

            Flow {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                spacing: Theme.paddingSmall
                visible: ancRepeater.count > 0

                Repeater {
                    id: ancRepeater

                    model: Modes.ancEntries(page.anc)

                    Button {
                        text: modelData.label
                        highlighted: page.anc !== undefined && page.anc.selected === modelData.flag
                        enabled: page.anc === undefined || page.anc.readonly !== true
                        onClicked: backend.setCapability("anc", modelData.flag)
                    }
                }
            }

            // Intensite du mode adaptatif
            Slider {
                width: parent.width
                minimumValue: 0
                maximumValue: 100
                stepSize: 1
                label: qsTr("Bruit en mode adaptatif")
                valueText: Math.round(value) + " %"
                visible: page.adaptiveNoise !== undefined
                    && page.anc !== undefined
                    && page.anc.selected === Modes.ADAPTIVE
                value: page.adaptiveNoise ? page.adaptiveNoise.selected : 0
                onReleased: backend.setCapability("adaptiveAudioNoise", Math.round(value))
            }

            // Autres appareils connus du demon
            SectionHeader {
                text: qsTr("Appareils")
                visible: deviceRepeater.count > 1
            }

            Repeater {
                id: deviceRepeater

                model: backend ? backend.headphones : []

                ListItem {
                    width: page.width
                    visible: deviceRepeater.count > 1
                    contentHeight: Theme.itemSizeSmall

                    Label {
                        x: Theme.horizontalPageMargin
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.name
                        color: modelData.connected ? Theme.primaryColor : Theme.secondaryColor
                    }

                    onClicked: {
                        if (modelData.connected)
                            backend.disconnectDevice(modelData.address)
                        else
                            backend.connectDevice(modelData.address)
                    }
                }
            }
        }

        VerticalScrollDecorator {}
    }
}
MAGICPODS_EOF

cat > "$APPDIR/qml/pages/SettingsPage.qml" << 'MAGICPODS_EOF'
import QtQuick 2.6
import Sailfish.Silica 1.0

Page {
    id: page

    property var backend

    readonly property var caps: backend ? backend.caps : ({})

    allowedOrientations: Orientation.All

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        Column {
            id: column

            width: page.width
            spacing: Theme.paddingSmall

            PageHeader {
                title: qsTr("Reglages avances")
            }

            TextSwitch {
                text: qsTr("Conversation awareness")
                description: qsTr("Baisse le volume quand vous parlez")
                visible: caps.conversationAwareness !== undefined
                checked: caps.conversationAwareness ? caps.conversationAwareness.selected === true : false
                onClicked: backend.setCapability("conversationAwareness", checked)
            }

            TextSwitch {
                text: qsTr("Volume personnalise")
                visible: caps.personalizedVolume !== undefined
                checked: caps.personalizedVolume ? caps.personalizedVolume.selected === true : false
                onClicked: backend.setCapability("personalizedVolume", checked)
            }

            TextSwitch {
                text: qsTr("Reduction de bruit avec un seul ecouteur")
                visible: caps.ancOneAirPod !== undefined
                checked: caps.ancOneAirPod ? caps.ancOneAirPod.selected === true : false
                onClicked: backend.setCapability("ancOneAirPod", checked)
            }

            TextSwitch {
                text: qsTr("Balayage de volume")
                description: qsTr("Glisser sur la tige pour regler le volume")
                visible: caps.volumeSwipe !== undefined
                checked: caps.volumeSwipe ? caps.volumeSwipe.selected === true : false
                onClicked: backend.setCapability("volumeSwipe", checked)
            }

            Slider {
                width: parent.width
                minimumValue: 0
                maximumValue: 100
                stepSize: 1
                label: qsTr("Volume des tonalites")
                valueText: Math.round(value) + " %"
                visible: caps.toneVolume !== undefined
                value: caps.toneVolume ? caps.toneVolume.selected : 0
                onReleased: backend.setCapability("toneVolume", Math.round(value))
            }

            SectionHeader {
                text: qsTr("Audio")
                visible: caps.bluetoothCodec !== undefined
            }

            ComboBox {
                width: parent.width
                label: qsTr("Profil Bluetooth")
                visible: caps.bluetoothCodec !== undefined

                menu: ContextMenu {
                    Repeater {
                        model: caps.bluetoothCodec ? caps.bluetoothCodec.options : []

                        MenuItem {
                            // Chaque option est une paire [valeur, libelle]
                            text: modelData[1]
                            onClicked: backend.setCapability("bluetoothCodec", modelData[0])
                        }
                    }
                }
            }
        }

        VerticalScrollDecorator {}
    }
}
MAGICPODS_EOF

cat > "$APPDIR/qml/cover/CoverPage.qml" << 'MAGICPODS_EOF'
import QtQuick 2.6
import Sailfish.Silica 1.0
import "../Modes.js" as Modes

CoverBackground {
    id: cover

    property var backend

    readonly property var entries: backend ? Modes.batteryEntries(backend.caps.battery) : []

    Column {
        anchors.centerIn: parent
        width: parent.width - 2 * Theme.paddingMedium
        spacing: Theme.paddingSmall

        Label {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            truncationMode: TruncationMode.Fade
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.secondaryColor
            text: backend && backend.deviceName ? backend.deviceName : qsTr("MagicPods")
        }

        Repeater {
            model: cover.entries

            Label {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                font.pixelSize: Theme.fontSizeLarge
                text: modelData.label.substring(0, 1) + " " + modelData.level + "%"
                color: modelData.charging ? Theme.highlightColor : Theme.primaryColor
            }
        }

        Label {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            font.pixelSize: Theme.fontSizeExtraSmall
            color: Theme.secondaryColor
            visible: cover.entries.length === 0
            text: backend !== undefined && backend.linked ? qsTr("Aucun appareil") : qsTr("Service arrete")
        }
    }

    CoverActionList {
        enabled: backend !== undefined && backend.hasDevice && backend.caps.anc !== undefined

        CoverAction {
            iconSource: "image://theme/icon-cover-next"
            onTriggered: {
                var list = Modes.ancEntries(backend.caps.anc)

                if (list.length === 0)
                    return

                var current = backend.caps.anc.selected
                var index = 0

                for (var i = 0; i < list.length; i++) {
                    if (list[i].flag === current)
                        index = i
                }

                backend.setCapability("anc", list[(index + 1) % list.length].flag)
            }
        }
    }
}
MAGICPODS_EOF

cat > /usr/share/applications/harbour-magicpods.desktop << 'MAGICPODS_EOF'
[Desktop Entry]
Type=Application
X-Nemo-Application-Type=silica-qt5
Icon=harbour-magicpods
Exec=sailfish-qml harbour-magicpods
Name=MagicPods
Name[fr]=MagicPods
MAGICPODS_EOF

mkdir -p "$ICONROOT/86x86/apps"
base64 -d > "$ICONROOT/86x86/apps/harbour-magicpods.png" << 'MAGICPODS_EOF'
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
zkIamtAAAAAASUVORK5CYII=
MAGICPODS_EOF

mkdir -p "$ICONROOT/108x108/apps"
base64 -d > "$ICONROOT/108x108/apps/harbour-magicpods.png" << 'MAGICPODS_EOF'
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
MAGICPODS_EOF

mkdir -p "$ICONROOT/128x128/apps"
base64 -d > "$ICONROOT/128x128/apps/harbour-magicpods.png" << 'MAGICPODS_EOF'
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
MAGICPODS_EOF

mkdir -p "$ICONROOT/172x172/apps"
base64 -d > "$ICONROOT/172x172/apps/harbour-magicpods.png" << 'MAGICPODS_EOF'
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
MAGICPODS_EOF


chmod -R a+rX "$APPDIR"
chmod a+r /usr/share/applications/harbour-magicpods.desktop
chmod a+r "$ICONROOT"/*/apps/harbour-magicpods.png

echo "Installe dans $APPDIR"
echo "Lancez : sailfish-qml harbour-magicpods"
