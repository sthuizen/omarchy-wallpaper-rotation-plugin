import QtQuick
import Quickshell
import Quickshell.Io

Item {
  id: root

  readonly property string home: Quickshell.env("HOME")
  readonly property string themeNamePath: home + "/.local/state/omarchy/current/theme.name"
  readonly property string controlPath: decodeURIComponent(
    String(Qt.resolvedUrl("WallpaperRotation.sh")).replace(/^file:\/\//, ""))

  property bool ready: false
  property bool enabled: true
  property bool timerActive: false
  property int intervalMinutes: 60
  property string mode: "sequential"
  property int nextInMinutes: -1
  property string currentWallpaper: ""
  property string currentTheme: ""
  property var wallpapers: []
  property bool busy: false
  property string lastAction: ""
  property string lastError: ""

  readonly property bool shuffle: root.mode === "shuffle"

  function wallpaperName(path) {
    var base = String(path || "").replace(/\\/g, "/").split("/").pop()
    base = base.replace(/\.[^.]+$/, "").replace(/[-_.]+/g, " ")
    return base.replace(/\b[a-z]/g, function(letter) { return letter.toUpperCase() })
      .replace(/\s+/g, " ").trim() || "Unknown"
  }

  function intervalLabel(minutes) {
    if (minutes < 60) return minutes + " min"
    if (minutes % 60 === 0) {
      var hours = minutes / 60
      return hours + (hours === 1 ? " hour" : " hours")
    }
    return minutes + " min"
  }

  function statusText() {
    if (!root.enabled) return "Automatic rotation is off"
    if (!root.timerActive) return "Rotation timer is not running"
    var next = root.nextInMinutes >= 0 ? " · next in " + root.nextInMinutes + " min" : ""
    return root.intervalLabel(root.intervalMinutes) + " · "
      + (root.shuffle ? "shuffle" : "sequential") + next
  }

  function refreshStatus() {
    if (!statusProc.running) statusProc.running = true
  }

  function refreshCatalog() {
    if (!catalogProc.running) catalogProc.running = true
  }

  function refreshAll() {
    root.refreshStatus()
    root.refreshCatalog()
  }

  function runAction(args, successText) {
    if (root.busy) return
    root.busy = true
    root.lastError = ""
    root.lastAction = successText || ""
    actionProc.command = [root.controlPath].concat(args)
    actionProc.running = true
  }

  function setEnabled(value) {
    root.runAction(["configure", "enabled", value ? "true" : "false"],
                   value ? "Automatic rotation enabled" : "Automatic rotation disabled")
  }

  function setInterval(minutes) {
    root.runAction(["configure", "intervalMinutes", String(minutes)], "Rotation interval updated")
  }

  function setMode(value) {
    root.runAction(["configure", "mode", value], "Rotation order updated")
  }

  function applyNext() {
    root.runAction(["next"], "Advanced to the next wallpaper")
  }

  function setWallpaper(path) {
    if (!path) return
    root.runAction(["set", String(path)], "Wallpaper changed")
  }

  FileView {
    id: themeNameFile
    path: root.themeNamePath
    watchChanges: true
    printErrors: false
    onLoaded: {
      root.currentTheme = String(text() || "").trim()
      root.refreshAll()
    }
    onFileChanged: reload()
  }

  Process {
    id: initProc
    command: [root.controlPath, "init"]
    stderr: StdioCollector { id: initError; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) root.lastError = String(initError.text || "Initialization failed").trim()
      root.ready = exitCode === 0
      root.refreshAll()
    }
  }

  Process {
    id: statusProc
    command: [root.controlPath, "status"]
    stdout: StdioCollector { id: statusOutput; waitForEnd: true }
    stderr: StdioCollector { id: statusError; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.lastError = String(statusError.text || "Could not read rotation status").trim()
        return
      }
      try {
        var state = JSON.parse(statusOutput.text || "{}")
        root.enabled = state.enabled === true
        root.timerActive = state.timerActive === true
        root.intervalMinutes = Number(state.intervalMinutes || 60)
        root.mode = state.mode === "shuffle" ? "shuffle" : "sequential"
        root.nextInMinutes = Number(state.nextInMinutes === undefined ? -1 : state.nextInMinutes)
        root.currentWallpaper = String(state.current || "")
        root.currentTheme = String(state.theme || root.currentTheme)
        root.ready = true
      } catch (error) {
        root.lastError = "Invalid status response: " + error
      }
    }
  }

  Process {
    id: catalogProc
    command: [root.controlPath, "catalog"]
    stdout: StdioCollector { id: catalogOutput; waitForEnd: true }
    stderr: StdioCollector { id: catalogError; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.lastError = String(catalogError.text || "Could not list wallpapers").trim()
        return
      }
      try {
        var entries = JSON.parse(catalogOutput.text || "[]")
        var result = []
        for (var i = 0; i < entries.length; i++) {
          if (!entries[i].path) continue
          result.push({ path: String(entries[i].path), name: root.wallpaperName(entries[i].path) })
        }
        root.wallpapers = result
      } catch (error) {
        root.lastError = "Invalid wallpaper catalog: " + error
      }
    }
  }

  Process {
    id: actionProc
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { id: actionError; waitForEnd: true }
    onExited: function(exitCode) {
      root.busy = false
      if (exitCode !== 0) root.lastError = String(actionError.text || "Wallpaper action failed").trim()
      else root.lastError = ""
      root.refreshAll()
    }
  }

  Timer {
    interval: 60000
    running: root.ready
    repeat: true
    onTriggered: root.refreshStatus()
  }

  Component.onCompleted: initProc.running = true
}
