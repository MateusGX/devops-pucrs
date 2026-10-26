.PHONY: instalar analisar testar auditar validar-terraform executar

instalar:
	python -m pip install -r requirements-dev.txt

analisar:
	ruff check aplicacao testes
	ruff format --check aplicacao testes

testar:
	pytest --cov=aplicacao --cov-report=term-missing

auditar:
	pip-audit -r requirements.txt

validar-terraform:
	cd infra/terraform && terraform fmt -check -recursive && terraform init -backend=false && terraform validate && terraform test -test-directory=testes

executar:
	uvicorn aplicacao.main:api --reload --port 8000
