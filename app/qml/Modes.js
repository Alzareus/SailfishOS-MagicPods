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
