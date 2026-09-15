import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Chezmoi Hound - a count of dotfile drift that hunts it down.
//
// The number is three things added up:
//
//   home      targets this machine has edited and the source has not captured
//   repo      paths the source repo's own working tree is holding uncommitted
//   unpushed  commits in the source repo the remote has not seen
//
// Nothing is counted here. bin/chezmoi-hound-check does that and answers in a
// line protocol this file parses; the panel's two buttons run
// bin/chezmoi-hound-act. Both are the plugin's own scripts, so the widget needs
// no jq, no cache file, no systemd timer and no ~/.local/bin of its own - it
// re-asks on its own clock and after every action.
//
// Clicking the count opens the panel: it names the drifting items and offers
// the two things a count of drift makes you want to do (push what the remote
// has not seen, capture and commit what this machine has edited). The badge
// itself is only ever a number, and it is silent when everything agrees, because
// a permanent zero is noise.
Panel {
  id: root
  moduleName: "io.github.dadofsambonzuki.chezmoi-hound"
  ipcTarget: "io.github.dadofsambonzuki.chezmoi-hound"
  // manageIpc: false because this file owns the single IpcHandler the target
  // allows, so it can answer status()/geometry() as well as open/close.
  manageIpc: false

  // ---- the plugin's own scripts -------------------------------------------
  // Resolved from this file, not from $HOME: the widget is meant to work from
  // wherever it was installed.
  readonly property string checkScript: Qt.resolvedUrl("bin/chezmoi-hound-check").toString().replace(/^file:\/\//, "")
  readonly property string actScript: Qt.resolvedUrl("bin/chezmoi-hound-act").toString().replace(/^file:\/\//, "")

  // ---- settings -----------------------------------------------------------
  // Settings arrive from the shell and are treated as input like everything
  // else: the source is a path that gets handed to a command, so it is trimmed
  // and the interval is clamped rather than trusted.
  readonly property string source: String(setting("source", "")).trim()
  readonly property int checkSeconds: {
    var n = Number(setting("checkSeconds", 300))
    if (!isFinite(n) || n < 60) n = 300
    if (n > 3600) n = 3600
    return Math.floor(n)
  }
  readonly property bool showWhenClean: String(setting("whenClean", "Hide")) === "Show"

  // The plugin's own reading, and the last one that parsed: a failed run leaves
  // the previous numbers on screen rather than emptying the badge.
  property int homeCount: 0
  property int repoCount: 0
  property int unpushed: 0
  property int total: 0
  property var detail: []
  property var commits: []
  property var repoDetail: []
  property var notes: []
  property string stamp: ""
  property string branch: ""
  property string upstream: ""
  property string srcDir: ""
  property string error: ""
  property bool everLoaded: false

  readonly property int maxBytes: 32768

  // ---- action state -------------------------------------------------------
  // Which action is in flight ("" when idle). While one runs the buttons are
  // inert: two commits racing over the same index, or a commit and a push
  // interleaving, is how a half-captured tree gets committed.
  property string running: ""
  property var logLines: []

  function bounded(value, high) {
    return (typeof value === "number" && isFinite(value) && value >= 0 && value <= high)
      ? Math.floor(value)
      : 0
  }

  // bar.showTooltip renders with AutoText, which this plugin cannot pin to
  // PlainText, so markup and control characters are stripped before handoff.
  function plain(value) {
    return String(value)
      .replace(/[<>&]/g, "")
      .replace(/[\u0000-\u001f\u007f-\u009f\u200e\u200f\u202a-\u202e\u2066-\u2069]/g, "")
      .substring(0, 200)
  }

  function countOf(value) {
    var n = Number(value)
    return (isFinite(n) && n >= 0 && n <= 100000) ? Math.floor(n) : -1
  }

  // The line protocol: one "key<TAB>value" record per line, in any order. A
  // reading is only accepted when all four counts arrived and agree with each
  // other, so a half-written or truncated run cannot move the badge.
  function applyReading(raw) {
    var text = String(raw || "")
    if (text.length > maxBytes) return false

    var lines = text.split("\n")
    var home = -1
    var repo = -1
    var unpushed = -1
    var total = -1
    var files = []
    var commitsOut = []
    var repoFiles = []
    var notesOut = []
    var src = ""
    var failed = ""

    for (var i = 0; i < lines.length; i++) {
      var line = lines[i]
      if (line === "") continue
      var tab = line.indexOf("\t")
      var key = tab < 0 ? line : line.substring(0, tab)
      var value = tab < 0 ? "" : line.substring(tab + 1)

      if (key === "home") home = countOf(value)
      else if (key === "repo") repo = countOf(value)
      else if (key === "unpushed") unpushed = countOf(value)
      else if (key === "total") total = countOf(value)
      else if (key === "file") { if (files.length < 10) files.push(plain(value)) }
      else if (key === "commit") { if (commitsOut.length < 10) commitsOut.push(plain(value)) }
      else if (key === "repofile") { if (repoFiles.length < 10) repoFiles.push(plain(value)) }
      else if (key === "note") notesOut.push(plain(value))
      else if (key === "error") failed = plain(value)
      else if (key === "source") src = plain(value)
      else if (key === "branch") branch = plain(value)
      else if (key === "upstream") upstream = plain(value)
      else if (key === "stamp") stamp = plain(value)
    }

    if (failed !== "") {
      root.error = failed
      return false
    }
    if (home < 0 || repo < 0 || unpushed < 0 || total < 0) return false
    if (home + repo + unpushed !== total) return false

    root.homeCount = home
    root.repoCount = repo
    root.unpushed = unpushed
    root.total = total
    root.detail = files
    root.commits = commitsOut
    root.repoDetail = repoFiles
    root.notes = notesOut
    root.srcDir = src
    root.everLoaded = true
    root.error = ""
    return true
  }

  function plural(count, noun) {
    return count + " " + noun + (count === 1 ? "" : "s")
  }

  function countText() {
    return String(root.total)
  }

  function tooltip() {
    if (root.error !== "") return "Chezmoi Hound: " + root.error

    if (root.total === 0) {
      return root.everLoaded
        ? "Dotfiles in sync" + (root.stamp ? "  ·  checked " + root.stamp : "")
        : "No reading yet"
    }

    var parts = []
    if (root.homeCount > 0) parts.push(root.homeCount + " changed in $HOME")
    if (root.repoCount > 0) parts.push(root.repoCount + " uncommitted")
    if (root.unpushed > 0) parts.push(root.unpushed + " unpushed")
    var out = "Dotfiles out of sync: " + parts.join("  ·  ")

    if (root.detail.length > 0) {
      out += "\n" + root.detail.join("\n")
      if (root.homeCount > root.detail.length) out += "\n…"
    }
    if (root.stamp) out += "\nchecked " + root.stamp
    out += "\nclick: push / commit what is drifting"
    return out
  }

  function heroPhrase() {
    if (root.running !== "") return root.running === "push" ? "pushing…" : "capturing and committing…"
    if (root.error !== "") return "Could not read the source"
    if (root.total === 0) return root.everLoaded ? "In sync" : "No reading yet"
    var parts = []
    if (root.homeCount > 0) parts.push(root.plural(root.homeCount, "edit") + " not captured")
    if (root.repoCount > 0) parts.push(root.plural(root.repoCount, "repo change") + " uncommitted")
    if (root.unpushed > 0) parts.push(root.plural(root.unpushed, "commit") + " not pushed")
    return parts.join("  ·  ")
  }

  function repoPhrase() {
    var where = root.srcDir !== "" ? root.srcDir : root.source
    var line = where !== "" ? where : "chezmoi's own source"
    if (root.branch !== "") line += "  ·  " + root.branch + (root.upstream !== "" ? " -> " + root.upstream : " (no upstream)")
    line += "\nClick to act  ·  middle-click re-checks  ·  right-click for details"
    if (root.stamp !== "") line += "\nchecked " + root.stamp
    return line
  }

  // ---- running the scripts ------------------------------------------------

  // --source is only passed when the setting names one: without it chezmoi
  // answers for the source it is configured for, which is the common case.
  function checkCommand() {
    var c = ["/usr/bin/timeout", "-k", "2", "60", root.checkScript]
    if (root.source !== "") c.push("--source", root.source)
    return c
  }

  function detailCommand() {
    var c = ["/usr/bin/omarchy-launch-floating-terminal-with-presentation", root.checkScript, "--render"]
    if (root.source !== "") c.push("--source", root.source)
    return c
  }

  function actionCommand(what) {
    var c = ["/usr/bin/timeout", "-k", "2", "180", root.actScript, what === "push" ? "push" : "commit"]
    if (root.source !== "") c.push("--source", root.source)
    return c
  }

  function refresh() {
    if (checkProc.running) return
    checkProc.command = root.checkCommand()
    checkProc.running = true
  }

  function runAction(what) {
    if (actionProc.running || root.running !== "") return
    root.logLines = []
    root.running = what === "push" ? "push" : "commit"
    actionProc.command = root.actionCommand(what)
    actionProc.running = true
  }

  function addLog(line) {
    var text = String(line)
    if (text.trim() === "") return
    var next = root.logLines.slice()
    next.push(root.plain(text))
    // Bounded: this is a panel, not a scrollback.
    if (next.length > 12) next = next.slice(next.length - 12)
    root.logLines = next
  }

  visible: root.total > 0 || root.showWhenClean
  implicitWidth: vertical ? barSize : (badge.width + Style.spaceReal(6))
  implicitHeight: vertical ? (badge.height + Style.spaceReal(6)) : barSize

  // The clock. triggerOnStart means the first reading happens when the shell
  // loads the widget rather than one interval later.
  Timer {
    id: poll
    interval: Math.max(60, root.checkSeconds) * 1000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Process {
    id: checkProc
    stdout: StdioCollector {
      id: checkOut
      waitForEnd: true
    }
    stderr: StdioCollector {
      id: checkErr
      waitForEnd: true
    }
    onExited: function (code, status) {
      var accepted = root.applyReading(checkOut.text)
      if (!accepted && root.error === "") {
        var e = String(checkErr.text || "").trim()
        root.error = e !== ""
          ? root.plain(e.split("\n")[0])
          : "chezmoi-hound-check exited " + code + " without a reading"
      }
    }
  }

  Process {
    id: detailProc
    command: root.detailCommand()
  }

  Process {
    id: actionProc
    stdout: SplitParser {
      onRead: function (line) { root.addLog(line) }
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: { root.addLog(String(text || "")) }
    }
    onExited: function (exitCode, exitStatus) {
      root.running = ""
      // The scripts count for their own log; re-reading is what makes the badge
      // and this panel show the new numbers the moment the action finishes.
      root.refresh()
    }
  }

  Row {
    id: badge
    anchors.centerIn: parent
    opacity: root.total > 0 ? 1 : 0.5

    // Just the count. A Nerd Font glyph used to sit to its left; it was dropped
    // because the codepoint it used draws a barcode in this font, not a git
    // icon, and a bare number is clearer than a number with a puzzle next to it.
    Text {
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: root.countText()
      color: root.total > 0 ? Color.foreground : Color.muted
      font.family: root.bar ? root.bar.fontFamily : Style.font.family
      font.pixelSize: Math.max(9, Math.round(root.barSize * 0.5))
      renderType: Text.NativeRendering
    }
  }

  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor

    // Left opens the panel, which both lists the drift and offers the two
    // actions. Middle re-asks now rather than waiting for the timer. Right keeps
    // the floating terminal, for the full text that can be copied out of.
    onClicked: function (mouse) {
      if (root.bar) root.bar.hideTooltip(root)
      if (mouse.button === Qt.LeftButton) {
        root.toggle()
      } else if (mouse.button === Qt.MiddleButton) {
        root.refresh()
      } else {
        if (!detailProc.running) detailProc.running = true
      }
    }
    onEntered: if (root.bar && !root.opened) root.bar.showTooltip(root, root.tooltip())
    onExited: if (root.bar) root.bar.hideTooltip(root)
  }

  // The panel: the shape of the drift, then the buttons that act on it, then
  // the log of the last action.
  KeyboardPanel {
    id: panel
    anchorItem: badge
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(440))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(12)

        PanelHero {
          width: parent.width
          title: "Chezmoi Hound"
          meta: root.heroPhrase()
          detail: root.repoPhrase()
          foreground: root.bar.foreground
          fontFamily: root.bar.fontFamily
          iconOpacity: root.total > 0 ? 1.0 : 0.5
        }

        // ---- what the remote has not seen ----
        Column {
          width: parent.width
          spacing: Style.space(8)
          visible: root.unpushed > 0

          PanelSectionHeader {
            text: "NOT PUSHED — " + root.plural(root.unpushed, "commit")
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
          }

          Repeater {
            model: root.commits
            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: "  " + modelData
              color: root.bar.foreground
              opacity: 0.75
              elide: Text.ElideRight
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
          }

          Button {
            text: root.running === "push" ? "Pushing…" : "Push " + root.plural(root.unpushed, "commit")
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            fontSize: Style.font.bodySmall
            horizontalPadding: Style.spacing.controlPaddingX
            verticalPadding: Style.spacing.controlPaddingY
            bordered: true
            opacity: root.running === "" ? 1 : 0.45
            onClicked: root.runAction("push")
          }
        }

        PanelSeparator {
          visible: root.unpushed > 0 && (root.homeCount > 0 || root.repoCount > 0)
          foreground: root.bar.foreground
        }

        // ---- edits made on this machine that the source has not got ----
        Column {
          width: parent.width
          spacing: Style.space(8)
          visible: root.homeCount > 0

          PanelSectionHeader {
            text: "EDITED HERE, NOT CAPTURED — " + root.plural(root.homeCount, "file")
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
          }

          Repeater {
            model: root.detail
            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: "  " + modelData
              color: root.bar.foreground
              opacity: 0.75
              elide: Text.ElideLeft
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
          }

          Button {
            text: root.running === "commit" ? "Committing…" : "Capture and commit " + root.plural(root.homeCount, "change")
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            fontSize: Style.font.bodySmall
            horizontalPadding: Style.spacing.controlPaddingX
            verticalPadding: Style.spacing.controlPaddingY
            bordered: true
            opacity: root.running === "" ? 1 : 0.45
            onClicked: root.runAction("commit")
          }
        }

        PanelSeparator {
          visible: root.homeCount > 0 && root.repoCount > 0
          foreground: root.bar.foreground
        }

        // ---- the source repo's own working tree ----
        Column {
          width: parent.width
          spacing: Style.space(8)
          visible: root.repoCount > 0

          PanelSectionHeader {
            text: "UNCOMMITTED IN THE SOURCE — " + root.plural(root.repoCount, "path")
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
          }

          Repeater {
            model: root.repoDetail
            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: "  " + modelData
              color: root.bar.foreground
              opacity: 0.75
              elide: Text.ElideLeft
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
          }

          Button {
            text: root.running === "commit" ? "Committing…" : "Commit " + root.plural(root.repoCount, "repo change")
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            fontSize: Style.font.bodySmall
            horizontalPadding: Style.spacing.controlPaddingX
            verticalPadding: Style.spacing.controlPaddingY
            bordered: true
            opacity: root.running === "" ? 1 : 0.45
            onClicked: root.runAction("commit")
          }
        }

        Text {
          width: parent.width
          visible: root.total === 0 && root.error === ""
          textFormat: Text.PlainText
          text: root.everLoaded
            ? "$HOME, the source and the remote all agree. Nothing to do."
            : "No reading yet."
          color: root.bar.foreground
          opacity: 0.7
          wrapMode: Text.WordWrap
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.bodySmall
        }

        // A reading that failed is said out loud, with the source it failed on:
        // a badge stuck on a stale number is worse than one that admits it.
        Text {
          width: parent.width
          visible: root.error !== ""
          textFormat: Text.PlainText
          text: root.error
          color: root.bar.foreground
          opacity: 0.85
          wrapMode: Text.WordWrap
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.bodySmall
        }

        Repeater {
          model: root.notes
          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: modelData
            color: root.bar.foreground
            opacity: 0.6
            wrapMode: Text.WordWrap
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
        }

        // ---- what the last action did ----
        Column {
          width: parent.width
          spacing: Style.space(4)
          visible: root.logLines.length > 0

          PanelSectionHeader {
            text: "LAST ACTION"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
          }

          Repeater {
            model: root.logLines
            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: "  " + modelData
              color: root.bar.foreground
              opacity: 0.8
              elide: Text.ElideRight
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
          }
        }

        PanelSeparator {
          foreground: root.bar.foreground
        }

        Row {
          width: parent.width
          spacing: Style.space(8)

          Button {
            text: "Re-check now"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            fontSize: Style.font.bodySmall
            horizontalPadding: Style.spacing.controlPaddingX
            verticalPadding: Style.spacing.controlPaddingY
            bordered: true
            onClicked: root.refresh()
          }

          Button {
            text: "Full details"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            fontSize: Style.font.bodySmall
            horizontalPadding: Style.spacing.controlPaddingX
            verticalPadding: Style.spacing.controlPaddingY
            bordered: true
            onClicked: if (!detailProc.running) detailProc.running = true
          }
        }
      }
    }
  }

  // Proves what the badge is actually showing, without reading pixels off the
  // screen: `omarchy-shell io.github.dadofsambonzuki.chezmoi-hound status`.
  IpcHandler {
    target: "io.github.dadofsambonzuki.chezmoi-hound"

    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }

    function status(): string {
      return "total=" + root.total + " home=" + root.homeCount + " repo=" + root.repoCount
        + " unpushed=" + root.unpushed + " visible=" + root.visible
        + " source=" + (root.srcDir !== "" ? root.srcDir : "(chezmoi default)")
        + " branch=" + root.branch
        + " loaded=" + root.everLoaded
        + " error=" + (root.error === "" ? "none" : root.error)
        + " text=" + root.countText() + " badgeW=" + Math.round(badge.width)
    }

    // Where the widget actually is on screen, so its rendering can be checked
    // without hunting the bar pixel by pixel.
    function geometry(): string {
      var p = root.mapToItem(null, 0, 0)
      return "x=" + Math.round(p.x) + " y=" + Math.round(p.y)
        + " w=" + Math.round(root.width) + " h=" + Math.round(root.height)
    }

    // The panel's own view of itself, and the same two entry points the buttons
    // call - so the actions can be exercised without a synthetic click.
    function panel(): string {
      return "opened=" + root.opened + " running=" + (root.running === "" ? "idle" : root.running)
        + " commits=" + root.commits.length + " detail=" + root.detail.length
        + " repoDetail=" + root.repoDetail.length + " log=" + root.logLines.length
        + " notes=" + root.notes.length
        + " canPush=" + (root.unpushed > 0) + " canCommit=" + (root.homeCount + root.repoCount > 0)
        + " query=" + panel.fittedContentWidth(Style.space(440))
        + "x" + panel.fittedContentHeight(column.implicitHeight)
    }

    function commit(): void { root.runAction("commit") }
    function push(): void { root.runAction("push") }
    function refresh(): void { root.refresh() }
  }

  // Keep bar drag-to-reorder working, the way WidgetButton does.
  property var registeredBar: null
  function syncClickRegistration() {
    if (registeredBar && registeredBar.unregisterClickTarget) registeredBar.unregisterClickTarget(root)
    registeredBar = root.bar
    if (registeredBar && registeredBar.registerClickTarget) registeredBar.registerClickTarget(root)
  }
  onBarChanged: syncClickRegistration()
  Component.onCompleted: syncClickRegistration()
  Component.onDestruction: {
    if (registeredBar && registeredBar.unregisterClickTarget) registeredBar.unregisterClickTarget(root)
    detailProc.signal(15)
    checkProc.signal(15)
    actionProc.signal(15)
  }
}
