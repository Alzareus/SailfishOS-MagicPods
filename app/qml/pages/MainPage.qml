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
