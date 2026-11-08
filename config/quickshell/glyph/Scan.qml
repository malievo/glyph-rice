pragma Singleton

import QtQuick
import Quickshell

// физические клавиши по scan code (evdev+8 — так Qt отдаёт его на Wayland): раскладка не важна.
// В ru та же клавиша даёт кириллицу, и e.key уже не равен Qt.Key_S — голые буквенные хоткеи сравниваем здесь
Singleton {
    id: root

    readonly property var codes: ({
        q: 24, w: 25, e: 26, r: 27, t: 28, y: 29, u: 30, i: 31, o: 32, p: 33,
        a: 38, s: 39, d: 40, f: 41, g: 42, h: 43, j: 44, k: 45, l: 46,
        z: 52, x: 53, c: 54, v: 55, b: 56, n: 57, m: 58,
        leftBracket: 34, rightBracket: 35
    })
    function hit(e, name) { return e.nativeScanCode === codes[name]; }
}
