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
