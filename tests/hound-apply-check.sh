#!/bin/sh
# chezmoi-hound-act apply: what it does per path, and the two rails it must keep.
#
# A fake `chezmoi` on PATH stands in for the real one, answering per path name,
# so every outcome and every assertion runs without a source to write to and
# without touching $HOME. Checks:
#
#   1. applied / left alone / failed are told apart, and a failed path is the
#      only thing that makes the action exit non-zero (a hand-edited file is
#      reported, not treated as an error).
#   2. a path that is only hand-edited leaves the action at exit 0 and says so.
#   3. every invocation carries --no-tty (the panel has no terminal; without it
#      chezmoi would try to prompt) and names an absolute path under $HOME.
#   4. no invocation is made without a path: the action never becomes a
#      whole-tree apply.
set -u

ACT=${ACT:-/home/nathan-day/Projects/chezmoi-hound/bin/chezmoi-hound-act}
SRC=${SRC:-/home/nathan-day/Projects/infra/dotfiles}
WORK=$(mktemp -d "${TMPDIR:-/tmp}/hound-apply-test.XXXXXX") || exit 1
trap 'rm -rf "$WORK"' EXIT INT TERM

mkdir -p "$WORK/bin"
cat > "$WORK/bin/chezmoi" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$CALLS"
case "$*" in
    *clean*)   exit 0 ;;
    *edited*)  printf '.edited has changed since chezmoi last wrote it (diff/overwrite/all-overwrite/skip/quit)? chezmoi: .edited: EOF\n' >&2; exit 1 ;;
    *missing*) printf 'chezmoi: %s: not managed\n' "${3:-}" >&2; exit 1 ;;
esac
exit 0
EOF
chmod +x "$WORK/bin/chezmoi"
export CALLS="$WORK/calls"
PATH="$WORK/bin:$PATH"
export PATH

pass=0
fail=0
ok() { printf 'ok   %s\n' "$1"; pass=$((pass + 1)); }
no() { printf 'FAIL %s\n' "$1"; fail=$((fail + 1)); }

run() { : > "$CALLS"; sh "$ACT" apply --source "$SRC" "$@" 2>&1; }

echo "chezmoi-hound-act apply, against a fake chezmoi:"
echo

out=$(run --path clean.txt --path edited.txt --path missing.txt); rc=$?
echo "$out" | sed 's/^/     /'
case "$out" in *'applied clean.txt'*) ok "an applied path is reported as applied" ;; *) no "an applied path is reported as applied" ;; esac
case "$out" in *'left alone, changed here since chezmoi wrote it: edited.txt'*) ok "a hand-edited path is reported as left alone" ;; *) no "a hand-edited path is reported as left alone" ;; esac
case "$out" in *'could not apply missing.txt'*) ok "a path chezmoi refuses is reported as failed" ;; *) no "a path chezmoi refuses is reported as failed" ;; esac
[ "$rc" -eq 1 ] && ok "a failure makes the action exit 1" || no "a failure makes the action exit 1 (got $rc)"

out=$(run --path edited.txt); rc=$?
case "$out" in *'nothing was overwritten'*) ok "only hand-edited: says nothing was overwritten" ;; *) no "only hand-edited: says nothing was overwritten" ;; esac
[ "$rc" -eq 0 ] && ok "only hand-edited: exit stays 0" || no "only hand-edited: exit stays 0 (got $rc)"

out=$(run --path missing.txt); rc=$?
[ "$rc" -eq 1 ] && ok "a refused path on its own exits 1" || no "a refused path on its own exits 1 (got $rc)"

# Rails, read off what the fake chezmoi was actually called with.
: > "$CALLS"
run --path clean.txt >/dev/null
if grep -q -- '--no-tty apply' "$CALLS"; then ok "every call is --no-tty (nothing can prompt)"; else no "every call is --no-tty (got: $(cat "$CALLS"))"; fi
if grep -qE "apply /(home|root|Users)/[^ ]+$" "$CALLS"; then ok "each call names an absolute path under \$HOME"; else no "each call names an absolute path under \$HOME (got: $(cat "$CALLS"))"; fi
if grep -qE '(^| )apply$' "$CALLS"; then no "no call applies the whole tree"; else ok "no call applies the whole tree"; fi
if grep -q -- '--force' "$CALLS"; then no "nothing is forced"; else ok "nothing is forced"; fi

echo
printf '%s ok, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
