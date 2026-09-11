import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

BarWidget {
  id: root
  moduleName: "ninepointlabs.upcoming"

  readonly property var service: panelLoader.item ? panelLoader.item.service : null
  readonly property int revision: service ? service.revision : 0
  readonly property bool showNext: setting("showNext", true) === true
  readonly property string labelText: showNext && service ? service.barText : ""
  readonly property var nextShow: service ? service.nextShow : null

  readonly property color chipColor: {
    if (!bar) return Color.foreground
    if (nextShow) return bar.barForeground
    return Qt.darker(bar.barForeground, 1.5)
  }

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  function anyOpened() {
    var items = bar && typeof bar.moduleWidgets === "function" ? bar.moduleWidgets(moduleName) : [root]
    for (var i = 0; i < items.length; i++) if (items[i] && items[i].opened === true) return true
    return false
  }

  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function togglePanel() { if (panelLoader.item) panelLoader.item.toggle() }

  readonly property real openPanelIndicatorWidth: button.width
  readonly property real openPanelIndicatorHeight: Math.max(Style.space(10), Math.round(Style.bar.iconSlot * 0.55))
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false
  function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

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
    target: "ninepointlabs.upcoming"

    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.togglePanel() }
    function isOpen(): string { return root.anyOpened() ? "true" : "false" }
    function refresh(): void { if (root.service) root.service.refresh() }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: ""
    labelVisible: false
    hasVisualContent: true
    fixedWidth: root.vertical ? -1 : Math.round(chipRow.implicitWidth + Style.spaceReal(horizontalMargin) * 2)
    fixedHeight: root.vertical ? Style.bar.iconSlot : -1
    horizontalMargin: root.labelText !== "" && !root.vertical ? 7 : 6
    tooltipText: root.labelText !== "" ? "Upcoming · " + root.labelText : "Upcoming · your next episodes"

    onPressed: function(b) {
      if (b === Qt.MiddleButton) { if (root.service) root.service.refresh() }
      else root.togglePanel()
    }

    Row {
      id: chipRow
      anchors.centerIn: parent
      spacing: Style.space(6)

      OpticalGlyph {
        width: Style.bar.iconCanvas + Style.space(2)
        height: width
        anchors.verticalCenter: parent.verticalCenter
        text: "󰑈"
        fontFamily: button.fontFamily
        fontSize: Style.bar.iconFont
        color: root.chipColor
      }

      Text {
        visible: !root.vertical && root.labelText !== ""
        textFormat: Text.PlainText
        text: root.labelText
        color: root.chipColor
        font.family: button.fontFamily
        font.pixelSize: Style.font.body
        anchors.verticalCenter: parent.verticalCenter
      }
    }
  }
}
