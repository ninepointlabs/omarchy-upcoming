import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "ninepointlabs.upcoming"

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  readonly property var sharedService: bar && bar.shell && typeof bar.shell.serviceFor === "function"
    ? bar.shell.serviceFor(moduleName) : null
  readonly property var service: sharedService || localService

  function pushSettings() { if (service) service.settings = settings }
  onSettingsChanged: pushSettings()
  onServiceChanged: pushSettings()
  Component.onCompleted: pushSettings()

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color accent: Color.accent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color dim: Qt.darker(foreground, 1.55)

  readonly property int revision: service ? service.revision : 0
  readonly property var shows: service && revision >= 0 ? service.shows : []
  readonly property var hits: service ? service.hits : []
  readonly property bool searching: service ? service.searching : false
  readonly property bool refreshing: service ? service.refreshing : false
  readonly property string lastError: service ? service.lastError : ""
  readonly property string actionStatus: service ? service.actionStatus : ""
  readonly property string statusText: lastError !== "" ? lastError : actionStatus
  readonly property bool statusIsError: lastError !== ""

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function submitSearch() {
    if (!service) return
    service.search(searchField.text)
  }

  implicitWidth: 1
  implicitHeight: 1

  onOpenedChanged: {
    if (!opened) return
    Qt.callLater(function() { searchField.forceActiveFocus() })
  }

  Service {
    id: localService
    active: false
  }
  Timer {
    interval: 2500
    running: root.bar !== null && root.sharedService === null && !localService.active
    onTriggered: if (root.sharedService === null) localService.active = true
  }
  onSharedServiceChanged: if (sharedService !== null && localService.active) localService.active = false

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: true
    focusTarget: searchField
    contentWidth: panel.fittedContentWidth(Style.space(420))
    contentHeight: panel.fittedContentHeight(mainColumn.implicitHeight + Style.space(24), Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: searchField.activeFocus
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

    Column {
      id: mainColumn
      width: parent.width
      spacing: Style.space(10)

      Item {
        width: parent.width
        implicitHeight: Math.max(titleColumn.implicitHeight, refreshButton.implicitHeight)

        Column {
          id: titleColumn
          anchors.left: parent.left
          anchors.right: refreshButton.left
          anchors.rightMargin: Style.space(8)
          spacing: Style.space(2)

          Text {
            textFormat: Text.PlainText
            text: "UPCOMING"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            font.bold: true
          }

          Text {
            visible: text !== ""
            width: parent.width
            textFormat: Text.PlainText
            text: root.statusText
            color: root.statusIsError ? Color.urgent : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.Wrap
          }
        }

        PanelActionButton {
          id: refreshButton
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          iconText: "󰑐"
          tooltipText: "Refresh air dates"
          foreground: root.foreground
          fontFamily: root.fontFamily
          onClicked: if (root.service) root.service.refresh()
        }
      }

      TextField {
        id: searchField
        width: parent.width
        placeholderText: "Find a show"
        foreground: root.foreground
        accent: root.accent
        Keys.onReturnPressed: root.submitSearch()
        Keys.onEnterPressed: root.submitSearch()
        Keys.onEscapePressed: function(event) {
          if (searchField.text !== "") { searchField.text = ""; event.accepted = true }
          else root.close()
        }
      }

      Text {
        visible: root.searching
        textFormat: Text.PlainText
        text: "Searching TVmaze…"
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }

      Column {
        visible: root.hits.length > 0
        width: parent.width
        spacing: Style.space(4)

        Text {
          textFormat: Text.PlainText
          text: "Pick the right one"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        Repeater {
          model: root.hits

          Rectangle {
            required property var modelData
            width: parent.width
            height: hitRow.implicitHeight + Style.space(10)
            radius: Style.cornerRadius
            color: hitMouse.containsMouse ? Style.hoverFillFor(root.foreground, root.accent) : "transparent"

            Row {
              id: hitRow
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: Style.space(6)
              anchors.rightMargin: Style.space(6)
              spacing: Style.space(8)

              Column {
                width: parent.width - addLabel.width - Style.space(8)
                spacing: Style.space(1)

                Text {
                  width: parent.width
                  textFormat: Text.PlainText
                  text: modelData.name
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  elide: Text.ElideRight
                }

                Text {
                  width: parent.width
                  textFormat: Text.PlainText
                  text: {
                    var bits = []
                    if (modelData.network) bits.push(modelData.network)
                    if (modelData.premiered) bits.push(String(modelData.premiered).substring(0, 4))
                    if (modelData.status) bits.push(modelData.status)
                    return bits.join(" · ")
                  }
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  elide: Text.ElideRight
                }
              }

              Text {
                id: addLabel
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: root.service && Model.alreadyOnList(root.shows, modelData.id) ? "Added" : "Add"
                color: root.accent
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }
            }

            MouseArea {
              id: hitMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: if (root.service) root.service.addShow(modelData)
            }
          }
        }
      }

      Text {
        visible: !root.searching && root.hits.length === 0 && searchField.text.length >= 2 && root.service && root.service.query !== "" && root.lastError === ""
        textFormat: Text.PlainText
        text: "Nothing matched that name."
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }

      PanelSeparator { foreground: root.foreground }

      Text {
        textFormat: Text.PlainText
        text: root.shows.length === 0 ? "No shows yet" : (root.shows.length === 1 ? "1 show" : root.shows.length + " shows")
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }

      Text {
        visible: root.shows.length === 0
        width: parent.width
        textFormat: Text.PlainText
        text: "Search above, then pick the matching year and network so the list stays on the right Silo, not the other one."
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        wrapMode: Text.Wrap
      }

      Repeater {
        model: root.shows

        Rectangle {
          required property var modelData
          width: parent.width
          height: showRow.implicitHeight + Style.space(10)
          radius: Style.cornerRadius
          color: showMouse.containsMouse ? Style.hoverFillFor(root.foreground, root.accent) : "transparent"

          Row {
            id: showRow
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Style.space(6)
            anchors.rightMargin: Style.space(6)
            spacing: Style.space(8)

            Column {
              width: parent.width - removeLabel.width - Style.space(8)
              spacing: Style.space(1)

              Text {
                width: parent.width
                textFormat: Text.PlainText
                text: modelData.name
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                elide: Text.ElideRight
              }

              Text {
                width: parent.width
                textFormat: Text.PlainText
                text: Model.showSubtitle(modelData, Date.now())
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                elide: Text.ElideRight
              }
            }

            Text {
              id: removeLabel
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: "Remove"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
          }

          MouseArea {
            id: showMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: if (root.service) root.service.removeShow(modelData.id)
          }
        }
      }
    }
    }
  }
}
