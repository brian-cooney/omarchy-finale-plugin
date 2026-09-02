import QtQuick
import qs.Commons
import qs.Ui

// Bar label for Finale Outdoor Region MTB trail status, and the host for the
// detail panel. The panel (Panel.qml) owns the fetch loop and computes the
// label / colour / tooltip; this widget just paints them and routes clicks.
//
// Left click toggles the panel, middle click forces a refresh, right click
// sends the summary as a notification.
BarWidget {
  id: root
  moduleName: "com.github.brian-cooney.finale-mtb"

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  function refresh() {
    if (panelLoader.item && panelLoader.item.refresh) panelLoader.item.refresh()
  }

  function togglePanel() {
    if (panelLoader.item && panelLoader.item.toggle) panelLoader.item.toggle()
  }

  // ---- Shape contract for shell.summon/hide/toggle routing. Bar.findPanelWidget
  //      requires opened/open/close on the bar-widget root; the popout
  //      coordinator also reads popoutSwitchClosing / closeForPopoutSwitch.
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function open() {
    if (panelLoader.item && panelLoader.item.openFromHotkey) panelLoader.item.openFromHotkey()
  }

  function close() {
    if (panelLoader.item && panelLoader.item.close) panelLoader.item.close()
  }

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  // Hidden until the panel has a label to show (first fetch in flight), the
  // same "nothing to say yet" treatment the weather widget uses.
  visible: panelLoader.item && panelLoader.item.label !== ""
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

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: panelLoader.item ? panelLoader.item.label : ""
    // Same colour as every other bar icon (WidgetButton's default is
    // bar.barForeground). State is conveyed by the token and the panel, not
    // by tinting the bar label — a muted/urgent icon here just reads as an
    // odd-one-out next to the other widgets.
    horizontalMargin: 8.75
    verticalPadding: 8.75
    tooltipText: panelLoader.item ? panelLoader.item.tooltipText : ""

    onPressed: function(b) {
      if (!root.bar) { root.togglePanel(); return }
      if (b === Qt.RightButton) {
        if (panelLoader.item)
          root.bar.run("omarchy-notification-send " + Util.shellQuote(panelLoader.item.notificationText))
      } else if (b === Qt.MiddleButton) {
        root.refresh()
      } else {
        root.togglePanel()
      }
    }
  }
}
