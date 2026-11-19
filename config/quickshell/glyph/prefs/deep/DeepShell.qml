import QtQuick
import qs
import qs.components
import ".."

// SHELL глубже: умолчания записи — те же, что по правому клику на record в quick
DeepPage {
    caption: "shell · advanced · recording"

    DeepGroup { text: "recording" }

    Row {
        spacing: 24
        Pick { label: "area"; opts: ["screen", "region"]; cur: Theme.state.recArea; onPicked: i => Theme.state.recArea = i }
        Pick { label: "audio"; opts: ["off", "sys", "mic", "both"]; cur: Theme.state.recAudio; onPicked: i => Theme.state.recAudio = i }
    }
    Item { width: 1; height: 20 }
    Row {
        spacing: 24
        Pick { label: "fps"; opts: Sys.recFps; cur: Math.max(0, Sys.recFps.indexOf(Theme.state.recFps)); onPicked: i => Theme.state.recFps = Sys.recFps[i] }
        Pick { label: "quality"; opts: ["med", "high", "max", "ultra"]; cur: Theme.state.recQuality; onPicked: i => Theme.state.recQuality = i }
    }
    Item { width: 1; height: 20 }
    Row {
        spacing: 24
        Pick { label: "cursor"; opts: ["on", "off"]; cur: Theme.state.recCursor ? 0 : 1; onPicked: i => Theme.state.recCursor = i === 0 }
    }
    Lb { topPadding: 20; text: "the same as right-click on record in quick · files land in ~/videos"; px: 10 }
}
