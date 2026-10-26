"""API Afazeres: serviço simples de tarefas usado para exercitar o pipeline DevOps."""

import json
import logging
import sys
import threading
import time
from datetime import UTC, datetime
from http import HTTPStatus
from itertools import count

from fastapi import FastAPI, HTTPException, Request, Response
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from prometheus_client import CONTENT_TYPE_LATEST, Counter, Histogram, generate_latest
from pydantic import BaseModel, Field
from starlette.exceptions import HTTPException as StarletteHTTPException

from aplicacao.config import carregar_configuracoes

config = carregar_configuracoes()

BOAS_VINDAS = "Bem-vindo à API Afazeres"
SERVICO_SAUDAVEL = "Serviço saudável"
TAREFA_NAO_ENCONTRADA = "Tarefa não encontrada"
TAREFA_REMOVIDA = "Tarefa removida"
DADOS_INVALIDOS = "Dados inválidos"

ERROS_HTTP = {
    400: "Requisição inválida",
    404: "Recurso não encontrado",
    405: "Método não permitido",
    500: "Erro interno do servidor",
}


class FormatadorJson(logging.Formatter):
    """Um objeto JSON por linha, pronto para agregadores de logs (Loki, CloudWatch)."""

    def format(self, entrada: logging.LogRecord) -> str:
        registro = {
            "data_hora": datetime.now(UTC).isoformat(),
            "nivel": entrada.levelname,
            "origem": entrada.name,
            "mensagem": entrada.getMessage(),
            "ambiente": config.ambiente,
            "versao": config.versao,
        }
        registro.update(getattr(entrada, "campos_extras", {}))
        return json.dumps(registro, ensure_ascii=False)


saida_logs = logging.StreamHandler(sys.stdout)
saida_logs.setFormatter(FormatadorJson())
registrador = logging.getLogger("afazeres")
registrador.handlers = [saida_logs]
registrador.setLevel(config.nivel_log)
registrador.propagate = False

REQUISICOES = Counter("afazeres_requisicoes_http", "Requisições HTTP", ["metodo", "rota", "status"])
LATENCIA = Histogram(
    "afazeres_duracao_requisicao_segundos", "Latência das requisições HTTP", ["metodo", "rota"]
)


class TarefaEntrada(BaseModel):
    titulo: str = Field(min_length=1, max_length=120)
    concluida: bool = False


class Tarefa(TarefaEntrada):
    id: int
    criada_em: datetime


class RepositorioTarefas:
    """Repositório em memória e seguro entre threads (trocar por um banco de dados em produção)."""

    def __init__(self) -> None:
        self._tarefas: dict[int, Tarefa] = {}
        self._ids = count(1)
        self._trava = threading.Lock()

    def listar(self) -> list[Tarefa]:
        with self._trava:
            return list(self._tarefas.values())

    def obter(self, tarefa_id: int) -> Tarefa | None:
        with self._trava:
            return self._tarefas.get(tarefa_id)

    def criar(self, dados: TarefaEntrada) -> Tarefa:
        with self._trava:
            tarefa = Tarefa(id=next(self._ids), criada_em=datetime.now(UTC), **dados.model_dump())
            self._tarefas[tarefa.id] = tarefa
            return tarefa

    def atualizar(self, tarefa_id: int, dados: TarefaEntrada) -> Tarefa | None:
        with self._trava:
            atual = self._tarefas.get(tarefa_id)
            if atual is None:
                return None
            tarefa = atual.model_copy(update=dados.model_dump())
            self._tarefas[tarefa_id] = tarefa
            return tarefa

    def remover(self, tarefa_id: int) -> bool:
        with self._trava:
            return self._tarefas.pop(tarefa_id, None) is not None


def plural(n: int, singular: str, varios: str) -> str:
    return f"{n} {singular if n == 1 else varios}"


def mensagem_validacao(erro: dict) -> str:
    tipo, ctx = erro.get("type", ""), erro.get("ctx") or {}
    if tipo == "missing":
        return "Campo obrigatório"
    if tipo == "string_too_short":
        return f"Deve ter pelo menos {plural(ctx.get('min_length', 1), 'caractere', 'caracteres')}"
    if tipo == "string_too_long":
        return f"Deve ter no máximo {plural(ctx.get('max_length', 0), 'caractere', 'caracteres')}"
    if tipo in ("string_type", "string_unicode"):
        return "Deve ser um texto"
    if tipo in ("bool_parsing", "bool_type"):
        return "Deve ser verdadeiro ou falso"
    if tipo in ("int_parsing", "int_type", "int_from_float"):
        return "Deve ser um número inteiro"
    if tipo == "json_invalid":
        return "JSON malformado"
    if tipo in ("model_attributes_type", "dict_type", "model_type"):
        return "Deve ser um objeto JSON"
    return "Valor inválido"


def nome_do_campo(localizacao: tuple) -> str:
    partes = [str(p) for p in localizacao if p not in ("body", "path", "query", "header")]
    return ".".join(partes) or "corpo"


api = FastAPI(
    title="Afazeres API",
    description="API de tarefas usada para exercitar o ciclo DevOps.",
    version=config.versao,
)
repositorio = RepositorioTarefas()


@api.exception_handler(StarletteHTTPException)
async def erro_http(requisicao: Request, excecao: StarletteHTTPException):
    padrao = HTTPStatus(excecao.status_code).phrase
    mensagem = (
        excecao.detail
        if excecao.detail and excecao.detail != padrao
        else ERROS_HTTP.get(excecao.status_code, padrao)
    )
    return JSONResponse(
        {"erro": mensagem}, status_code=excecao.status_code, headers=getattr(excecao, "headers", None)
    )


@api.exception_handler(RequestValidationError)
async def erro_validacao(requisicao: Request, excecao: RequestValidationError):
    detalhes = [
        {"campo": nome_do_campo(erro.get("loc", ())), "mensagem": mensagem_validacao(erro)}
        for erro in excecao.errors()
    ]
    return JSONResponse({"erro": DADOS_INVALIDOS, "detalhes": detalhes}, status_code=422)


@api.middleware("http")
async def observar(requisicao: Request, proxima):
    inicio = time.perf_counter()
    resposta = await proxima(requisicao)
    duracao = time.perf_counter() - inicio
    rota = requisicao.scope.get("route")
    caminho = rota.path if rota else "desconhecida"
    REQUISICOES.labels(requisicao.method, caminho, resposta.status_code).inc()
    LATENCIA.labels(requisicao.method, caminho).observe(duracao)
    registrador.info(
        "requisicao",
        extra={
            "campos_extras": {
                "metodo": requisicao.method,
                "rota": caminho,
                "status": resposta.status_code,
                "duracao_ms": round(duracao * 1000, 2),
            }
        },
    )
    return resposta


@api.get("/", summary="Boas-vindas")
def boas_vindas():
    return {"mensagem": BOAS_VINDAS, "versao": config.versao}


@api.get("/health", summary="Health check")
def saude():
    return {
        "status": "ok",
        "mensagem": SERVICO_SAUDAVEL,
        "ambiente": config.ambiente,
        "versao": config.versao,
    }


@api.get("/metrics", summary="Métricas no formato Prometheus")
def metricas():
    return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)


@api.get("/tarefas", response_model=list[Tarefa], summary="Lista as tarefas")
def listar_tarefas():
    return repositorio.listar()


@api.post("/tarefas", response_model=Tarefa, status_code=201, summary="Cria uma tarefa")
def criar_tarefa(dados: TarefaEntrada):
    return repositorio.criar(dados)


@api.get("/tarefas/{tarefa_id}", response_model=Tarefa, summary="Consulta uma tarefa")
def obter_tarefa(tarefa_id: int):
    tarefa = repositorio.obter(tarefa_id)
    if tarefa is None:
        raise HTTPException(404, TAREFA_NAO_ENCONTRADA)
    return tarefa


@api.put("/tarefas/{tarefa_id}", response_model=Tarefa, summary="Atualiza uma tarefa")
def atualizar_tarefa(tarefa_id: int, dados: TarefaEntrada):
    tarefa = repositorio.atualizar(tarefa_id, dados)
    if tarefa is None:
        raise HTTPException(404, TAREFA_NAO_ENCONTRADA)
    return tarefa


@api.delete("/tarefas/{tarefa_id}", summary="Remove uma tarefa")
def remover_tarefa(tarefa_id: int):
    if not repositorio.remover(tarefa_id):
        raise HTTPException(404, TAREFA_NAO_ENCONTRADA)
    return {"mensagem": TAREFA_REMOVIDA}
