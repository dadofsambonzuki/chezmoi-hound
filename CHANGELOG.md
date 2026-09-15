# Changelog

## 1.1.0

- **Capture and commit** now opens a commit message entry instead of committing
  wording nobody chose. It arrives prefilled with the wording the script
  generates (what drifted, where, and when), so an empty entry still commits
  something that says something. Nothing is committed until the button is
  pressed.
- **Suggest with <agent>** writes the message from the diff, using the machine's
  default coding agent — the one `omarchy default agent` reports, whatever it is
  — through that agent's own non-interactive mode. An agent with no such mode
  gets no button rather than a button that hangs, and the `aiCommand` setting
  pins a different one.
- The line under the entry says where the wording came from: a suggestion is
  credited to the agent that wrote it, generated wording is never credited to an
  agent that did not write it, and a failed suggestion says so with its exit
  code.
- A suggestion cannot push: the push stays a separate, separately-pressed action.
- `suggest --probe` lets anything else ask which agent would be used
  (`ai=<command>` or `ai=none`), and the panel exposes `suggest` and
  `commitWith` over its IPC target.

## 1.0.0

First release.

- A bar count of dotfile drift: targets edited here and not captured by the
  source, uncommitted paths in the source repo, and commits the remote has not
  seen, added up into one number.
- Clicking the count opens a panel that names the drift and offers **Push N
  commits** and **Capture and commit**, each shown only when there is something
  to do.
- The badge hides itself when everything agrees, and is a plain number
  otherwise.
- Self-contained: no `jq`, no cache file, no systemd timer, no `~/.local/bin`
  dependency. The widget re-reads on its own interval and after every action.
- Configurable chezmoi source directory, re-check interval, and clean-state
  behaviour.
- Templates and `$HOME`-side deletions are reported and never captured
  automatically. Push only ever goes to the branch's existing upstream, and
  never force-pushes.
- The panel states the outcome of an action instead of only logging it: success
  offers **Close**, failure shows what broke and offers **Retry**.
- One instance runs per monitor; finishing an action refreshes the other
  monitors so their counts stay in step.
- `push` and `commit` exit non-zero when they fail, so a refused push is
  reported as a failure rather than a success.
- The panel is titled after the plugin.
