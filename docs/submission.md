# Marketplace submission (filed — this is the record of it)

The Omarchy plugin marketplace takes listings as an **issue** on
`omacom/omarchy-plugin-marketplace` (per its `SUBMISSION.md`), not a PR.

**Status:** filed 2026-09-18 as issue #7526, listed 2026-09-21 at **1.1.6**
(`26e623d`). Releases after an approval are heads-ups as comments on that same
issue — the routed validation run is skipped once a plugin is listed, so a newer
commit is re-validated only if a maintainer runs it. A second submission issue is
never opened.

The body below is kept current, so that a resubmission (if the listing were ever
removed) does not start from the 1.0 wording.

## Repository

https://github.com/dadofsambonzuki/chezmoi-hound

## Category

System

## Tags

`bar`, `system`, `quickshell`

## Summary

A bar count of chezmoi dotfile drift, added up from three places: managed targets
edited on this machine and not captured by the source, paths the source repo has
not committed, and commits the remote has not seen. Clicking the count opens a
panel that names every drifting item and offers what the count makes you want to
do:

- **Push** what the remote has not seen — the branch's existing upstream, nothing
  else.
- **Capture and commit** what this machine has edited, with a commit message you
  write, or one your own coding agent writes on request from the diff.
- **Add to .chezmoiignore** for the paths that were never dotfiles: they stop
  being managed and counted, and nothing in your home is touched.
- **Apply the source** for a file chezmoi generates itself, which cannot be
  captured: the source's version goes back into your home. It names the paths it
  will write, and a path you have edited since chezmoi last wrote it is reported
  and left alone rather than overwritten.

The panel states the outcome of an action (success offers Close; failure shows
what broke and offers Retry), and every monitor's badge stays in step.

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
  and writes it back for the apply action (`chezmoi apply`)
- `git` — the source repo's working tree and its unpushed commits
- optional: `bubblewrap`, which the suggestion leg requires before it will run an
  agent at all

No `jq`, no cache file, no timer, nothing in a user's `~/.local/bin`: the plugin
ships its own scripts and runs them itself.

## Licence

MIT (LICENSE at the repo root)

## Preview

`preview.png` at the repo root, captured with drift on screen so the actions are
visible — they only appear when there is something to act on.

## Notes

- **Nothing runs until a button is pressed.** The widget only reads; the commit,
  the push, the `.chezmoiignore` edit and the apply all happen behind an explicit
  press (and the two that write ask for a second one).
- **What each press may touch.** Push only ever goes to the branch's existing
  upstream, and never force-pushes. Capture writes inside the source repo and
  makes a local commit. Add to .chezmoiignore writes one file, the source's
  `.chezmoiignore`. Apply writes in your home, and only for the paths the panel is
  showing: never the whole tree, and never `chezmoi --force`, so a file you have
  edited since chezmoi last wrote it comes back as *left alone* instead of being
  overwritten.
- Templates (`*.tmpl`) are reported and never captured automatically: the source
  version of one is a template, not the rendered output.
- The suggestion leg runs each supported agent with its tools off inside an
  allowlist sandbox, and passes exactly one credential — the one its chosen
  transport needs.
