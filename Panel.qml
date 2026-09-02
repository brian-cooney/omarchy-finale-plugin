pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Finale Outdoor Region MTB trail status: a bar label plus a detail popup,
// from one entry point (BarWidget.qml owns the bar slot and hands this panel
// the button to anchor against).
//
// The data is a small status.json produced by a scraper of
// finaleoutdoor.com/en/live/bike (see the finale-mtb-status repo). This panel
// curls it on a timer, keeps the last good copy on failure, and flags the
// reading as stale once the feed's `checked_at` ages past `staleAfterMinutes`.
Panel {
  id: root
  moduleName: "com.github.brian-cooney.finale-mtb"
  ipcTarget: "com.github.brian-cooney.finale-mtb"
  manageIpc: false

  property var anchorItem: null
  property bool openedFromHotkey: false

  // The bar tracks the widget in its slot (BarWidget.qml), not this nested
  // panel, so anything the bar identifies a panel by has to be that widget.
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  // ---- Configuration (per-widget shell.json entry) -----------------------
  readonly property string jsonUrl: setting("jsonUrl",
    "https://brian-cooney.github.io/finale-mtb-status/data/status.json")
  readonly property int refreshMinutes: Math.max(5, parseInt(setting("refreshMinutes", 30), 10) || 30)
  readonly property int staleAfterMinutes: Math.max(60, parseInt(setting("staleAfterMinutes", 720), 10) || 720)
  // nf-fa-bicycle. Override with "" for a text-only label.
  readonly property string glyph: setting("glyph", "")
  readonly property string sourcePage: "https://www.finaleoutdoor.com/en/live/bike"

  // ---- State ------------------------------------------------------------
  property var status: null          // parsed status.json, or null
  property bool everLoaded: false     // a fetch has completed at least once
  property int fetchRetries: 0
  property date nowTick: new Date()   // ticked each minute for age/stale math

  readonly property string displayState: everLoaded || status
    ? Model.displayState(status, nowTick, staleAfterMinutes)
    : ""
  readonly property string label: displayState === ""
    ? ""
    : Model.barLabel(status, displayState, glyph)
  readonly property color barColor: Model.stateColor(displayState, {
    foreground: root.barForeground,
    urgent: Color.urgent,
    muted: Color.muted
  })
  readonly property string summary: Model.summaryLine(status, displayState)
  readonly property string checkedAgo: status && status.checkedAt
    ? Model.relativeTime(status.checkedAt, nowTick) : ""
  readonly property string tooltipText: summary
    + (checkedAgo ? "  ·  checked " + checkedAgo : "")
  readonly property string notificationText: {
    var lines = ["Finale MTB — " + summary]
    var groups = Model.groupByArea(status ? status.closedTrails : [])
    for (var i = 0; i < groups.length; i++) {
      var names = groups[i].trails.map(function (t) {
        return t.trail + (t.note ? " (" + t.note + ")" : "")
      })
      lines.push(groups[i].area + ": " + names.join(", "))
    }
    return lines.join("\n")
  }
  readonly property var areaGroups: Model.groupByArea(status ? status.closedTrails : [])

  // ---- Lifecycle ------------------------------------------------------
  function open() {
    openedFromHotkey = false
    setCenterHoverRevealSuppressed(false)
    root.controller.show()
    root.refresh()
  }

  function openFromHotkey() {
    openedFromHotkey = true
    root.controller.show()
    root.refresh()
    Qt.callLater(function () {
      if (root.opened) setCenterHoverRevealSuppressed(true)
    })
  }

  function close() {
    setCenterHoverRevealSuppressed(false)
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.openFromHotkey()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function setCenterHoverRevealSuppressed(value) {
    if (root.bar && "centerHoverRevealSuppressed" in root.bar)
      root.bar.centerHoverRevealSuppressed = value
  }

  // ---- Fetch ---------------------------------------------------------
  function refresh() {
    fetchRetries = 0
    if (!fetchProc.running) fetchProc.running = true
  }

  function scheduleRetry() {
    if (fetchRetries >= 3) return
    fetchRetries++
    retryTimer.restart()
  }

  Process {
    id: fetchProc
    command: ["curl", "-fsS", "--max-time", "10", root.jsonUrl]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var raw = String(text || "").trim()
        var parsed = raw ? Model.parseStatus(raw) : null
        if (parsed) {
          root.status = parsed
          root.fetchRetries = 0
        } else {
          // Keep the last good status visible; try again shortly.
          root.scheduleRetry()
        }
        root.everLoaded = true
      }
    }
    // qmllint disable signal-handler-parameters
    // (Quickshell's Process.exited passes a QProcess::ExitStatus that qmllint
    //  can't resolve; the handler only reads exitCode.)
    onExited: function (exitCode) {
      if (exitCode !== 0) {
        root.everLoaded = true
        root.scheduleRetry()
      }
    }
  }

  Timer {
    id: retryTimer
    interval: 4000
    onTriggered: if (!fetchProc.running) fetchProc.running = true
  }

  Timer {
    id: refreshTimer
    interval: root.refreshMinutes * 60 * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Timer {
    id: clockTimer
    interval: 60 * 1000
    running: true
    repeat: true
    onTriggered: root.nowTick = new Date()
  }

  IpcHandler {
    target: root.ipcTarget

    function open(): void { root.openFromHotkey() }
    function close(): void { root.close() }
    function show(): void { root.openFromHotkey() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): void { root.refresh() }
  }

  // ---- UI ----------------------------------------------------------
  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: true
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(460))
    contentHeight: panel.fittedContentHeight(content.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function (direction) { root.switchPanel(direction) }
      onTextKey: function (t) { if (t === "r" || t === "R") root.refresh() }

      Flickable {
        id: scroll
        anchors.fill: parent
        contentWidth: width
        contentHeight: content.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        Column {
          id: content
          width: scroll.width
          spacing: Style.space(14)

          // ---- Header: state dot + summary, with the reference date and
          //      the fetch age underneath.
          Row {
            width: content.width
            spacing: Style.space(12)

            Rectangle {
              width: Style.space(10)
              height: Style.space(10)
              radius: width / 2
              anchors.verticalCenter: parent.verticalCenter
              color: root.barColor
            }

            Column {
              width: content.width - Style.space(10) - Style.space(12)
              spacing: Style.space(3)

              Text {
                width: parent.width
                text: root.summary
                color: root.barForeground
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.title
                font.bold: true
                elide: Text.ElideRight
              }

              Text {
                width: parent.width
                visible: text !== ""
                text: {
                  var bits = []
                  if (root.status && root.status.asOfDate) bits.push("as of " + root.status.asOfDate)
                  if (root.checkedAgo) bits.push("checked " + root.checkedAgo)
                  return bits.join("  ·  ")
                }
                color: Qt.darker(root.barForeground, 1.5)
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.bodySmall
              }

              Text {
                width: parent.width
                visible: root.displayState === "stale"
                text: "The source has not updated recently — treat this as a guide only."
                color: Color.urgent
                wrapMode: Text.WordWrap
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.bodySmall
              }
            }
          }

          Rectangle {
            width: parent.width
            height: Style.spacing.hairline
            color: root.barForeground
            opacity: 0.12
          }

          // ---- Closed trails, grouped by area.
          Column {
            width: parent.width
            spacing: Style.space(10)
            visible: root.areaGroups.length > 0

            Repeater {
              model: root.areaGroups

              Column {
                id: areaGroup
                required property var modelData
                width: content.width
                spacing: Style.space(4)

                Text {
                  text: areaGroup.modelData.area
                  color: Qt.darker(root.barForeground, 1.4)
                  font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  font.pixelSize: Style.font.caption
                  font.letterSpacing: 1
                  font.bold: true
                }

                Repeater {
                  model: areaGroup.modelData.trails

                  Row {
                    id: trailRow
                    required property var modelData
                    width: content.width
                    spacing: Style.space(8)

                    Text {
                      text: "✗"
                      color: Color.urgent
                      font.family: root.bar ? root.bar.fontFamily : Style.font.family
                      font.pixelSize: Style.font.body
                    }

                    Text {
                      text: trailRow.modelData.trail
                      color: root.barForeground
                      font.family: root.bar ? root.bar.fontFamily : Style.font.family
                      font.pixelSize: Style.font.body
                    }

                    Text {
                      visible: trailRow.modelData.note !== ""
                      text: "(" + trailRow.modelData.note + ")"
                      color: Qt.darker(root.barForeground, 1.5)
                      font.family: root.bar ? root.bar.fontFamily : Style.font.family
                      font.pixelSize: Style.font.bodySmall
                      anchors.verticalCenter: parent.verticalCenter
                    }
                  }
                }
              }
            }
          }

          Text {
            width: parent.width
            visible: root.displayState === "open"
            text: "No closures reported. Ride on."
            color: Qt.darker(root.barForeground, 1.4)
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.body
          }

          Text {
            width: parent.width
            visible: !root.everLoaded
            text: "Loading trail status…"
            color: Qt.darker(root.barForeground, 1.5)
            font.italic: true
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.bodySmall
          }

          // ---- Latest notices, verbatim from the source page.
          Column {
            width: parent.width
            spacing: Style.space(10)
            visible: root.status && root.status.notices && root.status.notices.length > 0

            Rectangle {
              width: parent.width
              height: Style.spacing.hairline
              color: root.barForeground
              opacity: 0.12
            }

            Text {
              text: "LATEST NOTICES"
              color: Qt.darker(root.barForeground, 1.5)
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.caption
              font.letterSpacing: 1
              font.bold: true
            }

            Repeater {
              model: root.status ? root.status.notices : []

              Column {
                id: notice
                required property var modelData
                width: content.width
                spacing: Style.space(3)

                Text {
                  width: parent.width
                  visible: text !== ""
                  text: (notice.modelData.date ? notice.modelData.date + " — " : "") + (notice.modelData.title || "")
                  color: root.barForeground
                  wrapMode: Text.WordWrap
                  font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  font.pixelSize: Style.font.bodySmall
                  font.bold: true
                }

                Text {
                  width: parent.width
                  visible: text !== ""
                  text: Model.noticeParagraphs(notice.modelData.text).join("\n")
                  color: Qt.darker(root.barForeground, 1.3)
                  wrapMode: Text.WordWrap
                  font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  font.pixelSize: Style.font.bodySmall
                }
              }
            }
          }

          // ---- Footer: open the official page, and a hint for the refresh key.
          Row {
            width: parent.width
            spacing: Style.space(10)

            Text {
              text: "Open finaleoutdoor.com"
              color: footerMouse.containsMouse
                ? Style.hoverStateColor(root.barForeground, Color.accent)
                : Style.normalStateColor(root.barForeground, Color.accent)
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.bodySmall
              font.underline: footerMouse.containsMouse

              MouseArea {
                id: footerMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  if (root.bar) root.bar.run("xdg-open " + Util.shellQuote(root.sourcePage))
                  else Qt.openUrlExternally(root.sourcePage)
                }
              }
            }

            Item { width: Style.space(1); height: 1 }

            Text {
              text: "press R to refresh"
              color: Qt.darker(root.barForeground, 1.8)
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.caption
            }
          }
        }
      }
    }
  }
}
