# Project Bootstrap — Auto-aplicar clusters.local.yaml en proyectos nuevos

Dos scripts en `bin/` que automatizan la creación de `clusters.local.yaml`
per-proyecto, evitando tener que recordar configurar cada uno manualmente.

## bin/setup-router-project.sh

Script invocado a mano para arrancar un proyecto nuevo.

```bash
cd ~/Desktop/mi-proyecto-nuevo
bash ~/.claude/skill-router/bin/setup-router-project.sh
```

Qué hace:
- Crea `.claude/skill-router/` en el cwd
- Genera `clusters.local.yaml` con 3 clusters base (`<nombre>_dev`, `<nombre>_deploy`, `<nombre>_debug`)
- Valida el YAML
- Verifica que el router lo detecta con `--status`
- Añade `.claude/skill-router/state/` al `.gitignore` si existe `.git`

Idempotente: si `clusters.local.yaml` ya existe, NO sobrescribe (usar `--force` para regenerar con backup).

## bin/auto-bootstrap-project.sh

Hook SessionStart silencioso que ejecuta `setup-router-project.sh` automático.

Se registra en `~/.claude/settings.json`:

```json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {"type": "command", "command": "/Users/<user>/.claude/skill-router/bin/auto-bootstrap-project.sh"}
        ]
      }
    ]
  }
}
```

Condiciones de activación (TODAS):
1. `cwd` está bajo `$HOME/Desktop/` (no `/tmp`, no `/`)
2. `cwd` tiene `.git/` (es repo git)
3. `cwd` NO tiene `.claude/skill-router/clusters.local.yaml` (no bootstrapped)
4. `cwd` NO está en blacklist (`~/.claude/skill-router/bootstrap-blacklist.txt`)

Si todas se cumplen → ejecuta el setup silencioso.

## Blacklist por proyecto

Si en algún proyecto NO quieres auto-bootstrap:

```bash
echo "$PWD" >> ~/.claude/skill-router/bootstrap-blacklist.txt
```

El hook lo respeta para futuras sesiones.

## Tests

Los 4 escenarios (cwd fuera Desktop / sin git / con git sin yaml / idempotente) pasan en local.
Test reproducible:

```bash
SANDBOX="$HOME/Desktop/_test-bootstrap-$$"
mkdir -p "$SANDBOX" && cd "$SANDBOX" && git init --quiet
bash ~/.claude/skill-router/bin/auto-bootstrap-project.sh
ls -la .claude/skill-router/clusters.local.yaml  # debe existir
rm -rf "$SANDBOX"
```
