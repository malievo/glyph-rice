import QtQuick
import "deep"

// реестр глубоких страниц: имя раздела prefs → страница. Дверь "advanced" видна только в разделах с записью,
// так что у шелла без кастомных страниц её нет вовсе.
// Новая страница: файл в deep/ (наследник DeepPage), Component здесь и строка в bySection; basic не трогать.
QtObject {
    readonly property Component bar: Component { DeepBar {} }
    readonly property Component look: Component { DeepLook {} }
    readonly property Component shell: Component { DeepShell {} }
    readonly property Component display: Component { DeepDisplay {} }
    readonly property Component empty: Component { DeepPage {} }

    readonly property var bySection: ({
        "BAR": bar,
        "LOOK": look,
        "SHELL": shell,
        "DISPLAY": display
    })

    function has(section) { return bySection[section] !== undefined; }
}
