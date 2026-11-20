import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs
import qs.components

// быстрый блокнот: панель Win+T в семье Win+V, но без тулбара — редактор на всю карточку.
// Справа сверху пилюли «+ new» и «notes»; notes плавно выкатывает историю из-под правого края.
// Заметки — файлы *.md в ~/Документы/Заметки (имя — дата). Текст пишется сам через 0.6 с паузы,
// открытие показывает последнюю заметку по mtime, Ctrl+Space — новая.
PanelWindow {
    id: root

    readonly property string dir: (Quickshell.env("HOME") || "") + "/Документы/Заметки"
    property var notes: []      // [{ mtime, name, title }], новые сверху
    property string cur: ""     // файл открытой заметки; пусто — новая, ещё не сохранённая
    property bool loader: false // текст выставлен программно (загрузка) — автосейв молчит
    property bool booted: false
    property real flash: 0      // вспышка «saved»

    property bool shown: false
    property bool drawer: false
    property real t: shown ? 1 : 0
    Behavior on t { NumberAnimation { duration: Theme.t; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.glide } }
    property real dt: drawer ? 1 : 0
    Behavior on dt { NumberAnimation { duration: Theme.t; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.glide } }
    Behavior on flash { NumberAnimation { duration: 400 } }

    function open() { shown = true; refresh(); }
    function close() { saveNow(); shown = false; drawer = false; }
    function toggle() { shown ? close() : open(); }
    function refresh() { lister.running = true; }

    // атомарно, текст — в stdin: ни argv, ни кавычек; новое имя — дата
    function saveNow() {
        if (loader || !booted) return;
        if (cur === "") {
            if (ed.text.length === 0) return;
            cur = dir + "/" + Qt.formatDateTime(new Date(), "yyyy-MM-dd_HH-mm-ss") + ".md";
        }
        if (save.running) { save.again = true; return; }
        save.payload = ed.text;
        save.stdinEnabled = true;
        save.running = true;
    }

    function load(name) {
        saveNow();
        cur = dir + "/" + name;
        loader = true;
        read.command = ["cat", "--", cur];
        read.running = true;
        drawer = false;
    }

    function fresh() {
        saveNow();
        cur = "";
        loader = true;
        ed.text = "";
        loader = false;
        drawer = false;
        ed.forceActiveFocus();
    }

    function burn(name) {
        if (dir + "/" + name === cur) {
            cur = "";
            loader = true;
            ed.text = "";
            loader = false;
        }
        rm.command = ["rm", "-f", "--", dir + "/" + name];
        rm.running = true;
    }

    function blink() { flash = 1; flashTimer.restart(); }

    function when(ts) {
        const d = new Date(ts * 1000), now = new Date();
        return d.toDateString() === now.toDateString()
            ? Qt.formatDateTime(d, "HH:mm") : Qt.formatDateTime(d, "dd.MM HH:mm");
    }

    // история: mtime, имя файла, первая строка — одной строкой, новые сверху
    Process {
        id: lister
        command: ["sh", "-c",
            'd="$1"; mkdir -p -- "$d" || exit 0; cd "$d" || exit 0; ' +
            'find . -maxdepth 1 -type f -name "*.md" -printf "%T@\\t%P\\n" 2>/dev/null | sort -rn | ' +
            'while IFS=$(printf "\\t") read -r ts f; do [ -n "$f" ] || continue; ' +
            't=$(head -n 1 -- "$f" 2>/dev/null | tr "\\t\\n" "  " | cut -c 1-90); ' +
            'printf "%s\\t%s\\t%s\\n" "$ts" "$f" "$t"; done',
            "sh", root.dir]
        stdout: StdioCollector {
            onStreamFinished: {
                root.notes = text.split("\n").filter(l => l.includes("\t")).map(l => {
                    const p = l.split("\t");
                    return { mtime: Number(p[0]), name: p[1], title: p[2] || "" };
                });
                if (!root.booted) {
                    root.booted = true;
                    // не затираем то, что успели напечатать, пока читался список (после старта шелла)
                    if (root.notes.length && ed.text.length === 0) root.load(root.notes[0].name);
                    else ed.forceActiveFocus();
                }
            }
        }
    }

    Process {
        id: read
        stdout: StdioCollector {
            onStreamFinished: {
                ed.text = text;
                root.loader = false;
                ed.cursorPosition = ed.text.length;
                ed.forceActiveFocus();
            }
        }
    }

    Process {
        id: save
        stdinEnabled: true
        property string payload: ""
        property bool again: false
        command: ["sh", "-c", 'd=$(dirname -- "$1"); mkdir -p -- "$d" && cat > "$1.tmp.$$" && mv -f -- "$1.tmp.$$" "$1"', "sh", root.cur]
        onStarted: { write(payload); stdinEnabled = false; }
        onExited: code => {
            if (code === 0 && root.cur !== "") { root.blink(); root.refresh(); }
            if (again) { again = false; root.saveNow(); }
        }
    }

    Process { id: rm; onExited: root.refresh() }

    Timer { id: autosave; interval: 600; onTriggered: root.saveNow() }
    Timer { id: flashTimer; interval: 1400; onTriggered: root.flash = 0 }

    visible: t > 0
    anchors { left: true; right: true; top: true; bottom: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    WlrLayershell.namespace: "glyph-note"

    onShownChanged: if (shown) ed.forceActiveFocus()
    Component.onCompleted: refresh()

    Rectangle {
        anchors.fill: parent
        color: Theme.scrim
        opacity: root.t
        MouseArea { anchors.fill: parent; onClicked: root.close() }
    }

    Stage {
        id: stage

        Rectangle {
            id: card
            x: (stage.width - width) / 2
            y: 140 + 24 * (1 - root.t)
            width: 1120
            height: Math.min(stage.height - 280, 760)
            opacity: root.t
            radius: Theme.corner(44)
            color: Theme.s1
            border { width: 1; color: Theme.s2 }
            clip: true

            MouseArea { anchors.fill: parent }

            TextEdit {
                id: ed
                anchors { fill: parent; leftMargin: 46; rightMargin: 46; topMargin: 92; bottomMargin: 44 }
                focus: true
                textFormat: TextEdit.PlainText
                wrapMode: TextEdit.WrapAtWordBoundaryOrAnywhere
                selectByMouse: true
                persistentSelection: true
                color: Theme.fg
                selectionColor: Theme.s3
                selectedTextColor: Theme.fg
                font { family: Theme.ui; pixelSize: 23 }
                cursorDelegate: Rectangle {
                    width: 2
                    color: Theme.accent
                    Timer { running: ed.activeFocus; interval: 520; repeat: true; onTriggered: parent.opacity = 1 - parent.opacity }
                }
                Keys.onPressed: e => {
                    const ctrl = (e.modifiers & Qt.ControlModifier) !== 0;
                    if (e.key === Qt.Key_Escape) {
                        if (root.drawer) root.drawer = false;
                        else root.close();
                    } else if (ctrl && e.key === Qt.Key_Space) {
                        root.fresh();
                    } else if (ctrl && e.key === Qt.Key_S) {
                        root.saveNow();
                    } else if (e.key === Qt.Key_Tab) {
                        ed.insert(ed.cursorPosition, "    ");
                    } else return;
                    e.accepted = true;
                }
                onTextChanged: if (!root.loader) autosave.restart()
            }

            Text {
                x: 48
                y: 96
                visible: ed.text.length === 0
                text: "start typing…"
                textFormat: Text.PlainText
                font: ed.font
                color: Theme.mute
            }

            // пилюли: новая заметка, история
            Row {
                id: chips
                anchors { top: parent.top; right: parent.right; margins: 20 }
                spacing: 8
                z: 4
                component Chip: Rectangle {
                    id: c
                    property string label
                    signal tapped
                    width: lab.implicitWidth + 36
                    height: 38
                    radius: 19
                    color: hov.hovered ? Theme.fg : Theme.s2
                    Behavior on color { ColorAnimation { duration: 150 } }
                    Lb { id: lab; anchors.centerIn: parent; text: c.label; px: 10; color: hov.hovered ? Theme.ink : Theme.grey }
                    TapHandler { onTapped: c.tapped() }
                    HoverHandler { id: hov; cursorShape: Qt.PointingHandCursor }
                }
                Chip { label: "+ new"; onTapped: root.fresh() }
                Chip { label: "notes"; onTapped: root.drawer = !root.drawer }
            }

            // история: выкатывается из-под правого края, карточка её подрезает
            Rectangle {
                id: sheet
                width: 380
                y: 76
                height: parent.height - 76 - 18
                x: parent.width - 18 - width + (width + 30) * (1 - root.dt)
                radius: Theme.corner(40)
                color: Theme.s2
                z: 3

                Lb { id: hlab; x: 28; y: 26; text: "notes" }
                Num { anchors.baseline: hlab.baseline; x: hlab.implicitWidth + 42; text: root.notes.length; font.pixelSize: 26; color: Theme.grey }

                ListView {
                    id: rows
                    anchors { left: parent.left; right: parent.right; top: hlab.bottom; bottom: parent.bottom; margins: 18 }
                    clip: true
                    spacing: 4
                    model: root.notes
                    boundsBehavior: Flickable.StopAtBounds
                    delegate: Note {}
                }

                Lb {
                    visible: root.notes.length === 0
                    anchors.centerIn: parent
                    text: "no notes yet"
                }
            }

            // строка истории: заголовок (первая строка файла) и время; текущая — белая пилюля
            component Note: Rectangle {
                id: row
                required property var modelData
                required property int index
                readonly property bool on: root.dir + "/" + modelData.name === root.cur
                width: rows.width
                height: 72
                radius: 20
                color: row.on ? Theme.fg : hov.hovered ? Theme.s3 : "transparent"
                Behavior on color { ColorAnimation { duration: 120 } }

                Column {
                    anchors { left: parent.left; leftMargin: 20; right: tail.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
                    spacing: 4
                    Text {
                        width: parent.width
                        elide: Text.ElideRight
                        textFormat: Text.PlainText
                        text: row.modelData.title || "empty note"
                        font { family: Theme.ui; pixelSize: 16; weight: Font.Medium }
                        color: row.on ? Theme.ink : row.modelData.title ? Theme.fg : Theme.mute
                    }
                    Lb { text: root.when(row.modelData.mtime); px: 10; color: row.on ? Theme.ink : Theme.grey; opacity: row.on ? 0.6 : 1 }
                }

                Row {
                    id: tail
                    anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
                    Rectangle {
                        width: 30
                        height: 30
                        radius: 15
                        visible: hov.hovered
                        color: del.hovered ? Theme.fg : row.on ? "transparent" : Theme.s1
                        Text {
                            anchors.centerIn: parent
                            text: "×"
                            font { family: Theme.ui; pixelSize: 20; weight: Font.Medium }
                            color: del.hovered ? Theme.ink : row.on ? Theme.ink : Theme.grey
                        }
                        TapHandler { id: del; onTapped: root.burn(row.modelData.name) }
                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                    }
                }

                TapHandler { onTapped: root.load(row.modelData.name) }
                HoverHandler { id: hov; cursorShape: Qt.PointingHandCursor }
            }

            // хинты под карточкой — как у Win+V
            Row {
                anchors { horizontalCenter: parent.horizontalCenter; top: parent.bottom; topMargin: 26 }
                spacing: 34
                Lb { text: "ctrl+space new" }
                Lb { text: "ctrl+s save" }
                Lb { text: "esc close" }
                Lb { text: "saved"; color: Theme.fg; opacity: root.flash }
            }
        }
    }
}
