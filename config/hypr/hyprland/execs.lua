local vars = require("variables")
local fn   = require("hyprland.functions")

hl.on("hyprland.start", function()
    -- Shell: тот, что выбран в rice
    -- погода: фиксируем координаты (Москва, пр. Свободный 19), иначе определится по IP
    hl.env("DEMONSHOT_LATLON", "55.758742,37.820825")
    hl.exec_cmd(vars.rice .. " start")

    -- во вложенной сессии системные демоны уже работают снаружи
    if vars.nested then return end

    -- Keyring and auth
    hl.exec_cmd("gnome-keyring-daemon --start --components=secrets")
    hl.exec_cmd("/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1")

    -- Bluetooth agent: без него BlueZ не спросит код сопряжения, и наушники вроде Ear (3) не спарятся из Quick
    hl.exec_cmd("blueman-applet")

    -- Clipboard history
    hl.exec_cmd("wl-paste --type text --watch cliphist store")
    hl.exec_cmd("wl-paste --type image --watch cliphist store")

    -- Auto delete trash 30 days old
    hl.exec_cmd("trash-empty 30")

    -- Cursors
    hl.exec_cmd("hyprctl setcursor " .. vars.cursorTheme .. " " .. vars.cursorSize)
    hl.exec_cmd("gsettings set org.gnome.desktop.interface cursor-theme " .. vars.cursorTheme)
    hl.exec_cmd("gsettings set org.gnome.desktop.interface cursor-size " .. vars.cursorSize)

    -- Location provider
    hl.exec_cmd("/usr/lib/geoclue-2.0/demos/agent")

    -- Forward bluetooth media commands to MPRIS
    hl.exec_cmd("mpris-proxy")

    -- hypridle поднимает шелл (Rules.idle): тайминги из house rules → ~/.config/demonshot/hypridle.conf
end)

-- Resizer listener
-- Bitwarden: плавающее окно только для десктоп-приложения (class Bitwarden) и popup-окна расширения
-- ("Extension: (Bitwarden ..."). Раньше искали "Bitwarden" в любом заголовке: любая вкладка/терминал с этим словом
-- сжималась в маленькое окно, а на каждую смену title размер сбрасывался. Теперь — один раз на окно.
local bw_done = {}
local function bitwarden(win)
    if not win or bw_done[win.address] then return end
    local cls, title = win.class or "", win.title or ""
    if cls == "Bitwarden" or title:find("^Extension: %(Bitwarden") then
        bw_done[win.address] = true
        hl.dispatch(hl.dsp.window.float({ action = "on", window = win }))
        hl.dispatch(hl.dsp.window.center({ window = win }))
        hl.dispatch(hl.dsp.window.resize(fn.resize_by_screen(30, 60)))
    end
end

hl.on("window.title", function(win)
    bitwarden(win)
    fn.resizer(win, "Picture[- ]in[- ][Pp]icture", 0, 0, fn.move_actions(win) or {}, false)
end)

hl.on("window.open", function(win)
    bitwarden(win)
    fn.resizer(win, "Picture[- ]in[- ][Pp]icture", 0, 0, fn.move_actions(win) or {}, false)
end)
