# Chezmoi Hound

A bar count of **dotfile drift** that hunts it down.

Chezmoi Hound adds up three different kinds of drift into one number in the
Omarchy bar, and when you click that number it names the items and offers the two
things a count of drift makes you want to do: **push** what the remote has not
seen, and **capture and commit** what this machine has edited.

```
  home      managed targets this machine has edited and the source has not captured
  repo      paths the source repo's own working tree is holding uncommitted
  unpushed  commits in the source repo the remote has not seen

  total = home + repo + unpushed          <- the number on the bar
```

![Chezmoi Hound's panel: the count, the drifting items, and the two actions](preview.png)

- The badge is only ever a number. No glyph, no icon, nothing to misread.
- It is **silent when everything agrees** — a permanent `0` on the bar is noise.
- The panel names the drift, section by section, with the commits and paths
  involved, so the number is never a mystery.
- Nothing is captured or pushed without your click. See [What it runs](#what-it-runs).

## Install

Omarchy 4 (Quattro) with the Omarchy shell:

```sh
omarchy plugin add https://github.com/dadofsambonzuki/chezmoi-hound.git --enable --yes
```

That clones the plugin, registers it with the shell and enables it. The count
appears in the bar's right section (drag it wherever you like afterwards).

`omarchy plugin add` prints Omarchy's warning that plugins run unsandboxed inside
the shell and asks you to confirm before it continues; `--yes` accepts it. [Review
the code](bin/chezmoi-hound-check) first — it is short on purpose.

If your chezmoi source is not the one chezmoi is configured for — for example you
normally run `chezmoi --source ~/Projects/dotfiles` — open the widget's settings
and set **chezmoi source directory** to that path. Everything else has a sane
default.

### Requirements

External dependencies, all of which an Omarchy machine already has:

| Dependency | Why | Version |
| --- | --- | --- |
| [`chezmoi`](https://www.chezmoi.io/) | reads the drift in `$HOME` | any v2 (`chezmoi status`, `chezmoi source-path`) |
| `git` | the source repo's working tree and its unpushed commits | any |
| `omarchy-launch-floating-terminal-with-presentation` | the panel's **Full details** button | ships with Omarchy |

There is no dependency on `jq`, on a systemd timer, or on anything in
`~/.local/bin`: the widget ships its own two scripts and runs them itself.

## Remove

```sh
omarchy plugin remove io.github.dadofsambonzuki.chezmoi-hound --yes
```

That unregisters the widget and deletes the plugin directory. Nothing else on the
machine is touched: the plugin keeps no cache file, writes no config, and adds no
timer or service. The only thing left behind is whatever you read into the bar
layout in `~/.config/omarchy/shell.json`, which Omarchy writes itself.

## Settings

| Setting | Default | Meaning |
| --- | --- | --- |
| **chezmoi source directory** | *(empty)* | Empty means "chezmoi's own configured source". Set it when the tree is one you pass to `chezmoi --source`. |
| **Re-check every (seconds)** | `300` | How often the widget re-reads the drift. 60–3600; a lower value costs more `chezmoi status` runs, not more network — this plugin never fetches. |
| **When everything is in sync** | `Hide` | Hide keeps a permanent zero off the bar. Show leaves the count visible always. |

## Using it

| Where | What it does |
| --- | --- |
| Left-click the count | Opens the panel: the drift, and the actions |
| Middle-click | Re-checks now, without waiting for the interval |
| Right-click | Opens a floating terminal with the full text |
| **Push N commits** | `git push` on the branch's existing upstream — nothing else |
| **Capture and commit** | `chezmoi add` each edited target, then one local commit |

The two action buttons only appear when there is something for them to do.

When an action finishes, the panel says what happened rather than leaving you to
read it out of the log: a success offers **Close**, and a failure shows what
broke and offers **Retry**.

Every monitor shows the same count. There is one bar surface per screen, so the
widget runs once per monitor; finishing an action on one screen tells the others
to re-check, instead of leaving them on the count from before it.

### What a commit and a push will and will not do

- **Commit** captures targets whose state is `M` (modified here) or `A` (new
  here), one `chezmoi add` each, then commits the source repo with
  `Capture dotfiles drift from <host> on <date>`. It also commits tracked edits
  already sitting in the source repo (`git add -u`) — never untracked stray
  files.
- A target whose source is a **template** (`*.tmpl`) is reported and left alone.
  Re-adding a template would overwrite the template with this machine's rendered
  output and stop it being a template.
- A target that was **deleted** in `$HOME` is reported and left alone. Deleting
  the source because a live file vanished is a judgement call, not a button.
- **Push** goes only to the branch's current upstream. It never force-pushes,
  never changes a remote, and never touches another branch. With no upstream it
  says so and does nothing.

## What it runs

The plugin is two POSIX `sh` scripts plus one QML file:

| File | Role |
| --- | --- |
| `BarWidget.qml` | the badge, the panel, and the clock that re-reads the drift |
| `bin/chezmoi-hound-check` | reads the drift, prints it in a line protocol |
| `bin/chezmoi-hound-act` | runs the two actions |

- The scripts are invoked directly, **not through a shell**, from the plugin's
  own directory — they are resolved relative to `BarWidget.qml`, so the plugin
  works from wherever it was installed.
- They run `chezmoi status`, `chezmoi source-path`, `chezmoi add`, and plain
  `git` inside your source repo. Nothing else. No `sudo`, no network, no
  `eval`, no writes outside the source repo.
- A malformed or failed reading leaves the previous number on screen and says why
  in the panel; it never empties the badge or invents a number.
- A reading is refused outright unless the three counts add up to the total.

Read `bin/chezmoi-hound-check` and `bin/chezmoi-hound-act` — they are short, and
the comments say why each rule exists.

## License

MIT — see [LICENSE](LICENSE).

## Implementation notes

- Settings live inline on the widget's entry in `~/.config/omarchy/shell.json`.
  Do not name a setting `type`, `exec` or `source`: the bar reads those three
  keys as a *custom module* definition, and an entry carrying one stops being a
  plugin widget at all — the bar goes looking for a QML file or a command and
  the widget silently never mounts. That is why the setting here is `sourceDir`.
- The widget runs one instance per monitor, so anything that changes state has
  to be published to the other instances (`bar.moduleWidgets()`) or the screens
  disagree.
- The counting and the git work are in `bin/`, not in QML: `chezmoi-hound-check`
  answers in a line protocol (`key<TAB>value`) and `chezmoi-hound-act` does the
  committing and pushing, with exit codes the panel can act on.
