#!/usr/bin/env bash
# Faz o deploy de uma imagem da API Afazeres no host atual, com rollback automático para a versão anterior.
#
# Uso: deploy.sh <imagem:tag> <homologacao|producao>
# Um token do registry pode chegar pelo stdin para fazer login no ghcr.io antes do pull.
set -euo pipefail

IMAGEM="${1:?uso: deploy.sh <imagem:tag> <homologacao|producao>}"
AMBIENTE="${2:?uso: deploy.sh <imagem:tag> <homologacao|producao>}"
DIRETORIO="$(cd "$(dirname "$0")" && pwd)"
URL_SAUDE="${URL_SAUDE:-http://localhost/health}"
VERSOES="$DIRETORIO/.versoes"
cd "$DIRETORIO"

registrar() { printf '[deploy %s] %s\n' "$(date -u +%H:%M:%S)" "$*"; }

if [ ! -t 0 ]; then
  TOKEN="$(cat)"
  if [ -n "$TOKEN" ]; then
    echo "$TOKEN" | docker login ghcr.io -u "${USUARIO_REGISTRO:-github}" --password-stdin >/dev/null
    registrar "login feito no ghcr.io"
  fi
fi

# A senha de admin do Grafana é gerada uma vez por host e nunca sai dele.
if [ ! -f .senha_grafana ]; then
  (umask 077 && openssl rand -base64 24 > .senha_grafana)
fi

escrever_env() {
  cat > .env <<ENV
IMAGEM_AFAZERES=$1
VERSAO_AFAZERES=${1##*:}
AMBIENTE=$AMBIENTE
SENHA_ADMIN_GRAFANA=$(cat .senha_grafana)
ENV
  chmod 600 .env
}

saudavel() {
  for _ in $(seq 1 20); do
    if curl -fsS "$URL_SAUDE" >/dev/null 2>&1; then
      return 0
    fi
    sleep 3
  done
  return 1
}

ANTERIOR="$(tail -n 1 "$VERSOES" 2>/dev/null || true)"
registrar "deploy de $IMAGEM em $AMBIENTE (anterior: ${ANTERIOR:-nenhuma})"

escrever_env "$IMAGEM"
docker compose pull api
docker compose up -d --remove-orphans

if saudavel; then
  echo "$IMAGEM" >> "$VERSOES"
  registrar "versão saudável: $IMAGEM"
  docker image prune -f >/dev/null
  docker logout ghcr.io >/dev/null 2>&1 || true
  exit 0
fi

registrar "health check falhou para $IMAGEM"
if [ -n "$ANTERIOR" ]; then
  registrar "rollback para $ANTERIOR"
  escrever_env "$ANTERIOR"
  docker compose up -d api
  if saudavel; then
    registrar "versão anterior restaurada: $ANTERIOR"
  else
    registrar "a versão anterior também falhou, é preciso agir manualmente"
  fi
fi
docker logout ghcr.io >/dev/null 2>&1 || true
exit 1
