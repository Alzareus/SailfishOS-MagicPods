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
