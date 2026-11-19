import QtQuick
import Quickshell
import qs
import qs.components

// полноэкранный редактор зон края: обои без виджетов и баров, ручки по всей высоте слева.
// Значения — px монитора; шаг 10; верх — колесо вниз растит, низ — колесо вверх растит.
FocusScope {
    id: root

    property var screen
    property string monName
    signal done

    focus: visible
    Keys.onPressed: e => {
        if (e.key === Qt.Key_Escape || e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { root.done(); e.accepted = true; }
        else if (e.key === Qt.Key_Space) {
            Theme.state.barZoneSync = !Theme.state.barZoneSync;
            if (Theme.state.barZoneSync) root.equalize();
            e.accepted = true;
        }
    }

    readonly property var mon: screen ?? Quickshell.screens[0]
    readonly property int scrH: mon?.height ?? 1440
    readonly property real k: height > 0 ? scrH / height : 1
    readonly property int minMid: 240
    readonly property int step: 10
    readonly property int band: 420
    readonly property int zoneTopPx: Theme.state.barReveal === "default" ? 150 : Theme.state.barZoneTop
    readonly property int zoneBottomPx: Theme.state.barReveal === "default" ? 150 : Theme.state.barZoneBottom

    function snap(v) { return Math.round(v / step) * step }
    function zoneMax(side) {
        return Theme.state.barZoneSync ? (scrH - minMid) / 2
            : side === "top" ? scrH - zoneBottomPx - minMid
            : scrH - zoneTopPx - minMid;
    }
    function setZone(side, v) {
        const z = Math.min(zoneMax(side), snap(Math.max(0, v)));
        Theme.state.barReveal = "custom";
        if (Theme.state.barZoneSync) {
            Theme.state.barZoneTop = z;
            Theme.state.barZoneBottom = z;
        } else if (side === "top") Theme.state.barZoneTop = z;
        else Theme.state.barZoneBottom = z;
    }
    function equalize() {
        const v = Math.min((scrH - minMid) / 2, snap((zoneTopPx + zoneBottomPx) / 2));
        Theme.state.barZoneTop = v;
        Theme.state.barZoneBottom = v;
    }

    onVisibleChanged: {
        if (!visible) return;
        Qt.callLater(root.forceActiveFocus);
        if (Theme.state.barReveal === "custom") {
            const t = snap(Theme.state.barZoneTop);
            const b = snap(Theme.state.barZoneBottom);
            if (t !== Theme.state.barZoneTop) Theme.state.barZoneTop = t;
            if (b !== Theme.state.barZoneBottom) Theme.state.barZoneBottom = b;
        }
    }

    // ---- обои: та же подложка, что у дома, без виджетов ----
    Stage {
        Rectangle { anchors.fill: parent; color: Theme.bg }
        Image {
            visible: Theme.state.grid && !wall.opaque
            anchors.fill: parent
            fillMode: Image.Tile
            source: "data:image/svg+xml," + encodeURIComponent(`<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32"><circle cx="16" cy="16" r="1.5" fill="#${Theme.hex(Theme.s2)}"/></svg>`)
        }
        Wall {
            id: wall
            anchors.fill: parent
            path: Theme.wallSrc(Theme.scr(root.monName || root.mon?.name, "wall"))
            animate: false
        }
    }

    Item {
        id: view
        anchors.fill: parent

        readonly property real pk: root.scrH > 0 ? height / root.scrH : 1
        readonly property real topY: Math.max(0, Math.min(height, root.zoneTopPx * pk))
        readonly property real botY: Math.max(0, Math.min(height, height - root.zoneBottomPx * pk))

        // зоны: светлее у края, к центру растворяются
        Rectangle {
            x: 0; y: 0; width: root.band; height: view.topY
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.22) }
                GradientStop { position: 1; color: "transparent" }
            }
        }
        Rectangle {
            x: 0; y: view.botY; width: root.band; height: view.height - view.botY
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.22) }
                GradientStop { position: 1; color: "transparent" }
            }
        }

        Rectangle { x: 0; y: 0; width: 1; height: view.height; color: Theme.fg; opacity: 0.3 }
        Rectangle { x: 0; y: 0; width: 3; height: view.topY; color: Theme.fg; opacity: 0.9 }
        Rectangle { x: 0; y: view.botY; width: 3; height: view.height - view.botY; color: Theme.fg; opacity: 0.9 }
        Rectangle { x: 0; y: Math.max(0, Math.min(view.height - 2, view.topY - 1)); width: root.band; height: 2; color: Theme.fg; opacity: 0.8 }
        Rectangle { x: 0; y: Math.max(0, Math.min(view.height - 2, view.botY - 1)); width: root.band; height: 2; color: Theme.fg; opacity: 0.8 }

        Rectangle {
            x: 24; y: Math.max(8, view.topY - 22)
            width: 230; height: 44; radius: 22; color: Theme.fg
            Lb { anchors.centerIn: parent; text: `top · ${root.zoneTopPx} px`; px: 12; color: Theme.ink }
        }
        Rectangle {
            x: 24; y: Math.min(view.height - 52, view.botY - 22)
            width: 230; height: 44; radius: 22; color: Theme.fg
            Lb { anchors.centerIn: parent; text: `bottom · ${root.zoneBottomPx} px`; px: 12; color: Theme.ink }
        }
        Lb { x: 24; anchors.verticalCenter: parent.verticalCenter; text: "scroll"; px: 10; color: Theme.fg; opacity: 0.55 }

        // тянем ручки, колесо — по зоне; фиксированная полоса, чтобы ручка не убегала из-под курсора
        MouseArea {
            id: edge
            x: 0; y: 0; width: root.band; height: parent.height
            hoverEnabled: true
            preventStealing: true
            cursorShape: Qt.SizeVerCursor
            property string active: ""
            property int startVal: 0
            property real startY: 0

            onPressed: m => {
                const nearTop = m.y <= view.topY + 40;
                const nearBottom = m.y >= view.botY - 40;
                active = nearTop && nearBottom ? (m.y < height / 2 ? "top" : "bottom")
                    : nearTop ? "top" : nearBottom ? "bottom" : "";
                if (active !== "") {
                    startVal = active === "top" ? root.zoneTopPx : root.zoneBottomPx;
                    startY = m.y;
                }
            }
            onPositionChanged: m => {
                if (!pressed || active === "") return;
                const dy = (m.y - startY) * root.k;
                if (active === "top") root.setZone("top", startVal + dy);
                else root.setZone("bottom", startVal - dy);
            }
            onReleased: active = ""
            onCanceled: active = ""
            onWheel: w => {
                const d = w.angleDelta.y || w.pixelDelta.y;
                if (!d) return;
                if (w.y <= view.topY + 40) root.setZone("top", root.zoneTopPx + (d > 0 ? -root.step : root.step));
                else if (w.y >= view.botY - 40) root.setZone("bottom", root.zoneBottomPx + (d > 0 ? root.step : -root.step));
                else return;
                w.accepted = true;
            }
        }
    }

    // ---- пульт справа, чтобы не закрывать кромку ----
    Rectangle {
        x: parent.width - 368
        y: 36
        width: 320
        height: 268
        radius: 22
        color: Theme.s1
        border { width: 1; color: Theme.s2 }

        Lb { x: 20; y: 18; text: "edit edge zones"; px: 12; color: Theme.fg }
        Lb { x: 20; y: 46; text: "drag or wheel a zone"; px: 10; color: Theme.grey }
        Lb { x: 20; y: 70; text: `top ${root.zoneTopPx} px · bottom ${root.zoneBottomPx} px`; px: 10; color: Theme.grey }

        Toggle {
            x: 20; y: 100; width: 280
            text: "sync zones"
            on: Theme.state.barZoneSync
            onFlip: {
                Theme.state.barZoneSync = !Theme.state.barZoneSync;
                if (Theme.state.barZoneSync) root.equalize();
            }
        }

        Lb { x: 20; y: 170; text: "space · sync"; px: 10; color: Theme.grey }

        Rectangle {
            id: doneBtn
            x: 20; y: 188; width: 150; height: 52; radius: 26
            readonly property bool hot: doneMa.containsMouse
            color: Theme.fg
            activeFocusOnTab: true
            border { width: doneBtn.hot || doneBtn.activeFocus ? 2 : 0; color: Theme.ink }
            Keys.onPressed: e => {
                if (e.key !== Qt.Key_Return && e.key !== Qt.Key_Enter && e.key !== Qt.Key_Space) return;
                root.done();
                e.accepted = true;
            }
            Lb { anchors.centerIn: parent; text: "done"; px: 12; color: Theme.ink }
            MouseArea {
                id: doneMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.done()
            }
        }
        Lb { x: 188; y: 204; text: "esc / enter"; px: 10; color: Theme.grey }
    }
}
