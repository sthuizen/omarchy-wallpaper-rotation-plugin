import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Commons
import qs.Ui

Panel {
  id: root
  moduleName: "thenailedone.wallpaper-rotation"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property var service: null
  readonly property var barIdentity: hostWidget || root
  readonly property color foreground: bar ? bar.foreground : Commons.Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.45)
  readonly property color urgent: bar ? bar.urgent : Commons.Color.urgent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property real cellSize: Style.space(92)
  readonly property real cellSpacing: Style.space(8)
  readonly property int gridColumns: Math.max(1, Math.floor(
    ((content ? content.width : 0) + cellSpacing) / (cellSize + cellSpacing)))
  readonly property int gridRows: Math.ceil(
    (service ? service.wallpapers.length : 0) / gridColumns)
  readonly property real gridHeight: gridRows * cellSize
    + (gridRows > 1 ? (gridRows - 1) * cellSpacing : 0)
  readonly property var intervalOptions: [
    { value: "5", label: "Every 5 min" },
    { value: "15", label: "Every 15 min" },
    { value: "30", label: "Every 30 min" },
    { value: "45", label: "Every 45 min" },
    { value: "60", label: "Every hour" },
    { value: "120", label: "Every 2 hours" },
    { value: "240", label: "Every 4 hours" },
    { value: "480", label: "Every 8 hours" },
    { value: "720", label: "Every 12 hours" },
    { value: "1440", label: "Every day" }
  ]
  readonly property var modeOptions: [
    { value: "sequential", label: "Sequential" },
    { value: "shuffle", label: "Shuffle" }
  ]

  function open() {
    if (service) service.refreshAll()
    controller.show()
  }

  function close() { controller.hide() }
  function toggle() { opened ? close() : open() }

  function switchPanel(direction) {
    if (bar && typeof bar.switchPanelFrom === "function")
      return bar.switchPanelFrom(barIdentity, direction)
    return false
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(430))
    contentHeight: panel.fittedContentHeight(content.implicitHeight, Style.space(650))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(text) {
        if ((text === "n" || text === "N") && root.service) root.service.applyNext()
        else if ((text === "e" || text === "E") && root.service)
          root.service.setEnabled(!root.service.enabled)
      }

      Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: content.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        ColumnLayout {
          id: content
          width: parent.width
          spacing: Style.space(12)

          PanelHero {
            Layout.fillWidth: true
            title: "Wallpaper Rotation"
            meta: root.service ? root.service.statusText() : "Service unavailable"
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconComponent: Component {
              Text {
                text: "󰉊"
                textFormat: Text.PlainText
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.display
              }
            }
          }

          PanelSeparator { Layout.fillWidth: true; foreground: root.foreground }

          PanelSectionHeader {
            Layout.fillWidth: true
            text: "ACTIVE THEME WALLPAPERS"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Text {
            Layout.fillWidth: true
            text: !root.service ? "" : root.service.wallpapers.length + " wallpaper"
              + (root.service.wallpapers.length === 1 ? "" : "s")
              + " · " + root.service.wallpaperName(root.service.currentTheme)
            textFormat: Text.PlainText
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          Flow {
            Layout.fillWidth: true
            Layout.preferredHeight: root.gridHeight
            spacing: root.cellSpacing

            Repeater {
              model: root.service ? root.service.wallpapers : []

              delegate: Rectangle {
                id: cell
                required property var modelData
                readonly property bool isCurrent: root.service
                  && root.service.currentWallpaper === modelData.path
                width: root.cellSize
                height: root.cellSize
                color: root.foreground
                clip: true

                Image {
                  anchors.fill: parent
                  source: root.opened ? Util.fileUrl(cell.modelData.path) : ""
                  sourceSize: Qt.size(256, 256)
                  fillMode: Image.PreserveAspectCrop
                  asynchronous: true
                  cache: false
                  smooth: true
                }

                Rectangle {
                  anchors.fill: parent
                  color: Util.alpha(root.foreground, cell.isCurrent ? 0 : 0.20)
                }

                Rectangle {
                  anchors.fill: parent
                  color: "transparent"
                  border.color: cell.isCurrent ? Commons.Color.accent : root.dim
                  border.width: cell.isCurrent ? 3 : 1
                }

                ToolTip.visible: mouse.containsMouse
                ToolTip.text: cell.modelData.name
                ToolTip.delay: 500

                MouseArea {
                  id: mouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  enabled: root.service && !root.service.busy
                  onClicked: root.service.setWallpaper(cell.modelData.path)
                }
              }
            }
          }

          Text {
            Layout.fillWidth: true
            text: "Click a preview to apply it. Manual selections restart the full interval."
            textFormat: Text.PlainText
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

          PanelSeparator { Layout.fillWidth: true; foreground: root.foreground }

          PanelSectionHeader {
            Layout.fillWidth: true
            text: "SCHEDULE"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Toggle {
            Layout.fillWidth: true
            label: "Automatic rotation"
            description: "Uses a persistent user timer and Omarchy's supported background commands."
            checked: root.service ? root.service.enabled : false
            foreground: root.foreground
            accent: Commons.Color.accent
            fontFamily: root.fontFamily
            enabled: root.service && !root.service.busy
            onClicked: root.service.setEnabled(!root.service.enabled)
          }

          RowLayout {
            Layout.fillWidth: true
            spacing: Style.space(8)

            Dropdown {
              Layout.fillWidth: true
              label: "Interval"
              value: root.service ? String(root.service.intervalMinutes) : "60"
              options: root.intervalOptions
              foreground: root.foreground
              fontFamily: root.fontFamily
              enabled: root.service && !root.service.busy
              onChanged: function(value) { if (root.service) root.service.setInterval(Number(value)) }
            }

            Dropdown {
              Layout.fillWidth: true
              label: "Order"
              value: root.service ? root.service.mode : "sequential"
              options: root.modeOptions
              foreground: root.foreground
              fontFamily: root.fontFamily
              enabled: root.service && !root.service.busy
              onChanged: function(value) { if (root.service) root.service.setMode(value) }
            }
          }

          Button {
            Layout.fillWidth: true
            text: root.service && root.service.busy ? "Applying…" : "Apply next wallpaper now"
            iconText: "󰑐"
            bordered: true
            focusable: true
            enabled: root.service && !root.service.busy
            foreground: root.foreground
            accent: Commons.Color.accent
            fontFamily: root.fontFamily
            onClicked: root.service.applyNext()
          }

          Text {
            Layout.fillWidth: true
            visible: root.service && (root.service.lastError !== "" || root.service.lastAction !== "")
            text: root.service && root.service.lastError !== ""
              ? root.service.lastError : (root.service ? root.service.lastAction : "")
            textFormat: Text.PlainText
            color: root.service && root.service.lastError !== "" ? root.urgent : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

          Text {
            Layout.fillWidth: true
            text: "Sequential mode delegates rotation to “omarchy theme bg next”. "
              + "Shuffle mode builds a non-repeating queue and applies each entry with “omarchy theme bg set”."
            textFormat: Text.PlainText
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }
        }
      }
    }
  }
}
