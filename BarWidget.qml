import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui

BarWidget {
  id: root
  moduleName: "thenailedone.wallpaper-rotation"

  readonly property var service: bar && bar.shell ? bar.shell.serviceFor(root.moduleName) : null
  readonly property bool ready: service !== null && service.ready
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    target.bar = root.bar
    target.anchorItem = button
    target.hostWidget = root
    target.service = root.service
  }

  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function toggle() { if (panelLoader.item) panelLoader.item.toggle() }

  onBarChanged: injectPanel()
  onServiceChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  IpcHandler {
    target: root.moduleName
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function next(): void { if (root.ready) root.service.applyNext() }
    function enable(): void { if (root.ready) root.service.setEnabled(true) }
    function disable(): void { if (root.ready) root.service.setEnabled(false) }
    function status(): string { return root.ready ? root.service.statusText() : "service unavailable" }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰉊"
    dimmed: !root.ready || !root.service.enabled
    active: root.ready && root.service.lastError !== ""
    tooltipText: !root.ready ? "Wallpaper Rotation unavailable" : root.service.statusText()
    onPressed: function(code) {
      if (code === Qt.MiddleButton && root.ready) root.service.applyNext()
      else root.toggle()
    }
  }
}
