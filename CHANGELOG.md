# Changelog

## 1.1.4

- **A suggestion works under the environment the panel actually runs in.** The
  sandbox bound the tool runtimes but not the command the leg had resolved, and
  the shell that presses Suggest finds agents in two places that were outside the
  namespace: a wrapper in `$HOME/.local/bin` (hermes) and a mise shim in
  `$HOME/.local/share/mise/shims` (opencode, codex, gemini, claude). The wrapper
  was not there to exec — `env: 'hermes': No such file or directory`, status 127 —
  and a shim is a symlink to the mise binary, so resolving it ran mise as the agent
  and reported `mise ERROR no tasks defined`. The command is now resolved on the
  host, through `mise which` where a shim stands for one, and that one file is
  bound into the namespace. Developers whose `PATH` already pointed into the
  installs did not see this; the panel's environment did.
- Measured in both environments, with each agent run through the leg: hermes,
  opencode and codex answer in both; gemini and claude report their own
  not-logged-in state in both.

## 1.1.3

- **A suggestion no longer fails for the agents that are handed the prompt on
  stdin.** The sandbox code rewrote the shell function's own arguments — once
  onto the agent's command line and again onto bubblewrap's — and then read the
  drift file out of `$3` as if those argument lists had never touched it. `$3`
  was a bubblewrap or agent option by then, so the shell tried to open
  `--unshare-pid` as a file: the agent never ran, and Suggest reported the
  agent's own failure. Taking the two files before anything rewrites the
  arguments fixes it, and opencode, codex and hermes all return a suggestion
  again.
- Verified by running each supported agent through the leg: hermes, opencode and
  codex answer; gemini and claude report their own not-logged-in failures.

## 1.1.2

- **A suggestion no longer reads the whole machine, and no longer runs without a
  sandbox.** The previous sandbox bound `/` read-only, which stops writes but not
  reads: an agent that had been talked into it could still read your ssh keys,
  `gh` credentials and shell environment. The namespace is now an allowlist —
  the machine's runtime (`/usr`, `/etc`, `/opt`), the agents' own runtimes, the
  resolver file, `/proc`, `/dev`, and an empty directory as its working
  directory. `$HOME` is empty, with only the agents' own directories overlaid
  back in, so keys, keyrings, `gh` credentials, `chezmoi` config, projects and
  documents are not there to be read at all.
- The agent's **environment is cleared** rather than inherited: it gets `PATH`,
  `HOME`, `TERM`, `LANG`, `TMPDIR` and a provider key, not the shell's exported
  tokens or its ssh agent socket.
- **`bubblewrap` is required for Suggest**, not merely used when present. There
  is no unsandboxed path left: the `HOUND_NO_SANDBOX` escape hatch is gone, and
  without `bubblewrap` the leg refuses to run and the **Suggest** button is not
  offered.
- Two faults found by testing the above against a live agent: the empty home was
  mounted *after* the agents' runtimes, which hid them and stopped the agent
  starting; and `/etc/resolv.conf` points into `/run` on this distribution, so
  without the resolver file bound the provider call failed as if the endpoint
  were down.

## 1.1.1

- **A suggestion can no longer change anything.** The drift handed to an agent is
  text out of files that may have arrived from anywhere, and the agent used to
  receive it with its tools switched on. It is now asked to work with them off —
  `claude --tools ''`, `codex exec -s read-only`, `gemini --approval-mode plan`,
  `opencode run --agent plan`, `hermes -t todo` — and, where `bubblewrap` is
  installed, is sandboxed as well: the filesystem read-only, an empty throwaway
  working directory, its own state overlaid so nothing it writes outlives the
  run, and key material masked. The diff reaches the agent fenced and labelled as
  untrusted data.
- The **lock** moved out of `$TMPDIR` and into a `0700` directory this user owns
  (`$XDG_RUNTIME_DIR/chezmoi-hound`, else `$HOME/.cache/chezmoi-hound`). A lock
  whose *name* another account can create is a lock that can be pointed at a
  symlink and made to truncate a file of yours. It is now created without
  following links, and opened without truncation.
- The agent runs in a **directory of its own** rather than in the source tree it
  is describing.

## 1.1.0

- A **zero** on the bar is drawn in the same colour as every other count. It used
  to be dimmed and half faded as well, which read as a different sort of number
  rather than as "nothing to do" — the count is the count.
- **Dotfile Drift** is now a permanent heading. With nothing to report it carries
  no count and says *No drift detected — the files here match the source.* in
  place of the list, so the panel keeps its shape and gains a line of plain
  English where the section used to disappear.
- Neither action button is offered with nothing to do: **Capture and commit** is
  absent when there is no drift, and **Push** only appears when the remote has
  not seen a commit. The rows above it record what is already committed; they are
  not a reason for the button.
- **Close** moved to the panel's foot, last of **Re-check now**, **Full
  details**, **Settings**. It used to trail the last action's outcome, so the way
  out of the panel moved around depending on what had just happened. **Retry**
  stays with the failure that asks for it.

- **Capture and commit** now opens a **blank** commit message entry instead of
  committing wording nobody chose. Nothing is filled in for you, and nothing is
  committed until the button is pressed. Press Commit on an empty entry and the
  commit carries no message at all, which the panel says under the entry
  beforehand. That replaces the generated wording (`Capture dotfiles drift from
  <host> on <date>`, then the paths): a list of files is not a message, and a run
  script that is merely due is not even in the commit the list describes.
- Each row of the commit history carries a small **undo** arrow. It asks first,
  repeating the row and saying what taking that commit back means for it: the
  newest unpushed commit leaves the history and its changes return to the working
  tree as drift, while a commit the remote has seen — or one with commits on top
  of it — keeps its place and only its changes are undone. A commit that cannot
  be undone without a clash is backed out entirely and reported, never left as a
  conflicted tree, and only the five commits on screen can be named at all.
- **Suggest with <agent>** writes the message from the diff, using the machine's
  default coding agent — the one `omarchy default agent` reports, whatever it is
  — through that agent's own non-interactive mode. An agent with no such mode
  gets no button rather than a button that hangs, and the `aiCommand` setting
  pins a different one.
- The line under the entry says where the wording came from: a suggestion is
  credited to the agent that wrote it, and a suggestion that failed is never
  papered over — it says so with its exit code and leaves the entry as the person
  left it.
- `suggest` has no generated fallback and no `--draft` flag. With no agent on the
  machine, or an agent that answers with nothing usable, it prints nothing, and
  the message stays the person's to write.
- A suggestion cannot push: the push stays a separate, separately-pressed action.
- **The drift an agent is shown is file drift only.** `chezmoi status` reports
  `R` for every `run_` script on every run, forever - a script is always due on
  the next apply, so that line never clears - and chezmoi prints a due script's
  entire body as a new file in `chezmoi diff`. Both lists therefore drop run
  scripts (`chez diff -x scripts`). Otherwise every request carried the paths and
  the full text of the machine's `run_` wrappers, and the agent answered with the
  wrapper it had just been handed: an installed feature proposed back as work to
  do. The check script already filtered them; now the brief does too.
- **The panel shows the repo's last five commits where it used to show the last
  action's log.** That log could only ever restate what the last button press did
  — which the badge had already answered by changing — and it was empty on every
  fresh start, so it spent its rows saying nothing. The history is a fact about
  the dotfiles themselves. Five rows, newest first, `sha` then subject, with no
  age column: a long message is the only thing that can elide, so nothing else is
  lost to it. `chezmoi-hound-check --render` prints the same five with their ages,
  for the terminal, where the width costs nothing.

- **The panel's top section is gone.** A title, a phrase and the source path
  restated what the badge, the tooltip and the rows under them already said, so
  the panel now opens on the drift itself. **`Dotfile Drift` is the heading that
  replaces "edited here, not captured"**, and each heading counts its own list
  (`Dotfile Drift — 1 change`, `Latest commits — 2 not pushed`) rather than
  leaving the count to be worked out from the rows. The history's count is only
  the commits the remote has not seen, and it is dropped when there are none.
- **The commit message entry opens where the button was pressed.** It used to
  live at the foot of the panel, past the history, which put the field and the
  list it describes at opposite ends of the panel. It is now placed in the
  section that asked for it — under **Capture and commit** for the drift, under
  **Commit n repo changes** for the source tree — and that section holds it on
  screen while it is open, so a re-check that empties the list cannot take the
  field out from under the person typing in it.
- **Section titles take the full-strength foreground.** The shared section header
  is already bold; its default colour was dimmed 1.4x to sit under a hero this
  panel no longer has, which left a title the same grey as the rows beneath it.
- **The rule now falls between the drift and the history**, and only when there is
  something on both sides of it: the old one ran across the top of the panel,
  under nothing.
- **The AI command field says what its empty state means**: *Uses the default
  Omarchy agent unless overridden here.*
- **Full details did nothing, and now it works.** The button set `running` on the
  process that opens the floating terminal without ever setting its `command` —
  only the badge's right-click did that — so it started a process with nothing to
  run and no terminal appeared. Both entry points now call one `showDetails()`,
  and `details` exposes it over IPC so the read-out can be opened without a click.
- **The widget's options are in the panel.** Nothing in the shell draws a form for
  a widget's settings — `settingsForm` is declared in manifests and rendered by
  nothing — so the panel draws its own behind the **Settings** button: source
  directory, seconds between checks, AI command, and show-when-clean. Each change
  is written back into this widget's entry in the bar layout as it is made
  (`settingsSet` over IPC, `omarchy bar set` from a shell), so it survives a
  restart.
- `suggest --probe` lets anything else ask which agent would be used
  (`ai=<command>` or `ai=none`), and the panel exposes `suggest` and
  `commitWith` over its IPC target.
- **The history's heading is `Latest commits`**, not "latest local commits": the
  rows are the source repo's own history and *local* was doing no work. A finished
  action likewise states its outcome in the panel's own words — **`Captured and
  committed.`**, **`Pushed.`**, **`Undone.`** — instead of echoing the script's last
  log line, which read out **`1 target(s) captured`** and its like. The script's log
  is still exactly what **Full details** prints. A suggestion in flight is likewise
  stated once, on the button that asked for it (**`Asking hermes…`**), instead of a
  second time as a line under the entry; that line now carries only what came back
  — who wrote the wording, or why nobody did.

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
