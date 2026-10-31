#!/usr/bin/env bash
# Smoke test pós-deploy: health check, métricas e o ciclo completo de uma tarefa.
# Uso: smoke_test.sh <url-base>
set -euo pipefail
URL="${1:?uso: smoke_test.sh <url-base>}"

SAUDE="$(curl -fsS "$URL/health")"
grep -q '"status":"ok"' <<< "$SAUDE"
echo "health check ok"

METRICAS="$(curl -fsS "$URL/metrics")"
grep -q afazeres_requisicoes_http_total <<< "$METRICAS"
echo "métricas ok"

ID="$(curl -fsS -X POST "$URL/tarefas" -H 'Content-Type: application/json' \
  -d '{"titulo":"smoke test"}' | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')"
curl -fsS "$URL/tarefas/$ID" >/dev/null
curl -fsS -X DELETE "$URL/tarefas/$ID" >/dev/null
echo "ciclo da tarefa ok (id $ID)"
