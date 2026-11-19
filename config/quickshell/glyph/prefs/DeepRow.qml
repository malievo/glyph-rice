import QtQuick
import qs
import qs.components

// строка формы глубоких настроек: метка (и подпись) слева, контрол справа, волосяная линия снизу.
// Контрол — единственный ребёнок строки; его фокус подсвечивает метку
Item {
    id: root

    property string label
    property string sub
    default property alias controlData: slot.data
    readonly property Item control: slot.children.length ? slot.children[0] : null
    readonly property bool hot: (root.control?.activeFocus ?? false) || hover.hovered

    width: parent ? parent.width : 0
    height: Math.max(80, (root.control?.height ?? 0) + 24)

    Column {
        anchors.verticalCenter: parent.verticalCenter
        spacing: 4
        Lb {
            text: root.label
            color: root.hot ? Theme.fg : Theme.grey
            Behavior on color { ColorAnimation { duration: Theme.t } }
        }
        Lb { visible: !!root.sub; text: root.sub; px: 10 }
    }

    Item {
        id: slot
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: childrenRect.width
        height: childrenRect.height
    }

    Rectangle {
        anchors.bottom: parent.bottom
        width: parent.width
        height: 1
        color: Theme.s3
        opacity: 0.5
    }

    HoverHandler { id: hover }
}
