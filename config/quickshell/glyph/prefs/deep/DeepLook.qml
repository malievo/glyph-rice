import QtQuick
import qs
import qs.components
import ".."

// LOOK глубже: папки обоев и гифок. Пусто — умолчание, оно же в подсказке поля
DeepPage {
    caption: "look · advanced · folders"

    DeepGroup { text: "folders" }

    DeepRow {
        label: "wallpapers"
        sub: "empty — ~/Pictures/Wallpapers"
        DeepField {
            placeholder: "~/Pictures/Wallpapers"
            text: Theme.state.wallDir
            onEdited: t => Theme.state.wallDir = t
        }
    }
    DeepRow {
        label: "gifs"
        sub: "empty — ~/Pictures/Gifs"
        DeepField {
            placeholder: "~/Pictures/Gifs"
            text: Theme.state.gifDir
            onEdited: t => Theme.state.gifDir = t
        }
    }
    Lb { topPadding: 20; text: "plain paths · the pickers read them when they open"; px: 10 }
}
