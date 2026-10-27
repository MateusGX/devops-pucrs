import pytest
from fastapi.testclient import TestClient

from aplicacao import main


@pytest.fixture()
def cliente():
    main.repositorio = main.RepositorioTarefas()
    return TestClient(main.api)


def detalhes(resposta):
    return [(d["campo"], d["mensagem"]) for d in resposta.json()["detalhes"]]


def teste_saude_retorna_ok(cliente):
    resposta = cliente.get("/health")
    assert resposta.status_code == 200
    assert resposta.json()["status"] == "ok"
    assert resposta.json()["mensagem"] == "Serviço saudável"


def teste_raiz_da_boas_vindas(cliente):
    assert cliente.get("/").json()["mensagem"] == "Bem-vindo à API Afazeres"


def teste_fluxo_completo_da_tarefa(cliente):
    criada = cliente.post("/tarefas", json={"titulo": "Configurar pipeline"})
    assert criada.status_code == 201
    tarefa_id = criada.json()["id"]
    assert criada.json()["concluida"] is False
    assert "criada_em" in criada.json()

    assert cliente.get(f"/tarefas/{tarefa_id}").json()["titulo"] == "Configurar pipeline"

    atualizada = cliente.put(
        f"/tarefas/{tarefa_id}", json={"titulo": "Configurar pipeline", "concluida": True}
    )
    assert atualizada.json()["concluida"] is True

    assert len(cliente.get("/tarefas").json()) == 1
    removida = cliente.delete(f"/tarefas/{tarefa_id}")
    assert removida.json() == {"mensagem": "Tarefa removida"}
    assert cliente.get(f"/tarefas/{tarefa_id}").status_code == 404


def teste_tarefa_inexistente_retorna_erro(cliente):
    resposta = cliente.get("/tarefas/999")
    assert resposta.status_code == 404
    assert resposta.json() == {"erro": "Tarefa não encontrada"}


def teste_rejeita_titulo_vazio(cliente):
    resposta = cliente.post("/tarefas", json={"titulo": ""})
    assert resposta.status_code == 422
    assert resposta.json()["erro"] == "Dados inválidos"
    assert detalhes(resposta) == [("titulo", "Deve ter pelo menos 1 caractere")]


def teste_rejeita_titulo_longo(cliente):
    resposta = cliente.post("/tarefas", json={"titulo": "x" * 121})
    assert detalhes(resposta) == [("titulo", "Deve ter no máximo 120 caracteres")]


def teste_titulo_e_obrigatorio(cliente):
    resposta = cliente.post("/tarefas", json={"concluida": True})
    assert detalhes(resposta) == [("titulo", "Campo obrigatório")]


def teste_rejeita_concluida_invalida(cliente):
    resposta = cliente.post("/tarefas", json={"titulo": "Revisar", "concluida": "talvez"})
    assert detalhes(resposta) == [("concluida", "Deve ser verdadeiro ou falso")]


def teste_rejeita_id_nao_numerico(cliente):
    resposta = cliente.get("/tarefas/abc")
    assert resposta.status_code == 422
    assert detalhes(resposta) == [("tarefa_id", "Deve ser um número inteiro")]


def teste_rejeita_json_malformado(cliente):
    resposta = cliente.post("/tarefas", content="{titulo", headers={"Content-Type": "application/json"})
    assert resposta.status_code == 422
    assert resposta.json()["detalhes"][0]["mensagem"] == "JSON malformado"


def teste_rota_inexistente_retorna_erro(cliente):
    resposta = cliente.get("/nao-existe")
    assert resposta.status_code == 404
    assert resposta.json() == {"erro": "Recurso não encontrado"}


def teste_metodo_nao_permitido_retorna_erro(cliente):
    resposta = cliente.delete("/tarefas")
    assert resposta.status_code == 405
    assert resposta.json() == {"erro": "Método não permitido"}


def teste_metricas_expoem_contador_de_requisicoes(cliente):
    cliente.get("/health")
    corpo = cliente.get("/metrics").text
    assert "afazeres_requisicoes_http_total" in corpo
