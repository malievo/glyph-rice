import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Networking
import Quickshell.Services.UPower
import Quickshell.Wayland
import qs
import qs.components
import qs.services
import qs.settings

// бар: пилюля у левого края или сверху — Theme.state.barAt. Первым знак (кольцо из 16 точек) — лаунчер, центр краснеет,
// пока запись или микрофон. Воркспейсы точками, заголовок окна, часы Doto по центру, трей последним — клик открывает быстрые настройки.
// Сбоку всё столбиком, сверху — строкой. Что в трее и в каком порядке, есть ли заголовок — Theme.state (настройки, раздел BAR)
PanelWindow {
    id: root

    signal markClicked
    signal trayClicked
    signal powerClicked
    signal clockClicked
    signal vpnClicked

    readonly property bool vert: Theme.state.barAt !== "top" // всё, кроме top (и неизвестное), — слева
    anchors { left: true; right: !vert; top: true; bottom: vert }
    implicitWidth: Math.ceil(Theme.barSpan * Theme.s)  // сбоку: зазор + пилюля
    implicitHeight: Math.ceil(Theme.barSpan * Theme.s) // сверху
    color: "transparent"
    WlrLayershell.namespace: "glyph-bar"

    // стол своего монитора (не глобальный фокус): на втором мониторе показывается его собственный стол
    readonly property var mon: Hyprland.monitorFor(screen) ?? Hyprland.monitors.values.find(m => m.name === screen?.name) ?? null
    readonly property int active: mon?.activeWorkspace?.id ?? Hyprland.focusedWorkspace?.id ?? 0
    // группа из десяти столов, к которой относится активный (1–10, 11–20, …)
    readonly property int base: Math.floor((Math.max(active, 1) - 1) / 10) * 10
    // шесть точек, больше — если занят или открыт дальний (в пределах группы)
    readonly property int count: Math.min(10, Math.max(6, active - base, ...Hyprland.workspaces.values.filter(w => w.toplevels.values.length && w.id > base && w.id <= base + 10).map(w => w.id - base)))
    readonly property var top: ToplevelManager.activeToplevel
    readonly property var bat: UPower.displayDevice
    readonly property var wifi: Networking.devices.values.find(d => d.type === DeviceType.Wifi) ?? null

    // ---- смена раскладки при скрытом баре: короткая пилюля у края, чтобы не терять en/ru ----
    property bool flashArmed: false
    property string flashText: ""
    property real flashOn: 0
    Behavior on flashOn { NumberAnimation { duration: root.shown ? 0 : (root.flashOn ? 150 : 250); easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.glide } }
    Timer { running: true; interval: 1500; onTriggered: root.flashArmed = true }
    Timer { id: flashT; interval: 900; onTriggered: root.flashOn = 0 }
    onShownChanged: if (root.shown) { flashT.stop(); root.flashOn = 0; deskT.stop(); root.deskOn = 0; }
    Connections {
        target: Sys
        function onLayoutChanged() {
            if (!root.flashArmed || root.shown) return;
            if (Hyprland.focusedMonitor?.name !== root.screen?.name) return;
            root.flashText = Sys.layout.toUpperCase();
            root.flashOn = 1;
            flashT.restart();
        }
    }
    // ---- смена стола при скрытом баре: мини-кластер точек, как в баре (текущий вытянут) ----
    property bool deskArmed: false
    property real deskOn: 0
    Behavior on deskOn { NumberAnimation { duration: root.deskOn ? 150 : 250; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.glide } }
    Timer { running: true; interval: 1500; onTriggered: root.deskArmed = true }
    Timer { id: deskT; interval: 900; onTriggered: root.deskOn = 0 }
    onActiveChanged: {
        if (!root.deskArmed || Hyprland.focusedMonitor?.name !== root.screen?.name) return;
        root.deskOn = 1;
        deskT.restart();
    }

    // ---- спец-стол: точки блюрятся, поверх — имя; при скрытом баре — постоянный чип, при выходе — вспышка столов ----
    property string specialWs: ""
    readonly property bool isSpecial: root.specialWs !== ""
    readonly property string specialText: root.specialName(root.specialWs)
    property real specLook: root.isSpecial ? 1 : 0
    Behavior on specLook { NumberAnimation { duration: Theme.t; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.glide } }
    function specialName(n) {
        const m = ({ music: "MUSIC", communication: "COMM", todo: "TODO", sysmon: "SYS", special: "SPEC" });
        return (m[n] ?? (n.length > 6 ? n.slice(0, 6) : n)).toUpperCase();
    }
    function syncSpecial() { const n = (mon?.lastIpcObject?.specialWorkspace?.name ?? "").replace(/^special:/, ""); if (n !== root.specialWs) root.specialWs = n; }
    onIsSpecialChanged: {
        if (root.isSpecial || !root.deskArmed || Hyprland.focusedMonitor?.name !== root.screen?.name) return;
        root.deskOn = 1;
        deskT.restart();
    }
    Connections {
        target: Hyprland
        function onRawEvent(e) {
            if (e.name !== "activespecial") return;
            const p = (e.data ?? "").split(",");
            if (p[1] !== root.screen?.name) return;
            root.specialWs = (p[0] ?? "").replace(/^special:/, "").trim();
        }
    }
    // чип при скрытом баре: спец-стол — постоянный, обычный — по таймеру вспышки
    property real wsChip: (root.isSpecial && !root.shown) ? 1 : root.deskOn
    Behavior on wsChip { NumberAnimation { duration: root.shown ? 0 : (root.wsChip ? 150 : 250); easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.glide } }

    // ---- автоскрытие (Theme.state.barMode): always — как обычно, с местом под бар; hidden — прячется, когда на этом
    // столе есть окна; smart — когда лента заполнена (fullscreen/maximized, колонка во всю ширину или две плитки).
    // Пока бар виден по режиму — он держит место под собой; исключение — вертикальный auto-бар с одним
    // центрированным окном: бокового поля хватает, окно остаётся по центру. Скрыт — окна растягиваются;
    // выезд по наведению и с deck ложится поверх, без рефлоу ----
    readonly property string mode: Theme.state.barMode
    readonly property bool auto: mode !== "always"
    readonly property bool full: mon?.activeWorkspace?.hasFullscreen ?? false
    readonly property var wins: Hyprland.toplevels.values.filter(t => t.workspace?.id === root.active)
    readonly property var tiles: root.wins.filter(t => !(t.lastIpcObject?.floating ?? false))
    // firefox и игры — колонка 1.0 в ленте, а не maximized: полноширинное окно считаем заполнением.
    // У окон, открытых до старта шелла, lastIpcObject без size — ширину берём из свежего hyprctl clients
    property var geo: ({})
    property var normal: ({}) // ширины, виденные вне maximized: по ним решаем сразу после выхода
    Process {
        id: clients
        command: ["hyprctl", "clients", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                const m = {};
                for (const c of JSON.parse(text || "[]")) m[String(c.address ?? "").replace(/^0x/, "")] = c.size?.[0] ?? 0;
                root.geo = m;
                if (!root.full) root.normal = m;
            }
        }
    }
    Timer { running: root.auto && root.mode === "smart"; interval: 2000; repeat: true; triggeredOnStart: true; onTriggered: if (!clients.running) clients.running = true }
    onWinsChanged: if (root.auto && root.mode === "smart" && !clients.running) clients.running = true
    // Super+F туда-сюда: ширина окна меняется сразу, а тик ждёт до 2 с — перечитываем, как только сменился fullscreen
    Timer { id: geoSoon; interval: 30; onTriggered: clients.running ? geoSoon.restart() : clients.running = true }
    onFullChanged: if (root.auto && root.mode === "smart") geoSoon.restart()
    readonly property bool wide: root.tiles.length === 1
        && (root.normal[root.tiles[0].address] ?? root.geo[root.tiles[0].address] ?? root.tiles[0].lastIpcObject?.size?.[0] ?? 0)
            >= 0.9 * (screen?.width ?? 1920) * (screen?.devicePixelRatio ?? 1)
    readonly property bool floatingWin: root.wins.some(t => t.lastIpcObject?.floating ?? false)
    // одно окно ленты стоит по центру и оставляет поля по бокам; если полоса уже бара, место можно не держать
    readonly property bool sideFree: {
        if (!root.vert) return false;
        if (root.tiles.length === 0) return true;
        if (root.tiles.length !== 1 || !root.screen) return false;
        const w = root.normal[root.tiles[0].address] ?? root.geo[root.tiles[0].address] ?? root.tiles[0].lastIpcObject?.size?.[0] ?? 0;
        if (w <= 0) return false;
        return (root.screen.width - w / (root.screen.devicePixelRatio || 1)) / 2 >= root.width;
    }
    // спец-стол — оверлей над основным: резерв не должен переключаться при его открытии,
    // иначе work area меняется и окно основного стола дёргается
    readonly property bool keepSpace: !root.auto || !root.vert || root.floatingWin || !root.sideFree
    readonly property bool deskWanted: !root.auto || (root.mode === "hidden" || !Sys.smartOK ? root.wins.length === 0
        : !root.full && !root.wide && root.tiles.length <= 1)
    // спец-стол живёт поверх основного: бар решает по его окнам, а не по столу под ним
    readonly property var specialWins: root.isSpecial
        ? Hyprland.toplevels.values.filter(t => t.workspace?.name === "special:" + root.specialWs) : []
    readonly property var specialTiles: root.specialWins.filter(t => !(t.lastIpcObject?.floating ?? false))
    readonly property bool specialWide: root.specialTiles.length === 1
        && (root.normal[root.specialTiles[0].address] ?? root.geo[root.specialTiles[0].address] ?? root.specialTiles[0].lastIpcObject?.size?.[0] ?? 0)
            >= 0.9 * (screen?.width ?? 1920) * (screen?.devicePixelRatio ?? 1)
    readonly property bool specialFull: root.specialWins.some(t => (t.lastIpcObject?.fullscreen ?? 0) > 0)
    readonly property bool specialWanted: !root.auto || (root.mode === "hidden" || !Sys.smartOK
        ? root.specialWins.length === 0
        : root.specialWins.length === 0 || (root.specialWins.length === 1 && root.specialTiles.length === 1 && !root.specialFull && !root.specialWide))
    readonly property bool wanted: root.isSpecial ? root.specialWanted : root.deskWanted
    // work area меняется только от основного стола: открытие/закрытие спец-стола её не трогает
    readonly property bool reserve: root.deskWanted && root.keepSpace
    property bool hovered: false
    property bool peeking: false
    readonly property bool shown: root.wanted || root.peeking || Sys.deckKeyed || Sys.barMenu || root.powOpen
    property real t: root.shown ? 1 : 0
    Behavior on t { NumberAnimation { duration: root.shown ? Theme.t : root.exitMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.glide } }
    // окно живёт всегда — иначе не поймать курсор; скрытым ловит только полоска у края
    readonly property int edge: 4
    readonly property int exitMs: 300 // выход чуть длиннее анимации окна (windowsIn speed 5 ≈ 200 мс)
    // зоны показа: вертикальный бар + scrolling — сверху и снизу, середина остаётся ленте
    readonly property bool zoneHere: root.vert && Sys.scrollLayout && Theme.state.barReveal !== "edge"
    readonly property int zoneTop: Theme.state.barReveal === "default" ? 150 : Theme.state.barZoneTop
    readonly property int zoneBottom: Theme.state.barReveal === "default" ? 150 : Theme.state.barZoneBottom
    readonly property int hitW: root.shown ? root.width : (root.vert ? root.edge : root.width)
    readonly property int hitH1: root.shown ? root.height : (root.zoneHere ? root.zoneTop : (root.vert ? root.height : root.edge))
    readonly property int hitH2: !root.shown && root.zoneHere ? root.zoneBottom : 0
    mask: Region {
        intersection: Intersection.Combine
        Region { x: 0; y: 0; width: root.hitW; height: root.hitH1 }
        Region { x: 0; y: root.height - root.hitH2; width: root.hitW; height: root.hitH2 }
    }
    exclusionMode: root.reserve ? ExclusionMode.Auto : ExclusionMode.Ignore
    // бар занимает место по режиму — OSD встаёт под него; peek/панели сюда не входят
    function syncBarVisible() {
        const m = Object.assign({}, Sys.barVisible);
        if (root.screen?.name) m[root.screen.name] = root.wanted;
        Sys.barVisible = m;
    }
    Component.onCompleted: { syncBarVisible(); syncSpecial(); }
    Component.onDestruction: { const m = Object.assign({}, Sys.barVisible); delete m[root.screen?.name ?? ""]; Sys.barVisible = m; }
    onWantedChanged: {
        root.syncBarVisible();
        if (root.wanted) {
            root.peeking = false;
            holdT.stop();
            hideT.stop();
        } else if (root.hovered) root.peeking = true;
        else if (root.peeking) hideT.restart();
    }
    Timer { id: holdT; interval: Theme.state.barHoldMs; onTriggered: if (root.hovered && !root.wanted) root.peeking = true }
    Timer { id: hideT; interval: 300; onTriggered: root.peeking = false }
    // после выезда hover может потеряться при смене input-региона: держим видимость по позиции курсора
    Process {
        id: cur
        command: ["hyprctl", "cursorpos"]
        stdout: StdioCollector {
            onStreamFinished: {
                const p = text.trim().split(/[, ]+/);
                const x = +p[0], y = +p[1], s = root.screen;
                if (!s || isNaN(x) || isNaN(y)) return;
                const lx = x - s.x, ly = y - s.y;
                const inside = lx >= 0 && ly >= 0
                    && lx <= (root.vert ? root.width + 12 : s.width)
                    && ly <= (root.vert ? s.height : root.height + 12);
                if (inside) hideT.stop();
                else if (!hideT.running) hideT.restart();
            }
        }
    }
    Timer { running: root.peeking && root.shown; interval: 120; repeat: true; triggeredOnStart: true; onTriggered: if (!cur.running) cur.running = true }

    // hyprland 0.56 с lua: dispatch принимает lua-выражение
    // сначала монитор этого бара: иначе стол откроется на том мониторе, где сейчас фокус (главный)
    function go(ws) {
        if (screen?.name) Hyprland.dispatch(`hl.dsp.focus({ monitor = "${screen.name}" })`);
        Hyprland.dispatch(`hl.dsp.focus({ workspace = "${ws}" })`);
    }

    SystemClock { id: clock; precision: SystemClock.Minutes }

    Stage {

        HoverHandler {
            onHoveredChanged: {
                root.hovered = hovered;
                if (hovered) {
                    hideT.stop();
                    if (!root.wanted) {
                        if (root.shown) root.peeking = true;
                        else holdT.restart();
                    }
                } else {
                    holdT.stop();
                }
            }
        }

        Rectangle {
            id: pill
            x: Theme.barGap + (root.vert ? -(1 - root.t) * (pill.width + Theme.barGap) : 0) // сбоку уезжает влево
            y: Theme.barGap + (root.vert ? 0 : -(1 - root.t) * (pill.height + Theme.barGap)) // сверху — вверх
            opacity: root.t
            width: root.vert ? Theme.barThick : parent.width - 2 * Theme.barGap
            height: root.vert ? parent.height - 2 * Theme.barGap : Theme.barThick
            radius: Theme.corner(Theme.barThick / 2)
            color: Theme.s1
            border { width: 1; color: Theme.s2 }

            Notch { onNotch: d => root.go(d > 0 ? "-1" : "+1") }

            // знак: кольцо из точек, центр — красный, пока что-то пишет
            Item {
                id: mark
                x: root.vert ? (parent.width - width) / 2 : 18
                y: root.vert ? 18 : (parent.height - height) / 2
                width: 34
                height: 34
                Ring { anchors.fill: parent; n: 16; dot: 3 }
                Rectangle {
                    anchors.centerIn: parent
                    width: 9
                    height: 9
                    radius: 4.5
                    color: !Sys.live ? Theme.fg : Qt.colorEqual(Theme.accent, Theme.fg) ? Theme.red : Theme.accent // monochrome: акцент = fg
                }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.markClicked() }
            }

            // воркспейсы: текущий вытягивается в белую пилюлю, занятые серые, пустые — линия
            Pile {
                id: ws
                x: root.vert ? (parent.width - width) / 2 : mark.x + mark.width + 24
                y: root.vert ? mark.y + mark.height + 24 : (parent.height - height) / 2
                spacing: 8
                opacity: 1 - 0.8 * root.specLook
                layer.enabled: root.specLook > 0.01
                layer.effect: MultiEffect { blurEnabled: true; blur: root.specLook; blurMax: 24 }

                Repeater {
                    model: root.count

                    Rectangle {
                        required property int index
                        readonly property int n: root.base + index + 1
                        readonly property bool occ: (Hyprland.workspaces.values.find(w => w.id === n)?.toplevels.values.length ?? 0) > 0
                        readonly property bool on: root.active === n
                        property real len: on ? 28 : 8
                        width: root.vert ? 8 : len
                        height: root.vert ? len : 8
                        radius: 4
                        color: on ? Theme.fg : occ ? Theme.grey : Theme.s3
                        Behavior on len { NumberAnimation { duration: Theme.t; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.glide } }
                        Behavior on color { ColorAnimation { duration: Theme.t } }
                        MouseArea { anchors.fill: parent; anchors.margins: -6; onClicked: root.go(parent.n) }
                    }
                }
            }
            Lb {
                visible: root.specLook > 0.01
                opacity: root.specLook
                anchors.centerIn: ws
                text: root.specialText
                px: 11
                color: Theme.fg
                rotation: root.vert ? 90 : 0
            }

            // заголовок окна: от воркспейсов до часов, сбоку — повёрнутый
            Item {
                id: title
                x: root.vert ? (parent.width - width) / 2 : ws.x + ws.width + 24
                y: root.vert ? ws.y + ws.height + 24 : (parent.height - height) / 2
                width: root.vert ? 20 : Math.max(0, clk.x - 24 - x)
                height: root.vert ? Math.max(0, clk.y - 24 - y) : 20
                clip: true
                visible: Theme.state.barTitle
                Lb {
                    x: (parent.width - width) / 2
                    y: (parent.height - height) / 2
                    width: root.vert ? parent.height : parent.width
                    rotation: root.vert ? 90 : 0
                    elide: Text.ElideRight
                    visible: (Hyprland.focusedWorkspace?.toplevels.values.length ?? 0) > 0
                    text: root.top ? `${root.top.appId.split(".").pop()} · ${root.top.title}` : ""
                    px: 11
                }
            }

            // часы: сбоку столбиком 14 над 32 и день, сверху строкой. Клик — календарь и фокус-таймер (cal/Cal)
            Pile {
                id: clk
                anchors.centerIn: parent
                TapHandler { onTapped: root.clockClicked() }
                HoverHandler { cursorShape: Qt.PointingHandCursor }
                Num { text: Theme.hh(clock.date); font.pixelSize: 30 }
                Num { visible: !root.vert; text: ":"; font.pixelSize: 30 }
                Num { text: Qt.formatTime(clock.date, "mm"); font.pixelSize: 30 }
                Lb {
                    topPadding: root.vert ? 8 : 0
                    leftPadding: root.vert ? 0 : 12
                    text: Qt.locale("en_US").toString(clock.date, "ddd d")
                    px: 10
                }
            }

            // трей — Theme.state.bar по порядку (настройки, раздел BAR). Раскладка, сеть, bluetooth, звук (колесо — громкость),
            // mic, уведомления, батарея, бегущий кот: клик открывает быстрые настройки. У mic и звука левый клик — сам тумблер,
            // правый — быстрые настройки. Режим питания и питание — свои клики
            Pile {
                x: root.vert ? (parent.width - width) / 2 : parent.width - width - 22
                y: root.vert ? parent.height - height - 22 : (parent.height - height) / 2
                spacing: 20

                Repeater {
                    model: Theme.state.bar
                    Loader {
                        id: part
                        required property string modelData
                        readonly property bool quick: modelData !== "mode" && modelData !== "power" && modelData !== "vpn"
                        readonly property bool direct: modelData === "mic" || modelData === "sound" // левый клик — тумблер, правый — quick
                        sourceComponent: root.parts[modelData] ?? null
                        visible: !!sourceComponent && (modelData !== "battery" || root.bat.isLaptopBattery)
                        TapHandler { enabled: part.quick && !part.direct; onTapped: root.trayClicked() }
                        TapHandler { acceptedButtons: Qt.RightButton; enabled: part.direct; onTapped: root.trayClicked() }
                        HoverHandler { enabled: part.quick; cursorShape: Qt.PointingHandCursor }
                        TapHandler { enabled: modelData === "vpn"; onTapped: root.vpnClicked() }
                        HoverHandler { enabled: modelData === "vpn"; cursorShape: Qt.PointingHandCursor }
                    }
                }
            }
        }

        Rectangle {
            id: flash
            z: -1
            visible: root.flashOn > 0
            opacity: root.flashOn
            x: root.vert ? (parent.width - width) / 2 : parent.width - width - 36
            y: root.vert ? parent.height - height - 36 : 14
            width: 46
            height: 26
            radius: Theme.corner(13)
            color: Theme.s1
            border { width: 1; color: Theme.s2 }
            transform: Translate {
                x: root.vert ? -(1 - root.flashOn) * 12 : 0
                y: root.vert ? 0 : -(1 - root.flashOn) * 10
            }
            Lb { anchors.centerIn: parent; text: root.flashText; color: Theme.fg; px: 10 }
        }

        Rectangle {
            id: wsFlash
            z: -1
            visible: root.wsChip > 0
            opacity: root.wsChip
            x: root.vert ? (parent.width - width) / 2 : 76
            y: root.vert ? 76 : 14
            width: cluster.implicitWidth + 28
            height: cluster.implicitHeight + 28
            radius: Theme.corner(13)
            color: Theme.s1
            border { width: 1; color: Theme.s2 }
            transform: Translate {
                x: root.vert ? -(1 - root.wsChip) * 12 : 0
                y: root.vert ? 0 : -(1 - root.wsChip) * 10
            }
            // как точки в баре: сверху — строкой, сбоку — столбиком (окно бара сбоку узкое)
            Lb {
                id: chipText
                visible: root.specLook > 0.01
                opacity: root.specLook
                anchors.centerIn: parent
                text: root.specialText
                px: 10
                color: Theme.fg
                rotation: root.vert ? 90 : 0
            }
            Flow {
                id: cluster
                anchors.centerIn: parent
                flow: root.vert ? Flow.TopToBottom : Flow.LeftToRight
                opacity: 1 - 0.8 * root.specLook
                layer.enabled: root.specLook > 0.01
                layer.effect: MultiEffect { blurEnabled: true; blur: root.specLook; blurMax: 24 }
                spacing: 6
                Repeater {
                    model: root.count
                    Rectangle {
                        required property int index
                        readonly property int n: root.base + index + 1
                        readonly property bool occ: (Hyprland.workspaces.values.find(w => w.id === n)?.toplevels.values.length ?? 0) > 0
                        readonly property bool on: root.active === n
                        width: root.vert ? 6 : (on ? 20 : 6)
                        height: root.vert ? (on ? 20 : 6) : 6
                        radius: 3
                        color: on ? Theme.fg : occ ? Theme.grey : Theme.s3
                        Behavior on width { NumberAnimation { duration: Theme.t; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.glide } }
                        Behavior on height { NumberAnimation { duration: Theme.t; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.glide } }
                        Behavior on color { ColorAnimation { duration: Theme.t } }
                    }
                }
            }
        }
    }
    readonly property var parts: ({ layout: layoutC, wifi: wifiC, bluetooth: btC, sound: soundC, mic: micC, notes: notesC, battery: batC, mode: modeC, power: powerC, cat: catC, vpn: vpnC })
    Component { id: layoutC; Lb { text: Sys.layout; px: 10 } }
    // кот RunCat: чем больше cpu, тем быстрее бежит (250 мс на кадр в простое, 50 на полной). cpu опрашивается, пока он в трее;
    // Binding не в делегате — уничтоженный значение не возвращает. Серый как есть, в светлой теме на белом теряется — чёрный, как buds
    Component {
        id: catC
        AnimatedImage {
            width: 44
            height: 26
            source: "runcat.gif"
            mipmap: true
            speed: 1 + 4 * SysStats.cpu
            layer.enabled: Theme.light
            layer.effect: MultiEffect { brightness: -1 }
        }
    }
    Binding { target: SysStats; property: "cat"; value: Theme.state.bar.includes("cat") }
    // сеть: две дуги и точка, концы круглые, как у батареи; выключен — косая черта
    Component {
        id: wifiC
        Shape {
            id: wf
            width: 20
            height: 18
            preferredRendererType: Shape.CurveRenderer
            readonly property color ink: root.wifi?.connected ? Theme.fg : Theme.grey
            ShapePath {
                strokeColor: wf.ink; strokeWidth: 2.2; capStyle: ShapePath.RoundCap; fillColor: "transparent"
                PathAngleArc { centerX: 10; centerY: 15; radiusX: 5.5; radiusY: 5.5; startAngle: 220; sweepAngle: 100 }
                PathAngleArc { centerX: 10; centerY: 15; radiusX: 10.5; radiusY: 10.5; startAngle: 220; sweepAngle: 100 }
            }
            ShapePath {
                strokeColor: Networking.wifiEnabled ? "transparent" : wf.ink; strokeWidth: 2.2; capStyle: ShapePath.RoundCap
                startX: 3; startY: 2
                PathLine { x: 17; y: 17 }
            }
            ShapePath {
                strokeWidth: -1; fillColor: wf.ink
                PathAngleArc { centerX: 10; centerY: 15; radiusX: 1.9; radiusY: 1.9; startAngle: 0; sweepAngle: 360 }
            }
        }
    }
    // vpn (Happ): щит с галочкой и код страны сервера, как заряд у батареи; выключен — пустой серый щит без подписи. Клик — панель (vpn/Happ)
    Component {
        id: vpnC
        Pile {
            spacing: 4
            Icon { text: HappState.live ? "\u{F0565}" : "\u{F0499}"; color: HappState.live ? Theme.fg : Theme.grey }
            Lb { visible: HappState.live; width: full2.implicitWidth; horizontalAlignment: Text.AlignHCenter; text: HappState.cc; px: 10; color: Theme.fg }
            Lb { id: full2; visible: false; text: "MM"; px: 10 }
        }
    }
    Component {
        id: btC
        Icon {
            text: Bluetooth.defaultAdapter?.enabled ? "\u{F00AF}" : "\u{F00B2}"
            color: Bluetooth.devices.values.some(d => d.connected) ? Theme.fg : Theme.grey
        }
    }
    Component {
        id: soundC
        Icon {
            text: Sys.muted ? "\u{F075F}" : "\u{F057E}"
            Notch { onNotch: d => Sys.setVol(Sys.vol + d * 0.05) }
            TapHandler { onTapped: Sys.toggleMute() }
        }
    }
    // mic: глушит дефолтный источник, как плитка в quick; включён — белый, выключен — серый. Правый клик — quick (обработчик в трее)
    Component {
        id: micC
        Icon {
            text: Sys.micOn ? "\u{F036C}" : "\u{F036D}"
            color: Sys.micOn ? Theme.fg : Theme.grey
            TapHandler { onTapped: Sys.toggleMic() }
        }
    }
    Component {
        id: notesC
        Icon {
            text: Theme.state.dnd ? "\u{F009B}" : "\u{F009A}"
            color: Notes.list.length ? Theme.fg : Theme.grey
        }
    }
    // слева батарея стоит, заряд растёт снизу; сверху — лежит, растёт слева. На зарядке — молния первой, заливка дышит, пока заряжается
    Component {
        id: batC
        Pile {
            id: batc
            HoverHandler { onHoveredChanged: { root.batHot = hovered; root.peek(batc); } Component.onDestruction: root.batHot = false }
            spacing: 8
            readonly property bool ac: !UPower.onBattery
            readonly property bool charging: root.bat.state === UPowerDeviceState.Charging
            // дыхание шагом 20 кадров/с, как шар в home/Back: анимация гнала бы бар на каждом vsync (120 Гц) все часы
            // зарядки. Косинус с периодом 2,2 с — те же два InOutSine по 1,1 с
            property real phase: 0
            readonly property real pulse: charging ? 0.675 + 0.325 * Math.cos(phase * Math.PI / 1.1) : 1
            Timer { running: batc.charging; interval: 50; repeat: true; onTriggered: batc.phase = (batc.phase + 0.05) % 2.2; onRunningChanged: batc.phase = 0 }
            Icon { visible: batc.ac; text: "\u{F140B}"; font.pixelSize: 14 }
            Rectangle {
                width: root.vert ? 14 : 26
                height: root.vert ? 26 : 14
                radius: 7
                color: "transparent"
                border { width: 1.5; color: Theme.grey }
                Rectangle {
                    x: 3
                    y: parent.height - 3 - height
                    width: root.vert ? parent.width - 6 : (parent.width - 6) * root.bat.percentage
                    height: root.vert ? (parent.height - 6) * root.bat.percentage : parent.height - 6
                    radius: 4
                    color: root.batLow ? Theme.red : Theme.fg
                    opacity: batc.pulse
                }
            }
            // ширина — под «100»: сверху трей прижат вправо, 99 → 100 сдвигал бы всё левее
            Lb { width: full.implicitWidth; horizontalAlignment: Text.AlignHCenter; text: Math.round(root.bat.percentage * 100); px: 10 }
            Lb { id: full; visible: false; text: "100"; px: 10 }
        }
    }
    // режим питания засечками (Rules.modes): ultra — одна, performance — все; клик — следующий,
    // наведение (и на батарею) — карточка с выбором
    Component {
        id: modeC
        Item {
            id: ticks
            width: 40
            height: 22
            Row {
                anchors.centerIn: parent
                spacing: 2
                Repeater {
                    model: Rules.modeCount
                    Rectangle {
                        required property int index
                        anchors.bottom: parent.bottom
                        width: 3
                        height: 5 + index * 3
                        radius: 1.5
                        color: index <= Rules.mode ? Theme.fg : Theme.s3
                    }
                }
            }
            HoverHandler { cursorShape: Qt.PointingHandCursor; onHoveredChanged: { root.tickHot = hovered; root.peek(ticks); } Component.onDestruction: root.tickHot = false }
            TapHandler { onTapped: Rules.setMode((Rules.mode + 1) % Rules.modeCount) }
        }
    }
    Component {
        id: powerC
        Icon {
            text: "\u{F0425}"
            color: pwr.hovered ? Theme.fg : Theme.grey
            HoverHandler { id: pwr; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: root.powerClicked() }
        }
    }

    // ---- батарея и режим питания: навёл на батарею или засечки — карточка сбоку от бара (со стороны экрана), как поповер caelestia.
    // Заряд Doto, статус, шкала; ниже режимы кругами с засечками — клик выбирает, под курсором — что он делает.
    // Ушёл и с бара, и с карточки — гаснет ----
    property bool batHot: false
    property bool tickHot: false
    readonly property bool powHot: batHot || tickHot || popHov.hovered
    readonly property bool batLow: UPower.onBattery && root.bat.percentage < 0.15
    // карточка встаёт по тому, на что навели (батарея или засечки): сбоку — низом к его низу, сверху — правым краем к его правому;
    // пока видна — не прыгает
    property point popAt
    function peek(it) { if (!pop.visible) popAt = it.mapToItem(pill, it.width, it.height); }
    property bool powOpen: false
    property int powPeek: -1
    onPowHotChanged: powHot ? powOpenT.restart() : powCloseT.restart()
    Timer { id: powOpenT; interval: 180; onTriggered: if (root.powHot) root.powOpen = true }
    Timer { id: powCloseT; interval: 300; onTriggered: if (!root.powHot) root.powOpen = false }
    function hm(sec) { const m = Math.round(sec / 60); return m >= 60 ? `${Math.floor(m / 60)} h ${m % 60} m` : `${m} m`; }
    readonly property string batState: root.bat.state === UPowerDeviceState.Charging
        ? "charging" + (root.bat.timeToFull ? ` · full in ${hm(root.bat.timeToFull)}` : "")
        : !UPower.onBattery ? "on ac · full"
        : "on battery" + (root.bat.timeToEmpty ? ` · ${hm(root.bat.timeToEmpty)} left` : "")

    PopupWindow {
        id: pop
        property real t: root.powOpen ? 1 : 0
        Behavior on t { NumberAnimation { duration: Theme.t; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.glide } }
        visible: t > 0
        // от внутреннего края пилюли бара с тем же зазором; сбоку растёт вверх от popAt, сверху — вниз и влево
        anchor.item: pill
        anchor.rect: root.vert ? Qt.rect(pill.width + Theme.barGap, root.popAt.y, 1, 1) : Qt.rect(root.popAt.x, pill.height + Theme.barGap, 1, 1)
        anchor.edges: Edges.Top | Edges.Left
        anchor.gravity: root.vert ? Edges.Top | Edges.Right : Edges.Bottom | Edges.Left
        implicitWidth: Math.ceil(440 * Theme.s)
        implicitHeight: Math.ceil(card.height * Theme.s)
        color: "transparent"

        Stage {
            Rectangle {
                id: card
                width: 440
                height: body.height + 52
                radius: Theme.corner(36)
                color: Theme.s1
                border { width: 1; color: Theme.s2 }
                opacity: pop.t
                transform: Translate { x: root.vert ? -16 * (1 - pop.t) : 0; y: root.vert ? 0 : -16 * (1 - pop.t) }
                HoverHandler { id: popHov }

                Column {
                    id: body
                    x: 26
                    y: 26
                    width: parent.width - 52
                    spacing: 18

                    Row {
                        spacing: 14
                        Num { text: Math.round(root.bat.percentage * 100); font.pixelSize: 72 }
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 6
                            Lb { text: "% battery"; color: Theme.fg }
                            Lb { text: root.batState }
                        }
                    }
                    Seg { width: parent.width; height: 6; n: 24; f: root.bat.percentage; on: root.batLow ? Theme.red : Theme.fg }

                    Lb { topPadding: 6; text: "power mode" }
                    Row {
                        spacing: (body.width - Rules.modeCount * 80) / Math.max(1, Rules.modeCount - 1)
                        Repeater {
                            model: Rules.modeCount
                            Column {
                                id: mo
                                required property int index
                                readonly property bool on: Rules.mode === index
                                spacing: 10
                                Rectangle {
                                    width: 80
                                    height: 80
                                    radius: 40
                                    color: mo.on ? Theme.fg : moHov.hovered ? Theme.s3 : Theme.s2
                                    Behavior on color { ColorAnimation { duration: Theme.t } }
                                    // засечки: сколько горит — такая сила
                                    Row {
                                        anchors.centerIn: parent
                                        spacing: 4
                                        Repeater {
                                            model: 4
                                            Rectangle {
                                                required property int index
                                                anchors.bottom: parent.bottom
                                                width: 5
                                                height: 8 + index * 6
                                                radius: 2.5
                                                color: index <= mo.index ? (mo.on ? Theme.ink : Theme.fg) : (mo.on ? Theme.mute : Theme.s3)
                                            }
                                        }
                                    }
                                    HoverHandler {
                                        id: moHov
                                        cursorShape: Qt.PointingHandCursor
                                        onHoveredChanged: if (hovered) root.powPeek = mo.index; else if (root.powPeek === mo.index) root.powPeek = -1
                                    }
                                    TapHandler { onTapped: Rules.setMode(mo.index) }
                                }
                                Lb { anchors.horizontalCenter: parent.horizontalCenter; text: mo.index === 3 ? "max" : Rules.modes[mo.index].name; color: mo.on ? Theme.fg : Theme.grey }
                            }
                        }
                    }
                    Lb {
                        readonly property int i: root.powPeek >= 0 ? root.powPeek : Rules.mode
                        width: parent.width
                        elide: Text.ElideRight
                        text: `${Rules.modes[i].what} · ${Rules.refreshHz} hz`
                    }
                }
            }
        }
    }
}
