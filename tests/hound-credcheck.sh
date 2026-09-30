#!/bin/sh
# Credential minimisation check, per harness/provider.
#
# For each agent: plant a fake key for EVERY provider in the parent environment
# (and extra key-shaped lines in ~/.hermes/.env), run the leg through the shipped
# script, and report which planted names reach the process - its environment, and
# the .env file the sandbox hands it. Then run the real agent with every *other*
# provider's key planted, and check its output for the planted values.
set -u
A=/home/nathan-day/Projects/chezmoi-hound/bin/chezmoi-hound-act
ENVF=$HOME/.hermes/.env
BAK=/tmp/hermes-env.bak
FAKE=$HOME/.local/fakebin

cp "$ENVF" "$BAK" || exit 1
printf 'PLANT_ANTHROPIC_API_KEY=PLANT-ANTHROPIC-7f3a\nPLANT_OPENAI_API_KEY=PLANT-OPENAI-7f3a\nPLANT_GEMINI_API_KEY=PLANT-GEMINI-7f3a\nPLANT_OPENROUTER_API_KEY=PLANT-OPENROUTER-7f3a\nPLANT_GITHUB_TOKEN=PLANT-GITHUB-7f3a\nPLANT_SLACK_BOT_TOKEN=PLANT-SLACK-7f3a\n' >> "$ENVF"
echo "planted key-shaped lines in ~/.hermes/.env: $(grep -c 'PLANT-' "$ENVF")   (total lines $(wc -l < "$ENVF"))"

# The fake agent reports, on one stderr line: which planted variables are in this
# process's environment, every variable name it was given, and the names in the
# .env the sandbox handed it. Names only - never a value.
# NB /proc/self/environ must be piped, not redirected: on this kernel a shell
# redirect into tr reads 0 bytes, which would make every assertion vacuously pass.
mkdir -p "$FAKE"
for a in claude codex gemini opencode hermes; do
    cat > "$FAKE/$a" <<'EOFA'
#!/bin/sh
hits=$(cat /proc/self/environ | tr '\0' '\n' | awk -F= '/PLANT-/{printf "%s,", $1}')
all=$(cat /proc/self/environ | tr '\0' '\n' | awk -F= '{printf "%s,", $1}')
henv="none"
[ -f "$HOME/.hermes/.env" ] && henv=$(awk -F= '{printf "%s,", $1}' "$HOME/.hermes/.env")
printf 'PROBE plant_hits=[%s] env=[%s] hermes_env=[%s]\n' "$hits" "$all" "$henv" 1>&2
exit 1
EOFA
    chmod +x "$FAKE/$a"
done

for v in ANTHROPIC_API_KEY OPENAI_API_KEY GEMINI_API_KEY GOOGLE_API_KEY \
         OPENROUTER_API_KEY XAI_API_KEY MISTRAL_API_KEY DEEPSEEK_API_KEY \
         GITHUB_TOKEN SLACK_BOT_TOKEN; do
    eval "export $v=PLANT-$v-7f3a"
done
echo "planted provider keys in parent environment: $(env | grep -c 'PLANT-')"

echo
echo "=== pass 1: what each agent's process can see (all provider keys planted)"
echo "    expected: claude only its own, codex only its own, gemini only its own,"
echo "              opencode none, hermes none in env + only its transport line in .env"
export PATH="$FAKE:/usr/share/omarchy/bin:/usr/bin:/bin"
for a in claude codex gemini opencode hermes; do
    out=$("$A" suggest --source /tmp/hound-canary/src --ai "$a" 2>&1 | grep 'err=' | head -1)
    printf '%-9s %s\n' "$a" "$(printf '%s' "$out" | sed 's/^HOUND-SUGGEST err=//')"
done

echo
echo "=== pass 2: the real agent, every *other* provider's key planted"
export PATH="/usr/share/omarchy/bin:$HOME/.local/share/mise/shims:$HOME/.local/bin:/usr/bin:/bin"
for a in opencode codex hermes; do
    own=""
    case "$a" in codex) own="OPENAI_API_KEY" ;; esac
    # Unset only this agent's own transport variable so its native credential is
    # what it authenticates with; every other provider stays poisoned.
    if [ -n "$own" ]; then eval "unset $own"; fi
    out=$("$A" suggest --source /tmp/hound-canary/src --ai "$a" 2>&1)
    if [ -n "$own" ]; then eval "export $own=PLANT-$own-7f3a"; fi
    leak=$(printf '%s' "$out" | grep -c 'PLANT-')
    printf '%-9s planted_leak=%s | %s\n' "$a" "$leak" "$(printf '%s' "$out" | head -2 | tr '\n' ' ')"
done

echo
echo "=== restoring ~/.hermes/.env"
cp "$BAK" "$ENVF"
if cmp -s "$BAK" "$ENVF"; then echo ".env restored byte-identical"; else echo ".env RESTORE FAILED"; fi
if grep -q 'PLANT-' "$ENVF"; then echo "WARNING: planted lines left in .env"; else echo "no planted lines left in .env"; fi
