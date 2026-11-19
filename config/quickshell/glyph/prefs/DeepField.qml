import QtQuick
import qs
import qs.components

// текстовое поле глубоких настроек: пилюля с путём; пусто — берётся default (подсказка в placeholder)
Rectangle {
    id: root

    property string text
    property string placeholder
    signal edited(string text)

    width: 520
    height: 56
    radius: Theme.corner(28)
    color: Theme.s2
    border { width: input.activeFocus ? 1 : 0; color: Theme.fg }

    Text {
        anchors { fill: parent; leftMargin: 22; rightMargin: 22 }
        verticalAlignment: Text.AlignVCenter
        visible: input.text.length === 0
        text: root.placeholder
        font { family: Theme.ui; pixelSize: 17 }
        color: Theme.mute
        elide: Text.ElideRight
    }

    TextInput {
        id: input
        anchors { fill: parent; leftMargin: 22; rightMargin: 22 }
        verticalAlignment: TextInput.AlignVCenter
        font { family: Theme.ui; pixelSize: 17 }
        color: Theme.fg
        selectionColor: Theme.s3
        selectedTextColor: Theme.ink
        clip: true
        text: root.text
        activeFocusOnTab: true
        onTextEdited: root.edited(text)
        cursorDelegate: Rectangle { width: 2; height: 18; color: Theme.fg }
    }
}
