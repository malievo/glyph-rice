import QtQuick
import QtQuick.Window
import qs
import qs.components

// страница расширенных настроек: та же сцена 1920×1080, подпись капсом сверху, дальше свиток с растворением у краёв.
// Всё, что объявлено в странице, едет в свиток; Tab/стрелки — по контролам, фокус сам подтягивает свиток
FocusScope {
    id: root

    property string caption
    property string section // имя раздела prefs — для пустой страницы: "input · advanced"
    signal editZones // страница просит полноэкранный редактор зон; ловит Prefs
    default property alias rows: col.data

    readonly property alias flick: flick
    readonly property int pad: 16 // отступ у края свитка, когда фокус подтягивает контрол

    function ensureVisible(item) {
        if (!item || !flick) return;
        const p = item.mapToItem(col, 0, 0);
        if (p.y < flick.contentY + root.pad) flick.contentY = Math.max(0, p.y - root.pad);
        else if (p.y + item.height > flick.contentY + flick.height - root.pad)
            flick.contentY = Math.min(Math.max(0, flick.contentHeight - flick.height), p.y + item.height - flick.height + root.pad);
    }
    function inside(item) {
        for (let p = item; p; p = p.parent) if (p === root) return true;
        return false;
    }
    // tab/клик по контролу — свиток сам подтягивает его к краю. Наблюдатель — Item: attached Window
    // внутри не-Item (Connections) окна не видит
    Item {
        id: watch
        visible: false
        readonly property Item focused: Window.activeFocusItem
        onFocusedChanged: if (focused && root.inside(focused)) Qt.callLater(root.ensureVisible, focused)
    }

    Lb { id: cap; text: root.caption || (root.section ? root.section.toLowerCase() + " · advanced" : "") }

    Flickable {
        id: flick
        y: cap.height + 30
        width: parent.width - 60
        height: parent.height - y
        contentWidth: width
        contentHeight: col.height
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick

        Column {
            id: col
            width: flick.width
            spacing: 0
        }

        Lb {
            visible: col.children.length === 0
            y: 40
            text: "nothing deeper here — the surface has it all"
        }
    }

    // растворы: фон непрозрачный, маски не нужны
    Rectangle {
        x: 0
        y: flick.y
        width: flick.width
        height: 32
        visible: flick.contentY > 0.5
        gradient: Gradient {
            GradientStop { position: 0; color: Theme.bg }
            GradientStop { position: 1; color: "transparent" }
        }
    }
    Rectangle {
        x: 0
        y: flick.y + flick.height - 32
        width: flick.width
        height: 32
        visible: flick.contentY < flick.contentHeight - flick.height - 0.5
        gradient: Gradient {
            GradientStop { position: 0; color: "transparent" }
            GradientStop { position: 1; color: Theme.bg }
        }
    }

    // индикатор свитка — тонкая линия справа
    Item {
        id: scroll
        visible: flick.contentHeight > flick.height + 2
        x: flick.width + 24
        y: flick.y
        width: 2
        height: flick.height
        Rectangle { anchors.fill: parent; radius: 1; color: Theme.s3; opacity: 0.4 }
        Rectangle {
            width: 2
            radius: 1
            color: Theme.grey
            height: Math.max(48, scroll.height * flick.height / Math.max(1, flick.contentHeight))
            y: (scroll.height - height) * (flick.contentY / Math.max(1, flick.contentHeight - flick.height))
        }
    }
}
