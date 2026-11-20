#!/usr/bin/env bash
# Exercise the import verdict without installing Godot. A fake command writes realistic
# logs and returns the status a runner observes; none of these logs is capture evidence.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
scratch="$(mktemp -d)"
trap 'rm -rf -- "$scratch"' EXIT
mkdir -p "$scratch/bin"
cat > "$scratch/bin/godot" <<'GODOT'
#!/usr/bin/env bash
case "$*" in
  '--headless --path . --import')
    echo import >> "$CALLS"
    printf '%s\n' "$IMPORT_LOG"
    exit "$IMPORT_CODE" ;;
  '--headless --editor --path . --quit')
    echo editor >> "$CALLS"
    printf '%s\n' "$EDITOR_LOG"
    exit "$EDITOR_CODE" ;;
  *) echo "unexpected Godot arguments: $*" >&2; exit 90 ;;
esac
GODOT
chmod +x "$scratch/bin/godot"

expect() {
  local name="$1" want="$2" import_code="$3" import_log="$4" editor_code="$5" editor_log="$6"
  local dir="$scratch/$name logs" code=0 summary
  summary=$(PATH="$scratch/bin:$PATH" CALLS="$scratch/$name.calls" \
    IMPORT_CODE="$import_code" IMPORT_LOG="$import_log" EDITOR_CODE="$editor_code" EDITOR_LOG="$editor_log" \
    bash "$root/tools/ci_import_godot.sh" "$dir" 2>&1) || code=$?
  if [[ "$code" != "$want" ]]; then
    printf 'FAIL: %s expected exit %s, got %s\n%s\n' "$name" "$want" "$code" "$summary" >&2
    exit 1
  fi
  [[ -f "$dir/import-1.log" && "$(cat "$dir/import-1.log")" == "$import_log" ]]
  if (( import_code == 0 )); then
    [[ "$(cat "$scratch/$name.calls")" == $'import\neditor' ]]
    [[ -f "$dir/import-2.log" && "$(cat "$dir/import-2.log")" == "$editor_log" ]]
  else
    [[ "$(cat "$scratch/$name.calls")" == import && ! -e "$dir/import-2.log" ]]
  fi
  if (( want == 0 )); then
    [[ "$summary" == *'IMPORT_RESULT=success'* && "$summary" != *'::error'* ]]
  else
    [[ "$summary" == *'IMPORT_RESULT=failure'* && "$summary" == *'::error title=Godot import::'* ]]
    [[ "$summary" != *'IMPORT_RESULT=success'* ]]
  fi
  printf 'ok: %s\n' "$name"
}

expect clean 0 0 'imported' 0 'editor ready'
expect cold_bootstrap_message 0 0 'ERROR: font not yet imported' 0 'editor ready'
expect cold_crash 139 139 'renderer crashed' 0 'must not run the editor'
expect cold_timeout 124 124 'import interrupted' 0 'must not run the editor'
expect warm_exit 2 0 'imported' 2 'editor failed'
expect warm_timeout 124 0 'imported' 124 'editor interrupted'
expect warm_parse_error 1 0 'imported' 0 'Parse Error: expected a token'
expect warm_script_error 1 0 'imported' 0 'SCRIPT ERROR: could not load the script'

printf 'PASS: the import preflight preserves both logs and rejects incomplete or broken passes.\n'
