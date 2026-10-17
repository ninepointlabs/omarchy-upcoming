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

  property bool showAbout: false
  property bool showLicense: false
  property bool showNotices: false
  property string copiedLabel: ""

  // About page facts read from this plugin's own files, only once it is shown.
  readonly property string pluginDir: {
    var text = String(Qt.resolvedUrl("."))
    if (text.indexOf("file://") === 0) text = decodeURIComponent(text.substring(7))
    return text.length > 1 && text.charAt(text.length - 1) === "/" ? text.substring(0, text.length - 1) : text
  }
  readonly property string version: Model.manifestVersion(manifestFile.loaded ? manifestFile.text() : "")
  readonly property string quickshellVersion: Model.probedVersion(function(a, b) { return Quickshell.hasVersion(a, b) }, 0)
  readonly property string qtVersion: Model.probedVersion(function(a, b) { return Quickshell.hasQtVersion(a, b) }, 6)
  readonly property string pythonVersion: service ? service.pythonVersion : ""
  readonly property string aboutDetails: Model.aboutDetails(root.version, root.quickshellVersion, root.qtVersion,
    root.pythonVersion, Qt.platform.os + ", " + Qt.platform.pluginName)

  FileView { id: manifestFile; path: root.showAbout ? root.pluginDir + "/manifest.json" : "" }
  FileView { id: licenseFile; path: root.showLicense ? root.pluginDir + "/LICENSE" : "" }
  FileView { id: noticesFile; path: root.showNotices ? root.pluginDir + "/THIRD_PARTY_NOTICES.md" : "" }

  function showAboutPage() {
    showLicense = false
    showNotices = false
    showAbout = true
    panelFlick.contentY = 0
    keyCatcher.forceActiveFocus()
  }

  function hideAboutPage() {
    showAbout = false
    panelFlick.contentY = 0
    if (opened) searchField.forceActiveFocus()
  }

  function copyText(text, label) {
    Quickshell.clipboardText = text
    copiedLabel = label
    copiedTimer.restart()
  }

  Timer { id: copiedTimer; interval: 1500; onTriggered: root.copiedLabel = "" }

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
    if (!opened) { showAbout = false; return }
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

  component Caption: Text {
    textFormat: Text.PlainText
    color: root.dim
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
  }

  component Detail: Text {
    width: parent ? parent.width : 0
    textFormat: Text.PlainText
    color: root.dim
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
    wrapMode: Text.Wrap
  }

  component Body: Text {
    textFormat: Text.PlainText
    color: root.foreground
    font.family: root.fontFamily
    font.pixelSize: Style.font.body
    wrapMode: Text.Wrap
  }

  component AboutLabel: Caption {
    width: Style.space(84)
  }

  component AboutLink: Text {
    signal activated()
    textFormat: Text.PlainText
    color: root.accent
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall

    MouseArea {
      anchors.fill: parent
      anchors.margins: -Style.space(4)
      cursorShape: Qt.PointingHandCursor
      onClicked: parent.activated()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: true
    focusTarget: searchField
    contentWidth: panel.fittedContentWidth(Style.space(420))
    contentHeight: panel.fittedContentHeight(panelFlick.contentHeight + Style.space(24), Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: searchField.activeFocus && !root.showAbout
      // Esc steps back out of About before it closes the panel.
      onCloseRequested: root.showAbout ? root.hideAboutPage() : root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

    Flickable {
      id: panelFlick
      anchors.fill: parent
      contentWidth: width
      contentHeight: root.showAbout ? aboutColumn.implicitHeight : mainColumn.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      flickableDirection: Flickable.VerticalFlick
      interactive: contentHeight > height
      ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

    Column {
      id: mainColumn
      visible: !root.showAbout
      width: panelFlick.width
      spacing: Style.space(10)

      Item {
        width: parent.width
        implicitHeight: Math.max(titleColumn.implicitHeight, refreshButton.implicitHeight)

        Column {
          id: titleColumn
          anchors.left: parent.left
          anchors.right: aboutButton.left
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
          id: aboutButton
          objectName: "aboutButton"
          anchors.right: refreshButton.left
          anchors.rightMargin: Style.space(4)
          anchors.verticalCenter: parent.verticalCenter
          iconText: "󰋽"
          tooltipText: "About Upcoming"
          foreground: root.foreground
          fontFamily: root.fontFamily
          onClicked: root.showAboutPage()
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

    // --------------------------------------------------------- About --
    Column {
      id: aboutColumn
      objectName: "aboutColumn"
      visible: root.showAbout
      width: panelFlick.width
      spacing: Style.space(10)

      Item {
        width: parent.width
        implicitHeight: Math.max(aboutTitle.implicitHeight, backButton.implicitHeight)

        Row {
          id: aboutTitle
          anchors.left: parent.left
          anchors.right: backButton.left
          anchors.rightMargin: Style.space(8)
          spacing: Style.space(10)

          OpticalGlyph {
            width: Style.space(40)
            height: width
            anchors.verticalCenter: parent.verticalCenter
            text: "󰑈"
            fontFamily: root.fontFamily
            fontSize: Style.space(30)
            color: root.accent
          }

          Column {
            width: parent.width - Style.space(50)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              textFormat: Text.PlainText
              text: Model.ABOUT.name
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
            }
            Detail { text: Model.ABOUT.tagline }
            Caption { objectName: "aboutVersion"; text: "Version " + (root.version || "unknown") }
          }
        }

        PanelActionButton {
          id: backButton
          objectName: "aboutBack"
          anchors.right: parent.right
          anchors.top: parent.top
          iconText: "󰅖"
          tooltipText: "Back (Esc)"
          foreground: root.foreground
          fontFamily: root.fontFamily
          onClicked: root.hideAboutPage()
        }
      }

      PanelSeparator { foreground: root.foreground }

      Grid {
        id: aboutFacts
        width: parent.width
        columns: 2
        columnSpacing: Style.space(10)
        rowSpacing: Style.space(8)
        readonly property real valueWidth: width - Style.space(84) - columnSpacing

        AboutLabel { text: "MADE BY" }
        Body { width: aboutFacts.valueWidth; text: Model.ABOUT.organization }

        AboutLabel { text: "CREATED" }
        Body { width: aboutFacts.valueWidth; text: Model.ABOUT.created }

        AboutLabel { text: "LICENSE" }
        Column {
          width: aboutFacts.valueWidth
          spacing: Style.space(4)
          Body { width: parent.width; text: Model.ABOUT.license + ", " + Model.ABOUT.copyright }
          Row {
            spacing: Style.space(14)
            AboutLink {
              objectName: "aboutLicenseLink"
              text: root.showLicense ? "Hide license" : "Read license"
              onActivated: root.showLicense = !root.showLicense
            }
            AboutLink {
              objectName: "aboutNoticesLink"
              text: root.showNotices ? "Hide third-party notices" : "Third-party notices"
              onActivated: root.showNotices = !root.showNotices
            }
          }
        }

        AboutLabel { text: "DATA" }
        Column {
          width: aboutFacts.valueWidth
          spacing: Style.space(4)
          Detail { objectName: "aboutDataCredit"; color: root.foreground; text: Model.ABOUT.dataCredit }
          AboutLink {
            text: "tvmaze.com"
            onActivated: Qt.openUrlExternally(Model.ABOUT.dataUrl)
          }
        }

        AboutLabel { text: "SUPPORT" }
        Column {
          width: aboutFacts.valueWidth
          spacing: Style.space(4)
          Body { width: parent.width; text: Model.ABOUT.supportEmail }
          Flow {
            width: parent.width
            spacing: Style.space(6)
            Button {
              objectName: "aboutEmail"
              text: "Email"
              bordered: true
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              onClicked: Qt.openUrlExternally(Model.supportMailto(root.version, root.aboutDetails))
            }
            Button {
              objectName: "aboutCopyEmail"
              text: root.copiedLabel === "email" ? "Copied" : "Copy"
              bordered: true
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              onClicked: root.copyText(Model.ABOUT.supportEmail, "email")
            }
            Button {
              objectName: "aboutCopyDetails"
              text: root.copiedLabel === "details" ? "Copied" : "Copy version details"
              bordered: true
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              onClicked: root.copyText(root.aboutDetails, "details")
            }
          }
        }

        AboutLabel { text: "PRIVACY" }
        Detail { objectName: "aboutPrivacy"; width: aboutFacts.valueWidth; color: root.foreground; text: Model.PRIVACY }

        AboutLabel { text: "BUILT WITH" }
        Detail {
          objectName: "aboutBuiltWith"
          width: aboutFacts.valueWidth
          text: ["Quickshell " + (root.quickshellVersion || "?"), "Qt " + (root.qtVersion || "?"),
            "Python " + (root.pythonVersion || "?")].join(", ")
        }
      }

      Detail {
        objectName: "aboutLicenseText"
        visible: root.showLicense
        text: licenseFile.loaded ? Model.reflowLicense(licenseFile.text())
          : Model.ABOUT.license + ", " + Model.ABOUT.copyright
      }

      Detail {
        objectName: "aboutNoticesText"
        visible: root.showNotices
        text: noticesFile.loaded ? Model.reflowLicense(noticesFile.text()) : "See THIRD_PARTY_NOTICES.md in the plugin directory."
      }
    }
    }
    }
  }
}
