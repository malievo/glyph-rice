import QtQuick
import qs
import qs.components
import qs.settings
import ".."

// DISPLAY глубже: ночник — auto/on/off и температура. В basic этого нет: апстримный тумблер не выражает auto
DeepPage {
    caption: "display · advanced · night light"

    DeepGroup { text: "night light" }

    Item {
        width: parent.width
        height: 84

        Pick {
            anchors.verticalCenter: parent.verticalCenter
            label: "mode"
            opts: ["auto", "on", "off"]
            cur: ["auto", "on", "off"].indexOf(Rules.store.nightMode)
            onPicked: i => { Rules.store.nightMode = ["auto", "on", "off"][i]; Rules.night(); }
        }
    }

    Row {
        spacing: 56
        Dial {
            label: "warmth · k · all screens"
            from: 2500
            to: 6500
            step: 100
            value: Rules.store.warmth
            onMoved: v => { Rules.store.warmth = v; if (Rules.store.nightMode === "on") Rules.night(); }
        }
    }
    Lb { topPadding: 18; text: "auto follows the sun · hyprsunset"; px: 10 }
}
