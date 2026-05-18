#!/usr/bin/env bash
# auto-bootstrap-project.sh — Hook SessionStart silencioso.
#
# Detecta proyecto NUEVO y aplica clusters.local.yaml automático.
#
# Condiciones de activación (TODAS):
#   1. cwd está bajo $HOME/Desktop/ (no /tmp, no /, no ~)
#   2. cwd tiene .git/ (es repo git)
#   3. cwd NO tiene .claude/skill-router/clusters.local.yaml (no bootstrapped aún)
#   4. cwd NO está en blacklist (~/.claude/skill-router/bootstrap-blacklist.txt)
#
# Si todas se cumplen: ejecuta setup-router-project.sh silencioso.
# Output sigue protocolo de hook (nada al stdout salvo si quieres mostrar al user).

set -euo pipefail

CWD="${CLAUDE_PROJECT_DIR:-$PWD}"

# Solo bajo ~/Desktop/
[[ "$CWD" == "$HOME/Desktop/"* ]] || exit 0

# Solo repos git
[[ -d "$CWD/.git" ]] || exit 0

# Solo si NO existe ya el yaml
[[ -f "$CWD/.claude/skill-router/clusters.local.yaml" ]] && exit 0

# Solo si NO está en blacklist
BLACKLIST="$HOME/.claude/skill-router/bootstrap-blacklist.txt"
if [ -f "$BLACKLIST" ] && grep -Fxq "$CWD" "$BLACKLIST" 2>/dev/null; then
  exit 0
fi

# Bootstrap silencioso
SETUP="$HOME/.claude/skill-router/bin/setup-router-project.sh"
[[ -x "$SETUP" ]] || exit 0

cd "$CWD"
bash "$SETUP" >/dev/null 2>&1 || true

# Emite mensaje vía hookSpecificOutput (lo verá el modelo, NO el usuario)
PROJECT_NAME="$(basename "$CWD")"
printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"[skill-router] Auto-bootstrap detectado: nuevo proyecto %s sin clusters.local.yaml. Template aplicado en .claude/skill-router/clusters.local.yaml con 3 clusters base (dev, deploy, debug). Edita el archivo para añadir triggers propios del proyecto. Para deshabilitar el auto-bootstrap en este proyecto: echo \"%s\" >> ~/.claude/skill-router/bootstrap-blacklist.txt"}}' "$PROJECT_NAME" "$CWD"
