# syntax=docker/dockerfile:1

# ---- estágio de build: instala as dependências num virtualenv isolado
FROM python:3.15-slim AS build
ENV PIP_NO_CACHE_DIR=1 PIP_DISABLE_PIP_VERSION_CHECK=1
WORKDIR /build
COPY requirements.txt .
RUN python -m venv /opt/venv && /opt/venv/bin/pip install -r requirements.txt

# ---- estágio final: imagem enxuta, usuário sem privilégio e health check
FROM python:3.15-slim
ARG VERSAO=0.0.0-dev
LABEL org.opencontainers.image.title="afazeres-api" \
      org.opencontainers.image.description="Afazeres API (DevOps na Prática)" \
      org.opencontainers.image.version="${VERSAO}"
ENV PATH=/opt/venv/bin:$PATH \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    VERSAO=${VERSAO}
RUN useradd --create-home --uid 10001 aplicacao
WORKDIR /srv
COPY --from=build /opt/venv /opt/venv
COPY aplicacao ./aplicacao
USER aplicacao
EXPOSE 8000
HEALTHCHECK --interval=15s --timeout=3s --start-period=10s --retries=3 \
  CMD python -c "import sys, urllib.request; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8000/health', timeout=2).status == 200 else 1)"
CMD ["uvicorn", "aplicacao.main:api", "--host", "0.0.0.0", "--port", "8000", "--proxy-headers"]
