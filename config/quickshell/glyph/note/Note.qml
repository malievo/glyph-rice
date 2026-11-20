import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs
import qs.components

// быстрый блокнот: панель Win+T в семье Win+V. Сверху пилюля поиска с пилюлями «+ new» и «notes»,
// под ней редактор почти на всю карточку; notes плавно выкатывает историю из-под правого края.
// Поиск фильтрует заметки по заголовку и содержимому (grep), набор текста сам открывает историю.
// История листается с клавиатуры (Ctrl+H — открыть, ↑↓, ↵, Del, Tab — поиск), в строке при наведении —
// копировать и удалить, между заметками — тихие подписи дат (today, yesterday…).
// Заметки — файлы *.md в ~/Документы/Заметки (имя — дата). Текст пишется сам через 0.6 с паузы,
// открытие показывает последнюю заметку по mtime, Ctrl+Space — новая.
PanelWindow {
    id: root

    readonly property string dir: (Quickshell.env("HOME") || "") + "/Документы/Заметки"
    property var notes: []      // [{ mtime, name, title }], новые сверху
    property var hits: []       // имена файлов, где поиск нашёл текст (grep)
    property string query: ""
    property int sel: 0         // выбранная строка истории (клавиатура и подсветка)
    property string cur: ""     // файл открытой заметки; пусто — новая, ещё не сохранённая
    property bool loader: false // текст выставлен программно (загрузка) — автосейв молчит
    property bool booted: false
    property real flash: 0      // вспышка «saved» / «copied»
    property string flashText: "saved"

    readonly property var view: (query === "" ? notes : notes.filter(n =>
        n.title.toLowerCase().includes(query.toLowerCase()) || hits.includes(n.name)))
        .map(n => ({ mtime: n.mtime, name: n.name, title: n.title, bucket: bucket(n.mtime) }))
    readonly property int words: ed.text.trim() ? ed.text.trim().split(/\s+/).length : 0

    property bool shown: false
    property bool drawer: false
    property real t: shown ? 1 : 0
    Behavior on t { NumberAnimation { duration: Theme.t; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.glide } }
    property real dt: drawer ? 1 : 0
    Behavior on dt { NumberAnimation { duration: Theme.t; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.glide } }
    Behavior on flash { NumberAnimation { duration: 400 } }

    function open() { shown = true; refresh(); }
    function close() { saveNow(); shown = false; drawer = false; input.text = ""; }
    function toggle() { shown ? close() : open(); }
    function refresh() {
        lister.running = true;
        if (query !== "") searchTimer.restart();
    }

    // история: открыть с поиском (Ctrl+H / пилюля notes), повторно — закрыть в редактор
    function history() {
        if (drawer) { drawer = false; ed.forceActiveFocus(); }
        else { drawer = true; input.forceActiveFocus(); }
    }

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
        input.text = "";
    }

    function fresh() {
        saveNow();
        cur = "";
        loader = true;
        ed.text = "";
        loader = false;
        drawer = false;
        input.text = "";
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

    // из строки истории, не открывая: текущая — из буфера редактора (там может быть ещё не сохранённое)
    function copyNote(name) {
        flashText = "copied";
        if (dir + "/" + name === cur) {
            copyText.payload = ed.text;
            copyText.stdinEnabled = true;
            copyText.running = true;
        } else {
            copyFile.command = ["sh", "-c", 'cat -- "$1" | wl-copy', "sh", dir + "/" + name];
            copyFile.running = true;
        }
    }

    function blink() { flash = 1; flashTimer.restart(); }

    function when(ts) {
        const d = new Date(ts * 1000), now = new Date();
        return d.toDateString() === now.toDateString()
            ? Qt.formatDateTime(d, "HH:mm") : Qt.formatDateTime(d, "dd.MM HH:mm");
    }

    // тихие группы по датам: заметки отсортированы по mtime, группы идут подряд
    function bucket(ts) {
        const d = new Date(ts * 1000), now = new Date();
        const day = 86400000;
        const start = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime();
        if (d.getTime() >= start) return "today";
        if (d.getTime() >= start - day) return "yesterday";
        if (d.getTime() >= start - 7 * day) return "last week";
        if (d.getTime() >= start - 30 * day) return "last month";
        return ">30 days";
    }

    onDrawerChanged: {
        if (!drawer) return;
        if (query === "") sel = Math.max(0, view.findIndex(n => dir + "/" + n.name === cur));
        rows.positionViewAtIndex(sel, ListView.Contain);
    }
    onViewChanged: {
        sel = Math.max(0, Math.min(sel, view.length - 1));
        rows.positionViewAtIndex(sel, ListView.Contain);
    }
    onSelChanged: rows.positionViewAtIndex(sel, ListView.Contain)

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

    // поиск по содержимому: имена файлов с совпадением; заголовки фильтруются сразу в view
    Process {
        id: grep
        stdout: StdioCollector {
            onStreamFinished: root.hits = text.split("\n").filter(l => l.endsWith(".md"))
        }
    }
    Timer {
        id: searchTimer
        interval: 150
        onTriggered: {
            if (root.query === "") { root.hits = []; return; }
            grep.command = ["sh", "-c", 'cd "$1" || exit 0; grep -ilF -e "$2" -- *.md 2>/dev/null', "sh", root.dir, root.query];
            grep.running = true;
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

    Process {
        id: copyText
        stdinEnabled: true
        command: ["wl-copy"]
        property string payload: ""
        onStarted: { write(payload); stdinEnabled = false; }
        onExited: root.blink()
    }
    Process { id: copyFile; onExited: root.blink() }

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
            width: 1008
            height: Math.min(stage.height - 280, 684)
            opacity: root.t
            radius: Theme.corner(44)
            color: Theme.s1
            border { width: 1; color: Theme.s2 }
            clip: true

            MouseArea { anchors.fill: parent }

            // пилюля поиска как у Win+V: лупа, поле, × очистки и две пилюли в одной строке
            Rectangle {
                id: pill
                x: 30
                y: 26
                width: parent.width - 60
                height: 62
                radius: 31
                color: Theme.s2

                Icon { id: lens; x: 22; anchors.verticalCenter: parent.verticalCenter; text: "\u{F0349}"; color: Theme.grey; font.pixelSize: 20 }

                TextInput {
                    id: input
                    anchors { left: lens.right; leftMargin: 14; right: clearBtn.left; rightMargin: 10; verticalCenter: parent.verticalCenter }
                    font { family: Theme.ui; pixelSize: 20 }
                    color: Theme.fg
                    selectionColor: Theme.s3
                    selectedTextColor: Theme.fg
                    clip: true
                    cursorDelegate: Rectangle {
                        width: 2
                        color: Theme.accent
                        Timer { running: input.activeFocus; interval: 520; repeat: true; onTriggered: parent.opacity = 1 - parent.opacity }
                    }
                    Text {
                        visible: !input.text
                        x: 2
                        text: "Search notes"
                        font: input.font
                        color: Theme.mute
                    }
                    onTextChanged: {
                        root.query = text;
                        root.sel = 0;
                        if (text.length && !root.drawer) root.drawer = true;
                    }
                    Keys.onPressed: e => {
                        if (e.key === Qt.Key_Escape) {
                            if (input.text) input.text = "";
                            else { root.drawer = false; ed.forceActiveFocus(); }
                        } else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
                            if (root.view[root.sel]) root.load(root.view[root.sel].name);
                        } else if (e.key === Qt.Key_Up) {
                            root.sel = Math.max(0, root.sel - 1);
                        } else if (e.key === Qt.Key_Down) {
                            root.sel = Math.min(root.view.length - 1, root.sel + 1);
                        } else if (e.key === Qt.Key_Delete && input.text === "") {
                            if (root.view[root.sel]) root.burn(root.view[root.sel].name);
                        } else if (e.key === Qt.Key_Tab || e.key === Qt.Key_Backtab) {
                            rows.forceActiveFocus();
                        } else return;
                        e.accepted = true;
                    }
                }

                Rectangle {
                    id: clearBtn
                    anchors { right: chips.left; rightMargin: 10; verticalCenter: parent.verticalCenter }
                    width: 34
                    height: 34
                    radius: 17
                    visible: input.text.length > 0
                    color: clearHov.hovered ? Theme.fg : "transparent"
                    Text {
                        anchors.centerIn: parent
                        text: "×"
                        font { family: Theme.ui; pixelSize: 20; weight: Font.Medium }
                        color: clearHov.hovered ? Theme.ink : Theme.grey
                    }
                    TapHandler { onTapped: { input.text = ""; input.forceActiveFocus(); } }
                    HoverHandler { id: clearHov; cursorShape: Qt.PointingHandCursor }
                }

                Row {
                    id: chips
                    anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                    spacing: 6
                    component Chip: Rectangle {
                        id: c
                        property string label
                        signal tapped
                        width: lab.implicitWidth + 30
                        height: 42
                        radius: 21
                        color: hov.hovered ? Theme.fg : Theme.s3
                        Behavior on color { ColorAnimation { duration: 150 } }
                        Lb { id: lab; anchors.centerIn: parent; text: c.label; px: 10; color: hov.hovered ? Theme.ink : Theme.grey }
                        TapHandler { onTapped: c.tapped() }
                        HoverHandler { id: hov; cursorShape: Qt.PointingHandCursor }
                    }
                    Chip { label: "+ new"; onTapped: root.fresh() }
                    Chip { label: "notes"; onTapped: root.history() }
                }
            }

            TextEdit {
                id: ed
                anchors { fill: parent; leftMargin: 42; rightMargin: 42; topMargin: 114; bottomMargin: 64 }
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
                    } else if (ctrl && e.key === Qt.Key_H) {
                        root.history();
                    } else if (e.key === Qt.Key_Tab) {
                        ed.insert(ed.cursorPosition, "    ");
                    } else return;
                    e.accepted = true;
                }
                onTextChanged: if (!root.loader) autosave.restart()
            }

            Text {
                x: 44
                y: 116
                visible: ed.text.length === 0
                text: "start typing…"
                textFormat: Text.PlainText
                font: ed.font
                color: Theme.mute
            }

            // сколько слов в заметке — мелкая деталь внизу справа, под редактором
            Lb {
                anchors { right: parent.right; rightMargin: 42; bottom: parent.bottom; bottomMargin: 22 }
                text: root.words === 1 ? "1 word" : root.words + " words"
                color: Theme.mute
                opacity: root.words ? 1 : 0
            }

            // история: выкатывается из-под правого края, карточка её подрезает
            Rectangle {
                id: sheet
                width: 360
                y: 110
                height: parent.height - 110 - 18
                x: parent.width - 18 - width + (width + 30) * (1 - root.dt)
                radius: Theme.corner(40)
                color: Theme.s2
                z: 3

                Lb { id: hlab; x: 28; y: 24; text: "notes" }
                Num { anchors.baseline: hlab.baseline; x: hlab.implicitWidth + 42; text: root.view.length; font.pixelSize: 26; color: Theme.grey }

                ListView {
                    id: rows
                    anchors { left: parent.left; right: parent.right; top: hlab.bottom; bottom: parent.bottom; margins: 18 }
                    clip: true
                    spacing: 4
                    model: root.view
                    boundsBehavior: Flickable.StopAtBounds
                    keyNavigationEnabled: false
                    section.property: "bucket"
                    section.delegate: Lb {
                        required property string section
                        text: section
                        px: 9
                        x: 20
                        topPadding: 12
                        bottomPadding: 4
                        color: Theme.mute
                    }
                    delegate: Note {}
                    Keys.onPressed: e => {
                        if (e.key === Qt.Key_Up) {
                            root.sel = Math.max(0, root.sel - 1);
                        } else if (e.key === Qt.Key_Down) {
                            root.sel = Math.min(root.view.length - 1, root.sel + 1);
                        } else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
                            if (root.view[root.sel]) root.load(root.view[root.sel].name);
                        } else if (e.key === Qt.Key_Delete) {
                            if (root.view[root.sel]) root.burn(root.view[root.sel].name);
                        } else if (e.key === Qt.Key_Escape) {
                            root.drawer = false;
                            ed.forceActiveFocus();
                        } else if (e.key === Qt.Key_Tab || e.key === Qt.Key_Backtab) {
                            input.forceActiveFocus();
                        } else return;
                        e.accepted = true;
                    }
                }

                Lb {
                    visible: root.view.length === 0
                    anchors.centerIn: parent
                    text: root.query ? "no matches" : "no notes yet"
                }
            }

            // строка истории: заголовок (первая строка файла) и время; текущая — белая пилюля,
            // выбранная с клавиатуры — подсветка как при наведении
            component Note: Rectangle {
                id: row
                required property var modelData
                required property int index
                readonly property bool on: root.dir + "/" + modelData.name === root.cur
                width: rows.width
                height: 72
                radius: 20
                color: row.on ? Theme.fg : (hov.hovered || root.sel === index) ? Theme.s3 : "transparent"
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
                    spacing: 6
                    Rectangle {
                        width: 30
                        height: 30
                        radius: 15
                        visible: hov.hovered
                        color: cp.hovered ? Theme.fg : row.on ? "transparent" : Theme.s1
                        Icon {
                            anchors.centerIn: parent
                            text: "\u{F0C5}"
                            font.pixelSize: 15
                            color: cp.hovered ? Theme.ink : row.on ? Theme.ink : Theme.grey
                        }
                        TapHandler { id: cp; onTapped: root.copyNote(row.modelData.name) }
                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                    }
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

                // открытие — только слева от кнопок: иначе тап по × ещё и «открывал» заметку
                // и закрывал историю, а удалённый файл подставлялся в редактор
                Rectangle {
                    anchors { left: parent.left; top: parent.top; bottom: parent.bottom; right: tail.left }
                    color: "transparent"
                    TapHandler { onTapped: root.load(row.modelData.name) }
                }

                HoverHandler { id: hov; cursorShape: Qt.PointingHandCursor }
            }

            // хинты под карточкой — как у Win+V
            Row {
                anchors { horizontalCenter: parent.horizontalCenter; top: parent.bottom; topMargin: 24 }
                spacing: 24
                Lb { text: "ctrl+space new" }
                Lb { text: "ctrl+h notes" }
                Lb { text: "ctrl+s save" }
                Lb { text: "esc close" }
                Lb { text: root.flashText; color: Theme.fg; opacity: root.flash }
            }
        }
    }
}
