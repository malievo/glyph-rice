pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.SystemTray

// статус Happ для бара: подключён ли, текущий сервер, код страны. Читает пункты трея Happ (dbusmenu), как панель vpn/Happ.qml.
// ponytail: подписи русские, как в трее Happ; другой язык — поменять регэкспы
Singleton {
    id: root

    readonly property var item: SystemTray.items.values.find(i => i.id === "Happ" || i.title === "Happ") ?? null
    QsMenuOpener { id: tray; menu: root.item?.menu ?? null }
    QsMenuOpener { id: srv; menu: tray.children.values.find(e => !e.isSeparator && /сервер|server/i.test(e.text)) ?? null }

    readonly property string status: tray.children.values.find(e => !e.isSeparator)?.text ?? ""
    readonly property bool live: /^(подключено|connected)/i.test(status)
    readonly property string name: srv.children.values.find(e => !e.isSeparator && e.checkState === Qt.Checked)?.text.split(/\s*\|\s*/)[0].trim() ?? ""

    function child(re) { return tray.children.values.find(e => !e.isSeparator && re.test(e.text)) ?? null; }
    // вкл/выкл — только пункты трея: второй запуск Happ (с happ:// или без) поднимает его окно.
    // Нет значка в трее: не запущен — стартуем свёрнутым (--autostart; он сам подключается), запущен — ещё поднимается, ждём
    function flip() {
        if (!item) return Quickshell.execDetached(["sh", "-c", "pgrep -x Happ >/dev/null || exec /opt/happ/bin/Happ --autostart"]);
        child(live ? /^отключ|^disconnect/i : /^подключ|^connect/i)?.triggered();
    }

    readonly property var cities: ({ "Амстердам": "NL", "Стокгольм": "SE", "Хельсинки": "FI", "Париж": "FR", "Варшава": "PL", "Рим": "IT", "Франкфурт": "DE", "Берлин": "DE", "Лондон": "GB", "Вена": "AT", "Мадрид": "ES", "Цюрих": "CH", "Прага": "CZ", "Москва": "RU", "Токио": "JP", "Стамбул": "TR", "Дубай": "AE" })
    readonly property string cc: cities[name.replace(/\s*#\d+$/, "")] ?? "··"
}
