pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.SystemTray

// статус Happ для бара: подключён ли, текущий сервер, код страны. Читает пункты трея Happ (dbusmenu), как панель vpn/Happ.qml.
// ponytail: подписи русские, как в трее Happ; другой язык — поменять регэкспы
Singleton {
    id: root

    readonly property var item: SystemTray.items.values.find(i => i.id === "Happ" || i.title === "Happ") ?? null
    QsMenuOpener { id: tray; menu: root.item?.menu ?? null }
    // «Сменить сервер» (или «Сервер»/«Change server»); якорь с начала строки: статус «Подключено <сервер>» тоже содержит «сервер»
    readonly property var srv: tray.children.values.find(e => !e.isSeparator && /^(?:сменить\s+)?сервер|^(?:change\s+|switch\s+)?servers?/i.test(e.text)) ?? null
    QsMenuOpener { id: srvm; menu: root.srv }

    readonly property string status: tray.children.values.find(e => !e.isSeparator)?.text ?? ""
    readonly property bool live: /^(подключено|connected)/i.test(status)
    readonly property string srvText: srvm.children.values.find(e => !e.isSeparator && e.checkState === Qt.Checked)?.text ?? ""
    readonly property string name: plain(srvText.split(/\s*\|\s*/)[0] ?? "")

    function child(re) { return tray.children.values.find(e => !e.isSeparator && re.test(e.text)) ?? null; }
    // вкл/выкл — только пункты трея: второй запуск Happ (с happ:// или без) поднимает его окно.
    // Нет значка в трее: не запущен — стартуем свёрнутым (--autostart; он сам подключается), запущен — ещё поднимается, ждём
    function flip() {
        if (!item) return Quickshell.execDetached(["sh", "-c", "pgrep -x Happ >/dev/null || exec /opt/happ/bin/Happ --autostart"]);
        child(live ? /^отключ|^disconnect/i : /^подключ|^connect/i)?.triggered();
    }

    // «Финляндия⚜️» → «Финляндия»: значки и эмодзи в названиях серверов ломают поиск по таблице
    function plain(s) {
        let t = "";
        for (const ch of s) if (ch.codePointAt(0) < 0x2000) t += ch;
        return t.replace(/\s*#\d+$/, "").trim();
    }
    // страны — из системного CLDR (iso-codes, countries.json): названия на 11 языках и ISO-коды, без таблиц под провайдера
    property var names: ({})
    property var iso: ({})
    FileView {
        id: cdb
        path: Qt.resolvedUrl("countries.json").toString().replace("file://", "")
        printErrors: false
        onLoaded: {
            const out = {}, set = {};
            try {
                const j = JSON.parse(text());
                for (const loc in j) for (const n in j[loc]) {
                    out[root.norm(n)] = j[loc][n];
                    set[j[loc][n]] = true;
                }
            } catch (e) {}
            root.names = out;
            root.iso = set;
        }
    }
    // разговорные названия, которых нет в CLDR
    readonly property var aliases: ({ "великобритания": "GB", "сша": "US", "соединенные штаты": "US", "оаэ": "AE", "эмираты": "AE", "южная корея": "KR", "корея": "KR", "северная корея": "KP", "тайвань": "TW", "молдавия": "MD", "молдова": "MD", "сирия": "SY", "лаос": "LA", "бруней": "BN", "венесуэла": "VE" })
    function norm(s) { return s.toLowerCase().replace(/ё/g, "е").replace(/\s+/g, " ").trim(); }
    // код страны по названию любого провайдера: флаг → название страны → ISO-токен → «··»
    function ccOf(text, name) {
        const flag = [...text].map(c => c.codePointAt(0)).filter(c => c >= 0x1F1E6 && c <= 0x1F1FF).map(c => String.fromCharCode(c - 0x1F1E6 + 65)).join("");
        if (flag.length >= 2) return flag.slice(0, 2);
        const key = norm(name);
        if (names[key]) return names[key];
        if (aliases[key]) return aliases[key];
        const m = /(?:^|[^A-Za-z])([A-Z]{2})(?=[^A-Za-z]|$)/.exec(text);
        if (m) return m[1];
        // «nl-1», «de #2» — токен в нижнем регистре засчитываем только перед цифрой/разделителем и только если это ISO-код
        const low = /(?:^|[^A-Za-z])([A-Za-z]{2})(?=[-_#\d])/.exec(text);
        if (low && iso[low[1].toUpperCase()]) return low[1].toUpperCase();
        return "··";
    }
    readonly property string cc: ccOf(srvText, name)

    // Happ наполняет «Сменить сервер» только по AboutToShow, а Quickshell шлёт его лишь корню меню:
    // без этого подменю пустое и в баре нет кода страны. После пробуждения обновляем модель подменю
    function wake() { if (!wakeP.running) wakeP.running = true; }
    Process {
        id: wakeP
        command: ["sh", Qt.resolvedUrl("happ-wake.sh").toString().replace("file://", "")]
        onExited: if (root.srv?.hasChildren) root.srv.updateLayout()
    }
    onItemChanged: if (item) wake()
    onSrvChanged: if (srv) wake()
    Component.onCompleted: Qt.callLater(root.wake)
}
