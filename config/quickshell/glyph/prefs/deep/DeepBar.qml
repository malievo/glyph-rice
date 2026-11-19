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
    readonly property int zoneTopPx: Theme.state.barReveal === "default" ? 150 : Theme.state.barZoneTop
    readonly property int zoneBottomPx: Theme.state.barReveal === "default" ? 150 : Theme.state.barZoneBottom

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
        height: 92

        Column {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8
            Lb { text: `top · ${barDeep.zoneTopPx} px`; px: 10; color: Theme.grey }
            Lb { text: `bottom · ${barDeep.zoneBottomPx} px`; px: 10; color: Theme.grey }
            Lb { visible: Theme.state.barZoneSync; text: "sync on"; px: 10; color: Theme.mute }
        }

        Rectangle {
            id: edit
            visible: Theme.state.barReveal !== "edge"
            anchors.verticalCenter: parent.verticalCenter
            x: 220
            width: 240
            height: 64
            radius: Theme.corner(32)
            color: editMa.containsMouse || activeFocus ? Theme.s3 : Theme.s2
            border { width: activeFocus ? 1 : 0; color: Theme.fg }
            activeFocusOnTab: true
            Keys.onPressed: e => {
                if (e.key !== Qt.Key_Return && e.key !== Qt.Key_Enter && e.key !== Qt.Key_Space) return;
                Sys.zoneEdit = true;
                e.accepted = true;
            }
            Lb { anchors.centerIn: parent; text: "edit zones"; px: 10; color: edit.activeFocus || editMa.containsMouse ? Theme.fg : Theme.grey }
            MouseArea {
                id: editMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: Sys.zoneEdit = true
            }
        }
    }
    Lb { visible: barDeep.zoneOK && Theme.state.barReveal !== "edge"; topPadding: 8; text: "opens the full-screen editor over your wallpaper · drag or wheel · steps of 10 px"; px: 10 }
    Lb { visible: barDeep.zoneOK && Theme.state.barReveal === "edge"; topPadding: 8; text: "edge uses the whole side — pick default or custom to edit zones"; px: 10 }
}
