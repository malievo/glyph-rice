import QtQuick
import Quickshell
import qs
import qs.components
import ".."

// BAR глубже: всё кастомное, чего нет в upstream-bar, — геометрия пилюли, удержание и автоскрытие.
// Живое превью — толщина, зазор и край видны сразу
DeepPage {
    id: barDeep
    caption: "bar · advanced · geometry, hold and auto-hide"

    readonly property bool zoneOK: Theme.state.barAt !== "top" && Sys.scrollLayout
    readonly property int scrH: Quickshell.screens[0]?.height ?? 1440
    readonly property int zoneTopPx: Theme.state.barReveal === "default" ? 150 : Theme.state.barZoneTop
    readonly property int zoneBottomPx: Theme.state.barReveal === "default" ? 150 : Theme.state.barZoneBottom
    readonly property int minMid: 240
    readonly property int step: 10
    function snap(v) { return Math.round(v / step) * step }
    function zoneMax(side) {
        return Theme.state.barZoneSync ? (scrH - minMid) / 2
            : side === "top" ? scrH - barDeep.zoneBottomPx - minMid
            : scrH - barDeep.zoneTopPx - minMid;
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

    // старые пер-пиксельные значения — к шагу ручек
    Component.onCompleted: if (Theme.state.barReveal === "custom") {
        const t = snap(Theme.state.barZoneTop);
        const b = snap(Theme.state.barZoneBottom);
        if (t !== Theme.state.barZoneTop) Theme.state.barZoneTop = t;
        if (b !== Theme.state.barZoneBottom) Theme.state.barZoneBottom = b;
    }

    Item {
        width: 560
        height: 316

        Rectangle {
            anchors.fill: parent
            radius: 18
            color: Theme.s1
            border { width: 1; color: Theme.s2 }

            Rectangle {
                readonly property real u: 560 / 1920
                readonly property bool onTop: Theme.state.barAt === "top"
                readonly property real t: Math.max(4, Theme.barThick * u)
                readonly property real g: Math.max(1, Theme.barGap * u)
                x: g
                y: g
                width: onTop ? 560 - 2 * g : t
                height: onTop ? t : 316 - 2 * g
                radius: Theme.corner(Math.min(width, height) / 2)
                color: Theme.s3
                border { width: 1; color: Theme.s3 }
                Behavior on width { NumberAnimation { duration: Theme.t; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.glide } }
                Behavior on height { NumberAnimation { duration: Theme.t; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.glide } }
            }
        }
    }
    Lb { topPadding: 14; text: "the bar as it sits now — changes are live"; px: 10 }

    DeepGroup { text: "size" }

    Item {
        width: parent.width
        height: 84

        Pick {
            anchors.verticalCenter: parent.verticalCenter
            label: "size"
            opts: ["theme", "fit", "px"]
            cur: ["theme", "fit", "px"].indexOf(Theme.state.barSizeMode)
            onPicked: i => Theme.state.barSizeMode = ["theme", "fit", "px"][i]
        }
    }

    Row {
        spacing: 56
        // px — толщина в логических пикселях, одинаковая на любом экране; 48 — минимум, где контент влезает
        Dial { label: "thickness · px"; from: 48; to: 96; value: Theme.state.barSizePx; onMoved: v => Theme.state.barSizePx = v }
        Dial { label: "edge gap · px"; from: 0; to: 24; value: Theme.state.barGapPx; onMoved: v => Theme.state.barGapPx = v }
    }
    Lb { topPadding: 18; text: "thickness works with size = px · gap is always px"; px: 10 }

    DeepGroup { text: "auto-hide" }

    Item {
        width: parent.width
        height: 84

        Pick {
            id: vis
            anchors.verticalCenter: parent.verticalCenter
            label: "mode"
            opts: Sys.smartOK ? ["always", "hidden", "smart"] : ["always", "hidden"]
            cur: opts.indexOf(Theme.state.barMode)
            onPicked: i => Theme.state.barMode = vis.opts[i]
        }
    }

    Row {
        spacing: 56
        Dial { label: "hold · ms"; from: 200; to: 2000; step: 100; value: Theme.state.barHoldMs; onMoved: v => Theme.state.barHoldMs = v }
    }
    Lb { topPadding: 18; text: "hold — how long the cursor rests at the edge before the bar comes out · smart needs the scrolling layout"; px: 10 }

    DeepGroup { text: "edge reveal" }

    Lb { visible: !barDeep.zoneOK; text: "hover zones — vertical bar with the scrolling layout only"; px: 10 }

    Item {
        visible: barDeep.zoneOK
        width: parent.width
        height: 84

        Pick {
            id: reveal
            anchors.verticalCenter: parent.verticalCenter
            label: "reveal"
            opts: ["edge", "default", "custom"]
            cur: opts.indexOf(Theme.state.barReveal)
            onPicked: i => Theme.state.barReveal = reveal.opts[i]
        }
    }

    Item {
        visible: barDeep.zoneOK
        width: parent.width
        height: 372

        Rectangle {
            id: scr
            width: 220
            height: 320
            radius: 18
            color: Theme.bg
            border { width: 1; color: Theme.s3 }
            readonly property real k: 292 / barDeep.scrH
            readonly property bool edge: Theme.state.barReveal === "edge"

            Image {
                anchors.fill: parent
                anchors.margins: 10
                fillMode: Image.Tile
                source: "data:image/svg+xml," + encodeURIComponent(`<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16"><circle cx="8" cy="8" r="1" fill="#${Theme.hex(Theme.s2)}"/></svg>`)
            }

            // сама полоска и зоны показа
            Rectangle { x: 14; y: 14; width: 8; height: 292; radius: 4; color: Theme.s3; opacity: scr.edge ? 0.4 : 1 }
            Rectangle {
                visible: scr.edge
                x: 14; y: 14; width: 8; height: 292; radius: 4; color: Theme.fg; opacity: 0.85
            }
            Rectangle {
                visible: !scr.edge
                x: 14; y: 14; width: 8; radius: 4
                height: Math.max(0, Math.min(292, barDeep.zoneTopPx * scr.k))
                color: Theme.fg; opacity: 0.85
            }
            Rectangle {
                visible: !scr.edge
                x: 14; y: 14 + 292 - height; width: 8; radius: 4
                height: Math.max(0, Math.min(292, barDeep.zoneBottomPx * scr.k))
                color: Theme.fg; opacity: 0.85
            }

            // колесо по всей белой зоне: верх — вниз растит, низ — вверх растит
            MouseArea {
                visible: !scr.edge
                x: 4; y: 14; width: 32
                height: Math.max(0, Math.min(292, barDeep.zoneTopPx * scr.k))
                acceptedButtons: Qt.NoButton
                onWheel: w => {
                    const d = w.angleDelta.y || w.pixelDelta.y;
                    if (!d) return;
                    barDeep.setZone("top", barDeep.zoneTopPx + (d > 0 ? -barDeep.step : barDeep.step));
                    w.accepted = true;
                }
            }
            MouseArea {
                visible: !scr.edge
                x: 4; y: 14 + 292 - height; width: 32
                height: Math.max(0, Math.min(292, barDeep.zoneBottomPx * scr.k))
                acceptedButtons: Qt.NoButton
                onWheel: w => {
                    const d = w.angleDelta.y || w.pixelDelta.y;
                    if (!d) return;
                    barDeep.setZone("bottom", barDeep.zoneBottomPx + (d > 0 ? barDeep.step : -barDeep.step));
                    w.accepted = true;
                }
            }

            // ручки зон: тянуть — режим custom, значение меняется; захват шире линии
            Rectangle {
                visible: !scr.edge
                x: 0; y: 14 + Math.min(292, barDeep.zoneTopPx * scr.k) - 10
                width: 36; height: 20; radius: 10
                color: "transparent"
                Rectangle { anchors.centerIn: parent; width: 28; height: 4; radius: 2; color: Theme.fg }
                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    preventStealing: true
                    cursorShape: Qt.SizeVerCursor
                    property real start: 0
                    property real y0: 0
                    onPressed: m => { start = barDeep.zoneTopPx; y0 = m.y }
                    onPositionChanged: m => { if (pressed) barDeep.setZone("top", start + (m.y - y0) / scr.k) }
                    onWheel: w => {
                        const d = w.angleDelta.y || w.pixelDelta.y;
                        if (!d) return;
                        barDeep.setZone("top", barDeep.zoneTopPx + (d > 0 ? -barDeep.step : barDeep.step));
                        w.accepted = true;
                    }
                }
            }
            Rectangle {
                visible: !scr.edge
                x: 0; y: 14 + 292 - Math.min(292, barDeep.zoneBottomPx * scr.k) - 10
                width: 36; height: 20; radius: 10
                color: "transparent"
                Rectangle { anchors.centerIn: parent; width: 28; height: 4; radius: 2; color: Theme.fg }
                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    preventStealing: true
                    cursorShape: Qt.SizeVerCursor
                    property real start: 0
                    property real y0: 0
                    onPressed: m => { start = barDeep.zoneBottomPx; y0 = m.y }
                    onPositionChanged: m => { if (pressed) barDeep.setZone("bottom", start - (m.y - y0) / scr.k) }
                    onWheel: w => {
                        const d = w.angleDelta.y || w.pixelDelta.y;
                        if (!d) return;
                        barDeep.setZone("bottom", barDeep.zoneBottomPx + (d > 0 ? barDeep.step : -barDeep.step));
                        w.accepted = true;
                    }
                }
            }

            Lb { anchors.centerIn: parent; text: "scroll"; px: 10; color: Theme.mute }
        }

        Lb {
            visible: !scr.edge
            x: 236; y: 12
            text: `top · ${Math.round(barDeep.zoneTopPx)} px`; px: 10; color: Theme.grey
        }
        Lb {
            visible: !scr.edge
            x: 236; y: 298
            text: `bottom · ${Math.round(barDeep.zoneBottomPx)} px`; px: 10; color: Theme.grey
        }
        Lb { visible: scr.edge; x: 236; y: 12; text: "full edge"; px: 10; color: Theme.grey }

        Toggle {
            visible: !scr.edge
            x: 236; y: 150; width: 200
            text: "sync zones"
            on: Theme.state.barZoneSync
            onFlip: {
                Theme.state.barZoneSync = !Theme.state.barZoneSync;
                if (Theme.state.barZoneSync) {
                    const v = Math.min((barDeep.scrH - barDeep.minMid) / 2,
                                       barDeep.snap((barDeep.zoneTopPx + barDeep.zoneBottomPx) / 2));
                    Theme.state.barZoneTop = v;
                    Theme.state.barZoneBottom = v;
                }
            }
        }
    }
    Lb { visible: barDeep.zoneOK; topPadding: 10; text: "top and bottom reveal the bar · the middle stays with the lane · drag a handle or wheel over a zone · steps of 10 px"; px: 10 }
}
