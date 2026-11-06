import QtQuick
import Quickshell
import Quickshell.Wayland
import qs

// горячий угол: курсор задержался в нижних правых 10% экрана — быстрые настройки выезжают (Quick.peek)
PanelWindow {
    id: root

    signal triggered

    visible: Theme.state.quickHover
    anchors { right: true; bottom: true }
    implicitWidth: Math.round(screen.width * 0.1)
    implicitHeight: 2
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "glyph-hot"

    HoverHandler { id: hov; onHoveredChanged: hovered ? dwell.restart() : dwell.stop() }
    Timer { id: dwell; interval: 150; onTriggered: if (hov.hovered) root.triggered() }
}
