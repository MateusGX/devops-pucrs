#!/usr/bin/env bash
# Chamado pelo pipeline de CD: envia o pacote de deploy para um host e executa o deploy.sh lá.
# Variáveis: SERVIDOR_DEPLOY, CHAVE_SSH_DEPLOY, TOKEN_REGISTRO, USUARIO_REGISTRO
# Uso: deploy_remoto.sh <imagem:tag> <homologacao|producao>
set -euo pipefail
IMAGEM="${1:?uso: deploy_remoto.sh <imagem:tag> <homologacao|producao>}"
AMBIENTE="${2:?uso: deploy_remoto.sh <imagem:tag> <homologacao|producao>}"
DESTINO="ec2-user@${SERVIDOR_DEPLOY:?SERVIDOR_DEPLOY é obrigatório}"
cd "$(dirname "$0")/.."

CHAVE="$(mktemp)"
PACOTE="$(mktemp -d)"
trap 'rm -rf "$CHAVE" "$PACOTE"' EXIT
printf '%s\n' "${CHAVE_SSH_DEPLOY:?CHAVE_SSH_DEPLOY é obrigatório}" > "$CHAVE"
chmod 600 "$CHAVE"

mkdir -p ~/.ssh
ssh-keyscan -H "$SERVIDOR_DEPLOY" >> ~/.ssh/known_hosts 2>/dev/null
SSH=(ssh -i "$CHAVE" -o BatchMode=yes "$DESTINO")

cp -r deploy/docker-compose.yml deploy/ambientes monitoramento scripts/deploy.sh scripts/rollback.sh "$PACOTE/"
tar -C "$PACOTE" -czf - . | "${SSH[@]}" 'mkdir -p /opt/afazeres && tar -C /opt/afazeres -xzf -'

printf '%s' "${TOKEN_REGISTRO:-}" | "${SSH[@]}" \
  "USUARIO_REGISTRO='${USUARIO_REGISTRO:-github}' /opt/afazeres/deploy.sh '$IMAGEM' '$AMBIENTE'"
