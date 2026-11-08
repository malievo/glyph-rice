import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.SystemTray
import Quickshell.Wayland
import qs
import qs.components

// happ: отдельная панель для Happ (Super+Alt+P). Та же вёрстка, что у vpn, но источник — Happ:
// серверы, статус и режим — пункты его трея (dbusmenu), скорость — счётчики его tun-интерфейса happ*, адрес сервера — Happ.conf.
// Выбор сервера и вкл/выкл — нажатием пунктов трея; если пункта нет — happ://connect|disconnect.
// ponytail: пункты ищем по русским подписям трея Happ; другой язык — поменять регэкспы ниже
PanelWindow {
    id: root

    // ---- happ: трей ----
    readonly property var happ: SystemTray.items.values.find(i => i.id === "Happ" || i.title === "Happ") ?? null
    function child(op, re) { return op.children.values.find(e => !e.isSeparator && re.test(e.text)) ?? null; }
    QsMenuOpener { id: tray; menu: root.happ?.menu ?? null }
    QsMenuOpener { id: srv; menu: root.child(tray, /сервер|server/i) }
    QsMenuOpener { id: trm; menu: root.child(tray, /транспорт|transport/i) }
    QsMenuOpener { id: tunm; menu: root.child(trm, /tun/i) }

    readonly property string status: tray.children.values.find(e => !e.isSeparator)?.text ?? ""
    readonly property bool live: /^(подключено|connected)/i.test(status)
    readonly property bool tun: tunIf !== ""
    readonly property bool proxy: live && !tun

    // сервер из пункта «Стокгольм | hysteria2»: город, протокол, код страны
    readonly property var cities: ({ "Амстердам": "NL", "Стокгольм": "SE", "Хельсинки": "FI", "Париж": "FR", "Варшава": "PL", "Рим": "IT", "Франкфурт": "DE", "Берлин": "DE", "Лондон": "GB", "Вена": "AT", "Мадрид": "ES", "Цюрих": "CH", "Прага": "CZ", "Москва": "RU", "Токио": "JP", "Стамбул": "TR", "Дубай": "AE" })
    function way(e) {
        const [name, ...rest] = e.text.split(/\s*\|\s*/), city = name.replace(/\s*#\d+$/, "").trim();
        return { entry: e, cc: cities[city] ?? "··", name: name.trim(), sub: rest.join(" · "), on: e.checkState === Qt.Checked };
    }
    readonly property var ways: srv.children.values.filter(e => !e.isSeparator).map(e => way(e))
    readonly property var now: ways.find(w => w.on) ?? null

    function go(i) { const w = ways[i]; if (w && !w.on) w.entry.triggered(); }
    property int want: -1 // 1 — включаем, 0 — выключаем, пока Happ не догнал
    readonly property bool connected: want >= 0 ? want === 1 : live
    onLiveChanged: want = -1
    // только пункты трея: второй запуск Happ поднимает его окно. Нет значка — свёрнутый старт, если не запущен
    function flip() {
        if (!happ) return Quickshell.execDetached(["sh", "-c", "pgrep -x Happ >/dev/null || exec /opt/happ/bin/Happ --autostart"]);
        const e = child(tray, connected ? /^отключ|^disconnect/i : /^подключ|^connect/i);
        if (!e) return;
        e.triggered();
        want = connected ? 0 : 1;
        wantT.restart();
    }
    Timer { id: wantT; interval: 8000; onTriggered: root.want = -1 }
    function setProxy() { child(trm, /прокси|proxy/i)?.triggered(); }
    function setTun() { (child(tunm, /sing/i) ?? child(tunm, /./))?.triggered(); }

    property date since: new Date()
    onConnectedChanged: if (connected) since = new Date()

    // ---- Happ.conf: последний сервер (адрес и порт открытым текстом) ----
    property string host: ""
    property string port: ""
    FileView {
        path: Quickshell.env("HOME") + "/.config/Happ.conf"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            const t = text(), f = k => new RegExp(`^${k}=(.*)$`, "m").exec(t)?.[1]?.trim() ?? "";
            root.host = f("lastServerHost");
            root.port = f("lastServerPort");
        }
    }

    // ---- скорость: счётчики tun-интерфейса happ* раз в секунду (в режиме прокси интерфейса нет — скорости нет) ----
    property string tunIf: ""
    property var toll: []
    property real up: 0
    property real down: 0
    property real prevRx: -1
    property real prevTx: -1
    Process {
        running: true
        command: ["sh", "-c", `while :; do i=; for d in /sys/class/net/happ*; do [ -d "$d" ] && i=\${d##*/}; done; if [ -n "$i" ]; then set -- $(cat /sys/class/net/$i/statistics/rx_bytes /sys/class/net/$i/statistics/tx_bytes 2>/dev/null); echo "$i $1 $2"; else echo none; fi; sleep 1; done`]
        stdout: SplitParser {
            onRead: l => {
                const p = l.trim().split(" ");
                if (p[0] === "none" || p.length < 3) {
                    root.tunIf = "";
                    root.prevRx = root.prevTx = -1;
                    root.up = root.down = 0;
                } else {
                    root.tunIf = p[0];
                    const rx = +p[1], tx = +p[2];
                    root.down = root.prevRx >= 0 ? Math.max(0, rx - root.prevRx) : 0;
                    root.up = root.prevTx >= 0 ? Math.max(0, tx - root.prevTx) : 0;
                    root.prevRx = rx;
                    root.prevTx = tx;
                }
                root.toll = root.toll.slice(-599).concat([[root.up, root.down]]);
            }
        }
    }

    // матрица трафика: 50 столбцов по 12 с, точек от оси: [вход вверх, выход вниз], 0…5 по общему максимуму.
    // Панель закрыта — не считаем
    readonly property var cols: {
        if (!root.visible) return [];
        const s = Array(Math.max(0, 600 - toll.length)).fill([0, 0]).concat(toll), c = [];
        let max = 1;
        for (let i = 0; i < 50; i++) {
            let a = 0, b = 0;
            for (let j = i * 12; j < i * 12 + 12; j++) { a += s[j][0]; b += s[j][1]; }
            c.push([b / 12, a / 12]);
            max = Math.max(max, a / 12, b / 12);
        }
        const lv = v => v > 0 ? Math.max(1, Math.round(5 * v / max)) : 0;
        return c.map(([i, o]) => [lv(i), lv(o)]);
    }
    function speed(b) { const k = b / 1024; return k >= 1000 ? [(k / 1024).toFixed(1), "mb/s"] : [k.toFixed(1), "kb/s"]; }

    // ---- открытие / закрытие: сам себе анимация (у слоёв glyph в hypr no_anim) ----
    property int cur: 0 // курсор клавиатуры по узлам
    property bool shown: false
    property real t: shown ? 1 : 0
    Behavior on t { NumberAnimation { duration: Theme.t; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.glide } }

    function open() {
        cur = Math.max(0, ways.findIndex(w => w.on));
        shown = true;
        panel.forceActiveFocus();
    }
    function close() { shown = false; }
    function toggle() { shown ? close() : open(); }
    onVisibleChanged: if (visible) list.positionViewAtIndex(cur, ListView.Contain)

    visible: t > 0
    anchors { left: true; right: true; top: true; bottom: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    WlrLayershell.namespace: "glyph-vpn"

    Rectangle {
        anchors.fill: parent
        color: Theme.scrim
        opacity: root.t
        MouseArea { anchors.fill: parent; onClicked: root.close() }
    }

    Stage {
        id: stage

        Rectangle {
            id: panel
            x: (stage.width - width) / 2
            y: (stage.height - height) / 2 - 20 + 24 * (1 - root.t)
            width: 1040
            height: 760
            opacity: root.t
            radius: Theme.corner(44)
            color: Theme.s1
            border { width: 1; color: Theme.s2 }
            focus: true
            MouseArea { anchors.fill: parent } // клик по панели не закрывает

            // буквы — по физической клавише (Scan): в русской раскладке e.key приходит кириллицей («ы» вместо S)
            Keys.onPressed: e => {
                const n = root.ways.length;
                if ((e.key === Qt.Key_Up || Scan.hit(e, "k")) && n) root.cur = (root.cur + n - 1) % n;
                else if ((e.key === Qt.Key_Down || Scan.hit(e, "j")) && n) root.cur = (root.cur + 1) % n;
                else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) root.go(root.cur);
                else if (Scan.hit(e, "s")) root.flip();
                else if (e.key === Qt.Key_Escape) root.close();
                else return;
                list.positionViewAtIndex(root.cur, ListView.Contain);
                e.accepted = true;
            }

            // ---- слева: кольцо, пилюли, режим, профиль ----
            Column {
                x: 36
                y: 36
                width: 340
                spacing: 16

                // кольцо: загорается волной на открытии и при включении; клик — вкл/выкл
                Item {
                    width: 340
                    height: 340
                    Ring { anchors.fill: parent; n: 60; dot: 10; f: root.shown && root.connected ? 1 : 0 }
                    Column {
                        anchors.centerIn: parent
                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: 18
                            height: 18
                            radius: 9
                            color: root.connected ? Theme.accent : Theme.s3
                            Behavior on color { ColorAnimation { duration: Theme.t } }
                        }
                        Num {
                            anchors.horizontalCenter: parent.horizontalCenter
                            topPadding: lead + 22
                            bottomPadding: lead + 16
                            text: root.connected ? "ON" : "OFF"
                            font.pixelSize: 120
                            color: root.connected ? Theme.fg : Theme.mute
                            Behavior on color { ColorAnimation { duration: Theme.t } }
                        }
                        Lb {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: !root.happ ? "happ sleeps · tap" : root.connected ? `since ${Qt.formatTime(root.since, "hh:mm")}` : "tap to connect"
                        }
                    }
                    TapHandler { onTapped: root.flip() }
                }
                Item { width: 1; height: 12 }

                Row {
                    spacing: 12
                    Pill { on: root.proxy; icon: "\u{F059F}"; name: "Proxy"; sub: "transport" }
                    Pill { on: root.tun; icon: "\u{F0A60}"; name: "TUN"; sub: "tunnel" }
                }
            }

            Column {
                x: 36
                anchors { bottom: parent.bottom; bottomMargin: 36 }
                width: 340
                spacing: 6
                Lb { text: "server"; px: 11 }
                Lb { width: parent.width; elide: Text.ElideRight; text: root.now?.name ?? "none"; px: 14; color: Theme.fg }
                Lb { text: root.now?.sub ?? "—"; px: 11 }
                Item { width: 1; height: 6 }
                Lb { text: root.host ? `${root.host}${root.port ? ":" + root.port : ""}` : "—"; px: 11 }
            }

            // ---- справа: скорость, трафик, узлы ----
            Item {
                x: 420
                y: 36
                width: parent.width - x - 36
                height: parent.height - 72

                Column {
                    id: rcol
                    width: parent.width
                    spacing: 12

                    Row {
                        spacing: 56
                        Stat { k: `↓ in · ${root.speed(root.down)[1]}`; v: root.speed(root.down)[0] }
                        Stat { k: `↑ out · ${root.speed(root.up)[1]}`; v: root.speed(root.up)[0] }
                    }
                    Item { width: 1; height: 14 }

                    Item {
                        width: parent.width
                        height: tl.height
                        Lb { id: tl; text: "traffic · in / out · 10 min" }
                        Lb { anchors.right: parent.right; text: root.tun ? `tun · ${root.tunIf}` : root.connected ? "proxy" : "off"; color: Theme.fg }
                    }
                    // матрица: вход растёт от середины вверх, выход — вниз; верхушка белая, под ней серые
                    Grid {
                        id: mx
                        width: parent.width
                        columns: 50
                        spacing: 4
                        readonly property real d: (width - 49 * spacing) / 50
                        Repeater {
                            model: 50 * 10
                            Rectangle {
                                required property int index
                                readonly property int r: Math.floor(index / 50)
                                readonly property int lv: r < 5 ? 5 - r : r - 4 // от оси: 1 … 5
                                readonly property int h: root.cols[index % 50]?.[r < 5 ? 0 : 1] ?? 0
                                width: mx.d
                                height: mx.d
                                radius: mx.d / 2
                                color: lv === h ? Theme.fg : lv < h ? Theme.grey : Theme.s2
                            }
                        }
                    }
                    Item { width: 1; height: 14 }

                    Item {
                        width: parent.width
                        height: nl.height
                        Lb { id: nl; text: "servers" }
                        Lb { anchors.right: parent.right; text: `${root.ways.length} total`; color: Theme.fg }
                    }
                }

                // ponytail: не влезли — листаются, панель не растёт
                ListView {
                    id: list
                    anchors { top: rcol.bottom; topMargin: 4; bottom: parent.bottom; left: parent.left; right: parent.right }
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    model: root.ways.length // по числу: делегаты живут, заливка успевает перетечь
                    delegate: Rectangle {
                        id: row
                        required property int index
                        readonly property var w: root.ways[index] ?? {}
                        readonly property bool on: !!w.on
                        width: list.width
                        height: 52
                        radius: Theme.corner(26)
                        color: on ? Theme.fg : index === root.cur ? Theme.s2 : Theme.fade(Theme.s2, 0)
                        Behavior on color { ColorAnimation { duration: Theme.t } }

                        Num {
                            id: cc
                            x: 20
                            anchors.verticalCenter: parent.verticalCenter
                            width: 50
                            text: row.w.cc ?? ""
                            font.pixelSize: 26
                            color: row.on ? Theme.ink : Theme.fg
                        }
                        Column {
                            anchors { left: cc.right; leftMargin: 10; right: ping.left; rightMargin: 16; verticalCenter: parent.verticalCenter }
                            Text {
                                width: parent.width
                                elide: Text.ElideRight
                                text: row.w.name ?? ""
                                font { family: Theme.ui; pixelSize: 16; weight: Font.DemiBold }
                                color: row.on ? Theme.ink : Theme.fg
                            }
                            Lb {
                                width: parent.width
                                visible: !!row.w.sub
                                elide: Text.ElideRight
                                text: row.w.sub ?? ""
                                px: 10
                                color: row.on ? Theme.ink : Theme.grey
                                opacity: row.on ? 0.6 : 1
                            }
                        }
                        Lb {
                            id: ping
                            anchors { right: parent.right; rightMargin: 20; verticalCenter: parent.verticalCenter }
                            text: row.on ? "active" : ""
                            px: 11
                            color: row.on ? Theme.ink : Theme.grey
                        }
                        TapHandler { onTapped: { root.cur = row.index; root.go(row.index); } }
                    }
                }
                Lb { visible: !root.ways.length; anchors.centerIn: list; text: root.happ ? "no servers" : "happ sleeps" }
            }
        }

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            y: panel.y + panel.height + 30
            opacity: root.t
            spacing: 34
            Repeater {
                model: ["↑↓ server", "↵ connect", "s on / off", "esc close"]
                Lb { required property string modelData; text: modelData }
            }
        }
    }

    // пилюля: вкл — белая, текст чёрный (как в быстрых настройках)
    component Pill: Rectangle {
        id: pill
        property bool on
        property string icon
        property string name
        property string sub
        signal clicked
        width: 164
        height: 76
        radius: Theme.corner(38)
        color: on ? Theme.fg : Theme.s2
        Behavior on color { ColorAnimation { duration: Theme.t } }
        Rectangle {
            id: pi
            x: 12
            anchors.verticalCenter: parent.verticalCenter
            width: 52
            height: 52
            radius: 26
            color: pill.on ? Theme.ink : Theme.s3
            Icon { anchors.centerIn: parent; text: pill.icon; font.pixelSize: 22 }
        }
        Column {
            anchors { left: pi.right; leftMargin: 12; right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
            Text { text: pill.name; font { family: Theme.ui; pixelSize: 16; weight: Font.DemiBold } color: pill.on ? Theme.ink : Theme.fg }
            Text {
                width: parent.width
                elide: Text.ElideRight
                text: pill.sub
                font { family: Theme.mono; pixelSize: 11; letterSpacing: 0.9; capitalization: Font.AllUppercase }
                color: pill.on ? Theme.ink : Theme.fg
                opacity: 0.6
            }
        }
        TapHandler { onTapped: pill.clicked() }
    }
    // скорость: метка и число Doto
    component Stat: Column {
        property string k
        property string v
        width: 264
        Lb { text: parent.k }
        Num { topPadding: lead + 10; text: parent.v; font.pixelSize: 80 }
    }
}
