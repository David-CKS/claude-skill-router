#!/usr/bin/env bash
# setup-router-project.sh — Bootstrap clusters.local.yaml para un proyecto Claude Code
#
# Uso:
#   cd ~/Desktop/mi-proyecto-nuevo
#   bash ~/.claude/skill-router/bin/setup-router-project.sh
#
# Qué hace:
#   1. Crea .claude/skill-router/ en el cwd actual
#   2. Pone un clusters.local.yaml plantilla (3 clusters básicos: dev, deploy, debug)
#   3. Verifica con --status del router que se carga
#   4. Imprime instrucciones de cómo añadir más clusters
#
# Idempotente: si clusters.local.yaml ya existe, NO sobrescribe. Solo verifica.
#
# Flags:
#   --force    Sobrescribe clusters.local.yaml existente (con backup .bak)
#   --no-git   No añade nada a .gitignore (default: añade .claude/skill-router/state/)
#   -h         Help

set -euo pipefail

PROJECT_ROOT="$(pwd)"
PROJECT_NAME="$(basename "$PROJECT_ROOT")"
TARGET_DIR="${PROJECT_ROOT}/.claude/skill-router"
TARGET_YAML="${TARGET_DIR}/clusters.local.yaml"
FORCE=0
NO_GIT=0

# Parse flags
while [ $# -gt 0 ]; do
  case "$1" in
    --force) FORCE=1 ;;
    --no-git) NO_GIT=1 ;;
    -h|--help)
      sed -n '2,18p' "$0"
      exit 0
      ;;
    *) echo "[error] flag desconocido: $1" >&2; exit 2 ;;
  esac
  shift
done

echo "=== setup-router-project ==="
echo "Proyecto:  $PROJECT_NAME"
echo "Path:      $PROJECT_ROOT"
echo ""

# Sanity check: router instalado?
if [ ! -f "$HOME/.claude/skill-router/v2/trigger_v2.py" ]; then
  echo "[error] Router no instalado en ~/.claude/skill-router/v2/" >&2
  echo "        Instala primero con: npx skills add David-CKS/claude-skill-router -g -y" >&2
  exit 1
fi

# Crear dir
mkdir -p "$TARGET_DIR"

# Comprobar yaml existente
if [ -f "$TARGET_YAML" ] && [ "$FORCE" -eq 0 ]; then
  echo "[skip] clusters.local.yaml ya existe."
  echo "       Usa --force para sobrescribir (creará backup .bak)."
  echo ""
  echo "[verify] testeando que el router lo carga..."
  python3 "$HOME/.claude/skill-router/v2/trigger_v2.py" --status 2>&1 \
    | grep -E "clusters_loaded|local_yaml" || true
  exit 0
fi

# Backup si --force
if [ -f "$TARGET_YAML" ] && [ "$FORCE" -eq 1 ]; then
  BACKUP="$TARGET_YAML.bak-$(date +%Y%m%d-%H%M%S)"
  cp "$TARGET_YAML" "$BACKUP"
  echo "[backup] $BACKUP"
fi

# Plantilla mínima nivel dios (3 clusters básicos cualquier proyecto)
cat > "$TARGET_YAML" <<EOF
# ${PROJECT_NAME} — Clusters locales del skill router
#
# Triggers semánticos específicos de este proyecto.
# El router (~/.claude/skill-router/v2/trigger_v2.py) sube desde cwd hasta home
# buscando este fichero y mergea con clusters.yaml global (local wins por id).
#
# Para añadir un cluster nuevo:
#   1. Define id único en snake_case
#   2. description: 1 línea qué cubre
#   3. triggers_natural: frases que dirías tú EN CASTELLANO (no inglés salvo
#      que sea jerga técnica). Incluye sinónimos, vulgarismos, abreviaciones.
#   4. skills: nombres exactos de SKILL.md (campo "name:" del frontmatter)
#   5. confidence_threshold: 0.5 (laxo) a 0.8 (estricto). Default 0.7.
#
# Verificar después de editar:
#   python3 ~/.claude/skill-router/v2/trigger_v2.py --status
#
# Generado por setup-router-project.sh el $(date +%Y-%m-%d).

clusters:
  ${PROJECT_NAME//-/_}_dev:
    description: "Desarrollo general en ${PROJECT_NAME}: implementar features, escribir código, refactor."
    triggers_natural:
      - "implementa"
      - "añade"
      - "refactoriza"
      - "haz que"
      - "crea funcion"
      - "crea función"
      - "nuevo endpoint"
      - "nueva pantalla"
    skills:
      - verification-before-completion
      - commit-work
    confidence_threshold: 0.7

  ${PROJECT_NAME//-/_}_deploy:
    description: "Deploy de ${PROJECT_NAME}: push a main, merge, release a producción."
    triggers_natural:
      - "deploy"
      - "deployar"
      - "push main"
      - "merge main"
      - "tirar a prod"
      - "tirar a producción"
      - "release"
      - "publicar"
    skills:
      - verification-before-completion
      - commit-work
    confidence_threshold: 0.7

  ${PROJECT_NAME//-/_}_debug:
    description: "Debug de ${PROJECT_NAME}: bugs, regresiones, errores consola."
    triggers_natural:
      - "hay un bug"
      - "no funciona"
      - "no carga"
      - "se ha roto"
      - "casca"
      - "petó"
      - "regresión"
      - "regresion"
      - "fix"
    skills:
      - systematic-debugging
      - verification-before-completion
    confidence_threshold: 0.65

settings:
  source: "local"
  project: "${PROJECT_NAME}"
  scope: "${PROJECT_ROOT}"
  merge_strategy: "local-wins-by-id"
EOF

echo "[create] $TARGET_YAML"
echo ""

# .gitignore (opcional)
if [ "$NO_GIT" -eq 0 ] && [ -d "$PROJECT_ROOT/.git" ]; then
  GITIGNORE="$PROJECT_ROOT/.gitignore"
  if [ -f "$GITIGNORE" ]; then
    if ! grep -q "^\.claude/skill-router/state" "$GITIGNORE" 2>/dev/null; then
      printf '\n# Skill router state (no versionar)\n.claude/skill-router/state/\n' >> "$GITIGNORE"
      echo "[gitignore] añadido .claude/skill-router/state/"
    fi
  fi
fi

# Validar YAML
echo "[verify] validando YAML..."
python3 -c "
import yaml
with open('$TARGET_YAML') as f:
    data = yaml.safe_load(f)
print(f'[ok] {len(data[\"clusters\"])} clusters declarados:')
for cid in data['clusters'].keys():
    print(f'     - {cid}')
"
echo ""

# Test router lo detecta
echo "[verify] router detecta clusters locales..."
python3 "$HOME/.claude/skill-router/v2/trigger_v2.py" --status 2>&1 \
  | grep -E "clusters_loaded|local_yaml" || true
echo ""

# Instrucciones siguientes
cat <<INSTRUCTIONS
[done] Setup completado.

Siguientes pasos:
  1. Edita $TARGET_YAML para añadir clusters propios del proyecto.
  2. Cuando termines:
       git add .claude/skill-router/clusters.local.yaml
       git commit -m "config: clusters router para auto-activar skills"
       git push
  3. Cualquier sesión Claude Code abierta en este proyecto detectará los
     clusters automático. No requiere restart ni instalación adicional.

Verificación rápida:
  python3 ~/.claude/skill-router/v2/trigger_v2.py --status

Plantillas disponibles para inspirarte:
  ~/Desktop/cks-system/.claude/skill-router/clusters.local.yaml   (12 clusters cks-*)
  ~/Desktop/OPENCLAW/.claude/skill-router/clusters.local.yaml     (16 clusters openclaw-*)
  ~/.claude/skill-router/v2/clusters.yaml                         (18 clusters globales)
INSTRUCTIONS
