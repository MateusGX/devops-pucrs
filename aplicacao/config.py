"""Configurações lidas de variáveis de ambiente (estilo 12-factor)."""

import os
from dataclasses import dataclass


@dataclass(frozen=True)
class Configuracoes:
    nome: str
    ambiente: str
    versao: str
    nivel_log: str


def carregar_configuracoes() -> Configuracoes:
    return Configuracoes(
        nome=os.getenv("NOME_APP", "afazeres-api"),
        ambiente=os.getenv("AMBIENTE", "desenvolvimento"),
        versao=os.getenv("VERSAO", "0.0.0-dev"),
        nivel_log=os.getenv("NIVEL_LOG", "INFO").upper(),
    )
