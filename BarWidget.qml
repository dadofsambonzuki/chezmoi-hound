import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Chezmoi Hound - a count of dotfile drift, and the two things it makes you
// want to do about it.
//
// The number is three parts added up: managed targets this machine has edited
// and the source has not captured, paths the source repo's own working tree is
// holding uncommitted, and commits the remote has not seen. The badge is silent
// while everything is in sync - a permanent zero is noise.
//
// Neither the counting nor the git work happens in QML. bin/chezmoi-hound-check
// is polled on a timer and answers in a line protocol, and the panel's two
// buttons run bin/chezmoi-hound-act. Both ship next to this file, so the plugin
// depends on chezmoi and git and on nothing else the author happens to have
// installed; the widget itself never shells out to git.
Panel {
  id: root
  moduleName: "io.github.dadofsambonzuki.chezmoi-hound"
  ipcTarget: "io.github.dadofsambonzuki.chezmoi-hound"
  // manageIpc: false because this file owns the single IpcHandler the target
  // allows, so it can answer status()/geometry() as well as open/close.
  manageIpc: false

  // ---- bar geometry -------------------------------------------------------
  // A popup widget is a Panel, which carries no bar geometry of its own, so the
  // two properties every bar widget reads are defined here with a fallback for
  // the moment before the host injects `bar`.
  readonly property bool vertical: bar ? bar.vertical : false
  readonly property int barSize: bar ? bar.barSize : Style.bar.sizeHorizontal

  // ---- settings -----------------------------------------------------------
  // The source directory is the one setting that cannot be guessed: a machine
  // that passes `chezmoi --source DIR` in a wrapper has no source in chezmoi's
  // own configuration, so `chezmoi source-path` cannot name it. Empty means
  // "whatever chezmoi is configured with".
  readonly property string sourceDir: String(setting("sourceDir", "")).replace(/^\s+|\s+$/g, "")

  readonly property int checkSeconds: {
    var n = Number(setting("checkSeconds", 300))
    if (!isFinite(n) || n < 60) return 300      // a floor, not a preference:
    if (n > 3600) return 3600                   // this runs git on a timer
    return Math.floor(n)
  }
  readonly property int pollInterval: root.checkSeconds * 1000

  readonly property bool showWhenClean: String(setting("whenClean", "Hide")) === "Show"

  // ---- the plugin's own scripts ------------------------------------------
  // Resolved next to this file, because a plugin that shells out to something
  // in one user's ~/.local/bin only works on the machine it was written on.
  readonly property string checkScript: Qt.resolvedUrl("bin/chezmoi-hound-check").toString().replace(/^file:\/\//, "")
  readonly property string actScript: Qt.resolvedUrl("bin/chezmoi-hound-act").toString().replace(/^file:\/\//, "")

  // A reading is input from another process, so it is bounded in size, type-
  // and range-checked, and a reading that disagrees with itself is rejected
  // outright instead of shown half-believed.
  readonly property int maxBytes: 65536

  property int homeCount: 0
  property int repoCount: 0
  property int unpushed: 0
  property int total: 0
  property var detail: []
  property var commits: []
  property var repoDetail: []
  property var notes: []
  property string stamp: ""
  property string reportedSource: ""
  property string branchName: ""
  property string upstream: ""
  property string problem: ""
  property bool everLoaded: false

  // ---- action state -------------------------------------------------------
  // Which action is in flight ("" when idle). While one runs the buttons are
  // inert: two commits racing over the same index, or a commit and a push
  // interleaving, is how a half-captured tree gets committed.
  property string running: ""
  property var logLines: []
  // The outcome of the last action as state, not log text: the panel says what
  // happened and then offers the one thing that makes sense next - close it,
  // or try again.
  property string result: ""          // "" | "ok" | "error"
  property string resultText: ""
  property string lastAction: ""
  // Set when a re-check is asked for while one is already running.
  property bool pendingRecheck: false

  // -1 means "the record was there but was not a count", which is different
  // from 0 and must not be mistaken for a valid reading.
  function countOf(value) {
    var n = Number(String(value))
    return (isFinite(n) && n >= 0 && n <= 100000) ? Math.floor(n) : -1
  }

  // The reading is a line protocol - "key<TAB>value", one record per line, in
  // no particular order - so the widget needs no JSON parser and the script
  // needs no jq.
  function apply(raw) {
    var text = String(raw || "")
    if (text.length === 0 || text.length > maxBytes) return false

    var lines = text.split("\n")
    var home = -1, repo = -1, unpushed = -1, total = -1
    var detail = [], commits = [], repoDetail = [], notes = []
    var src = "", branch = "", upstream = "", stamp = "", problem = ""

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
      else if (key === "file") { if (detail.length < 8) detail.push(plain(value)) }
      else if (key === "commit") { if (commits.length < 8) commits.push(plain(value)) }
      else if (key === "repofile") { if (repoDetail.length < 8) repoDetail.push(plain(value)) }
      else if (key === "note") { if (notes.length < 4) notes.push(plain(value)) }
      else if (key === "error") problem = plain(value)
      else if (key === "source") src = plain(value)
      else if (key === "branch") branch = plain(value)
      else if (key === "upstream") upstream = plain(value)
      else if (key === "stamp") stamp = value.substring(0, 32)
    }

    // An error record is a complete answer: say so and keep the last reading.
    if (problem !== "") {
      root.problem = problem
      return false
    }
    // The three parts must add up; a reading that disagrees with itself is
    // rejected rather than shown half-believed.
    if (home < 0 || repo < 0 || unpushed < 0 || total < 0) return false
    if (home + repo + unpushed !== total) return false

    root.homeCount = home
    root.repoCount = repo
    root.unpushed = unpushed
    root.total = total
    root.detail = detail
    root.commits = commits
    root.repoDetail = repoDetail
    root.notes = notes
    root.reportedSource = src
    root.branchName = branch
    root.upstream = upstream
    root.stamp = stamp
    root.problem = ""
    root.everLoaded = true
    return true
  }

  // bar.showTooltip renders with AutoText, which this plugin cannot pin to
  // PlainText, so markup and control characters are stripped before handoff.
  function plain(value) {
    return String(value)
      .replace(/[<>&]/g, "")
      .replace(/[\u0000-\u001f\u007f-\u009f\u200e\u200f\u202a-\u202e\u2066-\u2069]/g, "")
      .substring(0, 200)
  }

  function plural(count, noun) {
    return count + " " + noun + (count === 1 ? "" : "s")
  }

  function tooltip() {
    if (root.total === 0) {
      return root.everLoaded
        ? "Dotfiles in sync" + (root.stamp ? "  ·  checked " + root.stamp : "")
        : "No dotfiles reading yet  ·  the first check is on its way"
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

  // Naive plural: these are file counts, never language-facing prose.
  function countText() {
    return String(root.total)
  }

  function heroPhrase() {
    if (root.running !== "") return root.running === "push" ? "pushing…" : "capturing and committing…"
    if (root.problem !== "") return "Cannot read the dotfiles"
    if (root.total === 0) return root.everLoaded ? "In sync" : "Reading…"
    var parts = []
    if (root.homeCount > 0) parts.push(root.plural(root.homeCount, "edit") + " not captured")
    if (root.repoCount > 0) parts.push(root.plural(root.repoCount, "repo change") + " uncommitted")
    if (root.unpushed > 0) parts.push(root.plural(root.unpushed, "commit") + " not pushed")
    return parts.join("  ·  ")
  }

  function repoPhrase() {
    var where = root.sourceDir !== "" ? root.sourceDir : (root.reportedSource !== "" ? root.reportedSource : "chezmoi's default source")
    if (root.branchName !== "") where += "  ·  " + root.branchName
    return where
      + (root.stamp ? "\nchecked " + root.stamp : "")
  }

  // ---- actions ------------------------------------------------------------

  // Both buttons go through here, so there is exactly one place that decides
  // what a click runs and one place that refreshes the badge afterwards.
  function runAction(what) {
    if (actionProc.running || root.running !== "") return
    root.logLines = []
    root.result = ""
    root.resultText = ""
    root.lastAction = what
    root.running = what
    // 180s: capturing a large tree can take a while, and a half-captured tree
    // abandoned by a timeout is worse than a slow button.
    actionProc.command = withSource(["/usr/bin/timeout", "-k", "2", "180", root.actScript,
                                     what === "push" ? "push" : "commit"])
    actionProc.running = true
  }

  // The source argument is appended in exactly one place, so no call can forget
  // it and read a different tree than the badge is showing.
  function withSource(args) {
    var out = [].concat(args)
    if (root.sourceDir !== "") out.push("--source", root.sourceDir)
    return out
  }

  // Run the last action again - the other half of a failure.
  function retry() {
    if (root.lastAction !== "") root.runAction(root.lastAction)
  }

  // There is one bar surface per monitor, so there is one of us per screen. An
  // action lands on the instance that was clicked; the others are told to
  // re-check, or the other monitor keeps showing the count from before it.
  function notifyPeers() {
    var items = root.bar && typeof root.bar.moduleWidgets === "function"
      ? root.bar.moduleWidgets(root.moduleName) : []
    for (var i = 0; i < items.length; i++) {
      if (items[i] && items[i] !== root && typeof items[i].syncFromPeer === "function")
        items[i].syncFromPeer()
    }
  }

  // A peer can be mid-check when the call lands; the flag makes it run the
  // check again the moment the one in flight finishes, instead of leaving the
  // other monitor showing the count from before the action.
  function syncFromPeer() {
    if (checkProc.running) {
      root.pendingRecheck = true
      return
    }
    root.refresh(false)
  }

  // `notify` is true only where the reading changed because of something the
  // user did; the timer passes nothing, so a tick cannot ping-pong between
  // monitors.
  function refresh(notify) {
    // Peers are told first and unconditionally: an action must never leave
    // another monitor showing the count from before it, and a check of our own
    // already in flight must not swallow that.
    if (notify === true) notifyPeers()
    if (checkProc.running) {
      root.pendingRecheck = true
      return
    }
    checkProc.command = withSource(["/usr/bin/timeout", "-k", "2", "60", root.checkScript])
    checkProc.running = true
  }

  visible: root.total > 0 || root.showWhenClean
  implicitWidth: vertical ? barSize : (badge.width + Style.spaceReal(6))
  implicitHeight: vertical ? (badge.height + Style.spaceReal(6)) : barSize

  // The reading is taken on a timer rather than watched in a file: it is a few
  // chezmoi and git calls, and doing it here means the badge is right on a
  // machine that has never heard of a systemd timer.
  Timer {
    interval: root.pollInterval
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  // Right-click only: the old behaviour, kept because a floating terminal is
  // the one place the full `git diff`-worthy detail can be copied out of.
  Process {
    id: detailProc
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
    // actions. Middle re-runs the check now rather than waiting for the timer.
    // Right keeps the floating terminal for the full text.
    onClicked: function (mouse) {
      if (root.bar) root.bar.hideTooltip(root)
      if (mouse.button === Qt.LeftButton) {
        root.toggle()
      } else if (mouse.button === Qt.MiddleButton) {
        root.refresh()
      } else {
        if (!detailProc.running) {
          detailProc.command = withSource(["/usr/bin/omarchy-launch-floating-terminal-with-presentation",
                                           root.checkScript, "--render"])
          detailProc.running = true
        }
      }
    }
    onEntered: if (root.bar && !root.opened) root.bar.showTooltip(root, root.tooltip())
    onExited: if (root.bar) root.bar.hideTooltip(root)
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
      var applied = root.apply(checkOut.text)
      if (!applied && root.problem === "") {
        var err = plain(String(checkErr.text || "").trim())
        root.problem = err !== "" ? err : "chezmoi-hound-check exited " + code
      }
      // Someone asked for a fresh reading while this one was in flight.
      if (root.pendingRecheck) {
        root.pendingRecheck = false
        root.refresh(false)
      }
    }
  }

  Process {
    id: actionProc
    stdout: SplitParser {
      onRead: function (line) {
        var next = root.logLines.slice()
        next.push(String(line))
        // Bounded: this is a panel, not a scrollback.
        if (next.length > 12) next = next.slice(next.length - 12)
        root.logLines = next
      }
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var text = String(text || "").trim()
        if (text === "") return
        var next = root.logLines.slice()
        next.push(text)
        if (next.length > 12) next = next.slice(next.length - 12)
        root.logLines = next
      }
    }
    onExited: function (exitCode, exitStatus) {
      root.running = ""
      // The outcome is stated rather than left in the log to be inferred from:
      // success says so and offers to close, failure says what broke and
      // offers to try again.
      var tail = root.logLines.length > 0
        ? String(root.logLines[root.logLines.length - 1]).trim() : ""
      if (exitCode === 0) {
        root.result = "ok"
        root.resultText = tail !== "" ? tail
          : (root.lastAction === "push" ? "Pushed." : "Captured and committed.")
      } else {
        root.result = "error"
        root.resultText = tail !== "" ? tail : "the action exited " + exitCode
      }
      // Re-read now rather than at the next tick, and tell the other monitors'
      // badges to do the same.
      root.refresh(true)
    }
  }

  // The panel: the shape of the drift, then the buttons that act on it, then
  // the log of the last action. Everything it shows comes from the cache, so
  // opening it costs nothing.
  KeyboardPanel {
    id: panel
    anchorItem: badge
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(420))
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

        // Whatever the reading could not do - no chezmoi, no source tree, a
        // git command that failed - is said plainly instead of leaving the
        // panel insisting everything is fine.
        Text {
          width: parent.width
          visible: root.problem !== "" || root.notes.length > 0
          textFormat: Text.PlainText
          text: root.problem !== "" ? root.problem : root.notes.join("\n")
          color: root.bar.foreground
          opacity: 0.7
          wrapMode: Text.WordWrap
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.bodySmall
        }

        PanelSeparator {
          visible: root.unpushed > 0 && (root.homeCount > 0 || root.repoCount > 0)
          foreground: root.bar.foreground
        }

        // ---- edits made on this machine that the repo has not got ----
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

        // ---- the repo's own working tree ----
        Column {
          width: parent.width
          spacing: Style.space(8)
          visible: root.repoCount > 0

          PanelSectionHeader {
            text: "UNCOMMITTED IN THE REPO — " + root.plural(root.repoCount, "path")
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
          visible: root.total === 0
          textFormat: Text.PlainText
          text: root.everLoaded
            ? "$HOME, the repo and the remote all agree. Nothing to do."
            : "No reading yet — the first check is on its way."
          color: root.bar.foreground
          opacity: 0.7
          wrapMode: Text.WordWrap
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.bodySmall
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

        // ---- how the last action ended ----
        Column {
          width: parent.width
          spacing: Style.space(8)
          visible: root.result !== ""

          Text {
            width: parent.width
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            text: root.result === "ok" ? root.resultText : "Failed: " + root.resultText
            color: root.bar.foreground
            opacity: root.result === "ok" ? 0.85 : 1
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          Row {
            spacing: Style.space(8)

            Button {
              visible: root.result === "error"
              text: "Retry"
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              fontSize: Style.font.bodySmall
              horizontalPadding: Style.spacing.controlPaddingX
              verticalPadding: Style.spacing.controlPaddingY
              bordered: true
              onClicked: root.retry()
            }

            Button {
              text: "Close"
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              fontSize: Style.font.bodySmall
              horizontalPadding: Style.spacing.controlPaddingX
              verticalPadding: Style.spacing.controlPaddingY
              bordered: true
              onClicked: root.close()
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
  // screen: `omarchy-shell <id> status`. The other commands are the same entry
  // points the buttons call, so an action can be exercised without a synthetic
  // click.
  IpcHandler {
    target: "io.github.dadofsambonzuki.chezmoi-hound"

    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }

    function status(): string {
      return "total=" + root.total + " home=" + root.homeCount + " repo=" + root.repoCount
        + " unpushed=" + root.unpushed + " visible=" + root.visible
        + " running=" + (root.running === "" ? "idle" : root.running)
        + " problem=" + (root.problem === "" ? "none" : root.problem)
        + " source=" + (root.sourceDir !== "" ? root.sourceDir : (root.reportedSource === "" ? "unset" : root.reportedSource))
        + " branch=" + (root.branchName === "" ? "unset" : root.branchName)
        + " result=" + (root.result === "" ? "none" : root.result)
        + " lastAction=" + (root.lastAction === "" ? "none" : root.lastAction)
        + " stamp=" + root.stamp
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
        + " canPush=" + (root.unpushed > 0) + " canCommit=" + (root.homeCount + root.repoCount > 0)
        + " query=" + panel.fittedContentWidth(Style.space(420))
        + "x" + panel.fittedContentHeight(column.implicitHeight)
    }

    function commit(): void { root.runAction("commit") }
    function push(): void { root.runAction("push") }

    function refresh(): void {
      root.refresh()
    }

    function check(): void {
      root.refresh()
    }

    function reread(): void {
      root.refresh()
    }
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
