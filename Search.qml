import QtQuick
import Quickshell.Io
import "Model.js" as Model

// Search belongs to the open panel; the shared service keeps watching mail.
Item {
  id: root

  property bool active: false
  property string query: ""
  property string accountId: ""
  property var accounts: []
  readonly property string term: query.trim()
  readonly property bool ready: (term.match(/[\s\S]/gu) || []).length >= 3
  property bool submitted: false
  property bool searching: false
  property var results: []
  property string error: ""

  property int _revision: 0
  property int _requestRevision: 0
  property bool _requestActive: false

  signal authenticationRequired()

  onTermChanged: {
    submitted = false
    restart()
  }
  onReadyChanged: restart()
  onAccountIdChanged: restart()
  onActiveChanged: restart()

  function restart() {
    _revision++
    results = []
    error = ""
    debounce.stop()
    searching = active && (ready || submitted)
    if (searching) debounce.restart()
    if (_requestActive) searchProcess.running = false
  }

  function submit() {
    if (!active || term === "") return
    submitted = true
    if (!searching) restart()
    debounce.stop()
    runSearch()
  }

  function runSearch() {
    // A stopped process can take time to exit. Its exit handler starts the
    // latest query if the typing delay has already elapsed by then.
    if (_requestActive || !searching) return
    _requestRevision = _revision
    _requestActive = true
    searchProcess.command = Model.searchCommand(term, accountId)
    searchProcess.running = true
  }

  Timer {
    id: debounce
    interval: 300
    onTriggered: root.runSearch()
  }

  Process {
    id: searchProcess
    stdout: StdioCollector { id: searchStdout; waitForEnd: true }
    stderr: StdioCollector { id: searchStderr; waitForEnd: true }
    onExited: function(exitCode) {
      root._requestActive = false
      if (root._requestRevision !== root._revision) {
        if (!debounce.running) root.runSearch()
        return
      }

      root.searching = false
      var parsed = exitCode === 0
        ? Model.parseSearchResults(searchStdout.text, root.accountId, root.accounts)
        : Model.parseFailure(searchStdout.text, searchStderr.text)
      if (!parsed.ok) {
        root.error = exitCode === 124 ? "Search timed out. Try again." : parsed.error
        if (Model.isAuthError(parsed.code)) root.authenticationRequired()
        return
      }
      root.results = parsed.items
    }
  }
}
