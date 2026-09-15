# Changelog

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
