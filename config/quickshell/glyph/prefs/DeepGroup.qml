import QtQuick
import qs
import qs.components

// шапка группы глубоких настроек: капсом и линией до края — как разделы в Nothing OS
Item {
    id: root

    property string text

    width: parent ? parent.width : 0
    height: 58

    Lb { y: 24; text: root.text }

    Rectangle {
        anchors.bottom: parent.bottom
        width: parent.width
        height: 1
        color: Theme.s3
        opacity: 0.5
    }
}
