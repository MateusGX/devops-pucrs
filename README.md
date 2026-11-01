# Afazeres API

Projeto prático da disciplina **DevOps na Prática**, do curso de Análise e Desenvolvimento de Sistemas da PUCRS Online.

A Afazeres é uma API REST de tarefas escrita em Python com FastAPI. A aplicação é simples de propósito: o foco do projeto é o ciclo DevOps em volta dela. O trabalho foi entregue em duas fases:

| Fase | Entregas | Seção |
|---|---|---|
| 1 | Repositório, testes automatizados, pipeline de CI e infraestrutura como código na AWS | [Fase 1](#fase-1-integração-contínua-e-infraestrutura-como-código) |
| 2 | Containers, pipeline de CD com deploy e rollback, monitoramento e segurança | [Fase 2](#fase-2-containers-entrega-contínua-e-monitoramento) |

Rotas, campos do JSON e mensagens de erro da API estão em português.

## Tecnologias

| Fase | Ferramentas |
|---|---|
| 1 | Python 3.12, FastAPI, pytest, Ruff, pip-audit, GitHub Actions, Terraform e AWS (VPC, EC2, IAM e CloudWatch) |
| 2 | Docker, Docker Compose, GitHub Container Registry (GHCR), Prometheus, Grafana, Trivy e OWASP ZAP |

## Estrutura

```text
aplicacao/            código da API                                    fase 1
testes/               testes automatizados                             fase 1
infra/terraform/      infraestrutura da AWS                            fase 1
.github/workflows/    ci.yml (fase 1) e cd.yml (fase 2)
Makefile              comandos de desenvolvimento                      fase 1
Dockerfile            imagem da API                                    fase 2
docker-compose.yml    ambiente local com API, Prometheus e Grafana     fase 2
deploy/               compose e variáveis dos servidores por ambiente  fase 2
scripts/              deploy, rollback e smoke test                    fase 2
monitoramento/        Prometheus, regras de alerta e Grafana           fase 2
```

## Como rodar

Pré-requisitos: Python 3.12 ou superior e Make.

```bash
git clone https://github.com/MateusGX/devops-pucrs.git
cd devops-pucrs
python -m venv .venv
source .venv/bin/activate
make instalar
make executar
```

A API sobe em http://localhost:8000 e a documentação interativa fica em http://localhost:8000/docs.

Para rodar com Docker, veja [Containers](#containers).

## Fase 1: integração contínua e infraestrutura como código

### Testes e qualidade

```bash
make analisar            # Ruff: estilo, erros comuns, regras de segurança e formatação
make testar              # pytest com cobertura mínima de 85%
make auditar             # pip-audit nas dependências
make validar-terraform   # terraform fmt, validate e test
```

### Pipeline de CI

O pipeline `.github/workflows/ci.yml` roda a cada push e pull request para a `main` e também pode ser disparado manualmente.

| Job | O que faz |
|---|---|
| `analise` | Ruff com regras de estilo, erros comuns e segurança, além da checagem de formatação |
| `testes` | pytest em Python 3.12 e 3.13, com cobertura mínima de 85% e relatórios salvos como artefatos |
| `dependencias` | pip-audit contra a base de vulnerabilidades do PyPI |
| `terraform` | `fmt`, `init`, `validate` e `test` da infraestrutura |

### Infraestrutura

O Terraform em `infra/terraform/` cria, para cada ambiente, uma VPC com sub-rede pública, gateway de internet, grupo de segurança, uma EC2 com Amazon Linux 2023, IP elástico, papel IAM e um grupo de logs no CloudWatch. Homologação e produção usam o mesmo código, com os valores de cada um em `infra/terraform/ambientes/`.

| Arquivo | Conteúdo |
|---|---|
| `rede.tf` | VPC, sub-rede, gateway, rotas e grupo de segurança |
| `computacao.tf` | EC2, IP elástico, papel IAM e grupo de logs |
| `variaveis.tf` | Variáveis de entrada, com validação do ambiente |
| `saidas.tf` | IP público, URL da API, comando SSH e grupo de logs |
| `versoes.tf` | Versões fixadas e etiquetas padrão |
| `inicializacao.sh` | Instala o Docker e o Compose no primeiro boot da EC2 |
| `ambientes/*.tfvars` | Tipo de instância e endereçamento de cada ambiente |
| `testes/*.tftest.hcl` | Testes da infraestrutura com o provider da AWS simulado |

Os testes executam o `plan` com o provider da AWS simulado, sem credenciais nem custo, e verificam as regras do grupo de segurança, o IMDSv2, a criptografia do disco, os nomes por ambiente e a validação do ambiente.

Pré-requisitos: Terraform 1.7 ou superior, credenciais da AWS configuradas e um par de chaves SSH (`ssh-keygen -t ed25519 -f ~/.ssh/afazeres`).

Cada ambiente usa um workspace próprio, para que os estados não se misturem:

```bash
cd infra/terraform
terraform init
terraform workspace new homologacao
terraform apply -var-file=ambientes/homologacao.tfvars \
  -var="chave_publica_ssh=$(cat ~/.ssh/afazeres.pub)" \
  -var='cidrs_ssh_permitidos=["0.0.0.0/0"]' \
  -var='cidrs_monitoramento_permitidos=["SEU_IP/32"]'
```

Para produção, repita com `terraform workspace new producao` e `-var-file=ambientes/producao.tfvars`.

| Variável | Uso |
|---|---|
| `chave_publica_ssh` | Chave pública instalada na EC2. Obrigatória |
| `cidrs_ssh_permitidos` | IPs liberados na porta 22. Vazio fecha a porta |
| `cidrs_monitoramento_permitidos` | IPs liberados no Grafana (3000) e no Prometheus (9090). Vazio fecha as portas |

O deploy da Fase 2 entra na EC2 por SSH a partir dos runners do GitHub Actions, cujos IPs mudam a cada execução. Por isso o exemplo libera a porta 22 para qualquer origem. O acesso continua restrito à chave SSH, sem login por senha. Em cenários sem deploy automatizado, recomenda-se restringir a porta 22 ao IP do administrador, por exemplo `["SEU_IP/32"]`.

A instância `t3.micro` de homologação cabe no nível gratuito da AWS. Ao terminar os testes, rode `terraform destroy` com as mesmas variáveis em cada workspace para não gerar custo.

## Fase 2: containers, entrega contínua e monitoramento

### Containers

Pré-requisito: Docker com o plugin Compose.

```bash
docker compose up -d --build
./scripts/smoke_test.sh http://localhost:8000
```

| Serviço | Endereço |
|---|---|
| API | http://localhost:8000 |
| Prometheus | http://localhost:9090 |
| Grafana | http://localhost:3000 (usuário `admin`, senha `admin`) |

O build da imagem é feito em dois estágios a partir de `python:3.12-slim`. O container roda com usuário sem privilégio e tem health check em `/health`.

### Pipeline de CD

O pipeline `.github/workflows/cd.yml` roda quando o CI termina com sucesso na `main` e também pode ser disparado manualmente.

| Job | O que faz |
|---|---|
| `imagem` | Build da imagem Docker com o hash do commit como tag, varredura com Trivy (bloqueia vulnerabilidades críticas com correção disponível), smoke test e push para o GHCR |
| `seguranca-dinamica` | Varredura com OWASP ZAP contra a imagem publicada, com o relatório salvo como artefato |
| `deploy-homologacao` | Deploy automático em homologação, com health check, rollback automático e smoke test |
| `deploy-producao` | Deploy em produção depois da aprovação de um revisor |

Para ativar os deploys:

1. Provisione os dois ambientes com o Terraform (veja [Infraestrutura](#infraestrutura)).
2. Nas configurações do repositório no GitHub, crie os ambientes `homologacao` e `producao`.
3. Em cada ambiente, cadastre os segredos:
   - `SERVIDOR_DEPLOY`: saída `ip_publico` do Terraform daquele ambiente.
   - `CHAVE_SSH_DEPLOY`: chave privada do par cuja chave pública foi passada em `chave_publica_ssh`.
4. Em `producao`, adicione um revisor obrigatório.

Enquanto os segredos não existirem, o CD faz o build, a varredura e o push da imagem e pula os deploys com um aviso.

### Deploy manual e rollback

```bash
export SERVIDOR_DEPLOY=IP_DO_SERVIDOR
export CHAVE_SSH_DEPLOY="$(cat ~/.ssh/afazeres)"
./scripts/deploy_remoto.sh ghcr.io/mateusgx/afazeres-api:COMMIT homologacao
```

Se a imagem no GHCR for privada, exporte também `USUARIO_REGISTRO` e `TOKEN_REGISTRO`, um token com permissão `read:packages`.

O `deploy_remoto.sh` copia o compose, as variáveis do ambiente, o monitoramento e os scripts para `/opt/afazeres` e executa o `deploy.sh` no servidor. O `deploy.sh` guarda o histórico de versões em `/opt/afazeres/.versoes`. Se o health check não responder em 60 segundos, ele faz o rollback sozinho para a versão anterior. Para fazer o rollback manualmente, rode no servidor:

```bash
/opt/afazeres/rollback.sh homologacao
```

### Monitoramento

- O Prometheus coleta `/metrics` a cada 15 segundos.
- As regras em `monitoramento/alertas.yml` disparam quando a API fica fora do ar por mais de 1 minuto, quando os erros 5xx passam de 5% e quando a latência p95 passa de 500 ms.
- O Grafana sobe ligado ao Prometheus e com o painel **Afazeres API**.
- Nos servidores, o Grafana e o Prometheus ficam nas portas 3000 e 9090, liberadas só para `cidrs_monitoramento_permitidos`. A senha de admin do Grafana é gerada no primeiro deploy e fica em `/opt/afazeres/.senha_grafana`.
- Os logs JSON da API vão para o CloudWatch, no grupo `/afazeres/AMBIENTE/aplicacao`.

### Segurança

- Análise estática com as regras Bandit do Ruff e dependências verificadas com pip-audit, desde a Fase 1.
- Dependências atualizadas pelo Dependabot.
- Imagem verificada com Trivy e aplicação em execução testada com OWASP ZAP.
- Nenhum segredo no repositório. Credenciais ficam nos segredos do GitHub.
- Cada job do GitHub Actions recebe só as permissões que usa.
- EC2 com disco criptografado e IMDSv2 obrigatório.

## Rotas da API

| Método | Rota | Descrição |
|---|---|---|
| GET | `/` | Boas-vindas e versão |
| GET | `/health` | Health check usado pelo Docker e pelo deploy |
| GET | `/metrics` | Métricas no formato Prometheus |
| GET, POST | `/tarefas` | Lista e cria tarefas |
| GET, PUT, DELETE | `/tarefas/{id}` | Consulta, atualiza e remove uma tarefa |

### Exemplo de uso

```bash
curl -X POST http://localhost:8000/tarefas \
  -H 'Content-Type: application/json' \
  -d '{"titulo": "Revisar o pipeline"}'
```

```json
{"titulo": "Revisar o pipeline", "concluida": false, "id": 1, "criada_em": "2026-10-31T23:10:00Z"}
```

Os erros seguem sempre o mesmo formato:

```json
{"erro": "Dados inválidos", "detalhes": [{"campo": "titulo", "mensagem": "Deve ter pelo menos 1 caractere"}]}
```

```json
{"erro": "Tarefa não encontrada"}
```
