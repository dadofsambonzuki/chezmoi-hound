# Marketplace submission (ready to file, on request)

The Omarchy plugin marketplace takes listings as an **issue** on
`omacom/omarchy-plugin-marketplace` (per its `SUBMISSION.md`), not a PR. This is
the prepared body — nothing has been filed.

```sh
gh issue create --repo omacom/omarchy-plugin-marketplace \
  --title "Chezmoi Hound" \
  --body-file docs/submission.md
```

## Repository

https://github.com/dadofsambonzuki/chezmoi-hound

## Category

System

## Tags

`bar`, `system`, `quickshell`

## Summary

A bar count of chezmoi dotfile drift, added up from three places: managed
targets edited on this machine and not captured by the source, paths the source
repo has not committed, and commits the remote has not seen. Clicking the count
opens a panel that names every drifting item and offers the two things the count
makes you want to do — push what the remote has not seen, or capture and commit
what this machine has edited. The panel states the outcome of an action
(success offers Close; failure shows the error and offers Retry), and every
monitor's badge stays in step.

## Install

```sh
omarchy plugin add https://github.com/dadofsambonzuki/chezmoi-hound.git --enable
```

Then, if the chezmoi source is not the one chezmoi is configured with, set
**chezmoi source directory** in the widget's settings.

## Removal

```sh
omarchy plugin remove io.github.dadofsambonzuki.chezmoi-hound --yes
```

## External dependencies

- `chezmoi` v2 — reads the drift in `$HOME` (`chezmoi status`, `chezmoi source-path`)
- `git` — the source repo's working tree and its unpushed commits

No `jq`, no cache file, no timer, nothing in a user's `~/.local/bin`: the plugin
ships its own two scripts and runs them itself.

## Licence

MIT (LICENSE at the repo root)

## Preview

`preview.png` at the repo root.

## Notes

- Nothing is written to the user's configuration without an explicit click: the
  widget only reads, and the commits and the push happen behind the panel's two
  buttons. Push only ever goes to the branch's existing upstream, and never
  force-pushes.
- Templates (`*.tmpl`) and `$HOME`-side deletions are reported and never
  captured automatically.
