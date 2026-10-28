# Afazeres API

Projeto prático da disciplina **DevOps na Prática**, do curso de Análise e Desenvolvimento de Sistemas da PUCRS Online.

A Afazeres é uma API REST de tarefas escrita em Python com FastAPI. A aplicação é simples de propósito: o foco do projeto é o ciclo DevOps em volta dela, com integração contínua, testes automatizados e infraestrutura como código na AWS.

Rotas, campos do JSON e mensagens de erro da API estão em português.

## Tecnologias

- Python 3.12 e FastAPI
- pytest, Ruff e pip-audit
- GitHub Actions
- Terraform e AWS (VPC, EC2, IAM e CloudWatch)

## Estrutura

```text
aplicacao/            código da API
testes/               testes automatizados
infra/terraform/      infraestrutura da AWS
.github/workflows/    pipeline de CI
Makefile              comandos de desenvolvimento
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

## Testes e qualidade

```bash
make analisar            # Ruff: estilo, erros comuns, regras de segurança e formatação
make testar              # pytest com cobertura mínima de 85%
make auditar             # pip-audit nas dependências
make validar-terraform   # terraform fmt, validate e test
```

## Integração contínua

O pipeline `.github/workflows/ci.yml` roda a cada push e pull request para a `main` e também pode ser disparado manualmente.

| Job | O que faz |
|---|---|
| `analise` | Ruff com regras de estilo, erros comuns e segurança, além da checagem de formatação |
| `testes` | pytest em Python 3.12 e 3.13, com cobertura mínima de 85% e relatórios salvos como artefatos |
| `dependencias` | pip-audit contra a base de vulnerabilidades do PyPI |
| `terraform` | `fmt`, `init`, `validate` e `test` da infraestrutura |

## Infraestrutura

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
  -var='cidrs_ssh_permitidos=["SEU_IP/32"]'
```

Para produção, repita com `terraform workspace new producao` e `-var-file=ambientes/producao.tfvars`.

| Variável | Uso |
|---|---|
| `chave_publica_ssh` | Chave pública instalada na EC2. Obrigatória |
| `cidrs_ssh_permitidos` | IPs liberados na porta 22. Vazio fecha a porta |
| `cidrs_monitoramento_permitidos` | IPs liberados no Grafana (3000) e no Prometheus (9090). Vazio fecha as portas |

A instância `t3.micro` de homologação cabe no nível gratuito da AWS. Ao terminar os testes, rode `terraform destroy` com as mesmas variáveis em cada workspace para não gerar custo.

## Rotas da API

| Método | Rota | Descrição |
|---|---|---|
| GET | `/` | Boas-vindas e versão |
| GET | `/health` | Health check |
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
{"titulo": "Revisar o pipeline", "concluida": false, "id": 1, "criada_em": "2026-10-28T14:30:00Z"}
```

Os erros seguem sempre o mesmo formato:

```json
{"erro": "Dados inválidos", "detalhes": [{"campo": "titulo", "mensagem": "Deve ter pelo menos 1 caractere"}]}
```

```json
{"erro": "Tarefa não encontrada"}
```
