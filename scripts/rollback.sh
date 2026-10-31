#!/usr/bin/env bash
# Rollback manual: faz o deploy de novo da versão anterior à atual.
# Uso: rollback.sh <homologacao|producao>
set -euo pipefail
AMBIENTE="${1:?uso: rollback.sh <homologacao|producao>}"
DIRETORIO="$(cd "$(dirname "$0")" && pwd)"
VERSOES="$DIRETORIO/.versoes"

TOTAL=0
[ -f "$VERSOES" ] && TOTAL="$(wc -l < "$VERSOES")"
[ "$TOTAL" -ge 2 ] || { echo "nenhuma versão anterior registrada"; exit 1; }
ALVO="$(tail -n 2 "$VERSOES" | head -n 1)"

# Tira a versão atual e o alvo do histórico. O deploy.sh registra o alvo de novo quando ele sobe saudável.
awk -v manter="$((TOTAL - 2))" 'NR <= manter' "$VERSOES" > "$VERSOES.tmp" && mv "$VERSOES.tmp" "$VERSOES"

echo "rollback para $ALVO"
"$DIRETORIO/deploy.sh" "$ALVO" "$AMBIENTE" </dev/null
