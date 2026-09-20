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
