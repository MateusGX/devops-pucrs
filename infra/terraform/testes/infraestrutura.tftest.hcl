mock_provider "aws" {
  override_data {
    target = data.aws_availability_zones.disponiveis
    values = { names = ["us-east-1a"] }
  }

  override_data {
    target = data.aws_ami.amazon_linux
    values = { id = "ami-0123456789abcdef0" }
  }
}

variables {
  ambiente          = "homologacao"
  chave_publica_ssh = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITeste teste@afazeres"
}

run "somente_http_aberto_por_padrao" {
  command = plan

  assert {
    condition     = length(aws_security_group.aplicacao.ingress) == 1
    error_message = "Sem IPs informados, o grupo de segurança deve ter só a regra de HTTP."
  }

  assert {
    condition     = one(aws_security_group.aplicacao.ingress).from_port == 80
    error_message = "A única porta aberta por padrão deve ser a 80."
  }
}

run "ssh_liberado_somente_para_ips_informados" {
  command = plan

  variables {
    cidrs_ssh_permitidos = ["203.0.113.10/32"]
  }

  assert {
    condition     = one([for regra in aws_security_group.aplicacao.ingress : regra.cidr_blocks if regra.from_port == 22]) == tolist(["203.0.113.10/32"])
    error_message = "A porta 22 deve aceitar apenas os IPs de cidrs_ssh_permitidos."
  }

  assert {
    condition     = !contains([for regra in aws_security_group.aplicacao.ingress : regra.from_port], 3000)
    error_message = "Liberar SSH não pode abrir o Grafana."
  }
}

run "monitoramento_liberado_somente_para_ips_informados" {
  command = plan

  variables {
    cidrs_monitoramento_permitidos = ["203.0.113.10/32"]
  }

  assert {
    condition     = toset([for regra in aws_security_group.aplicacao.ingress : regra.from_port if regra.from_port != 80]) == toset([3000, 9090])
    error_message = "Grafana (3000) e Prometheus (9090) devem ser liberados, e nenhuma outra porta além da 80."
  }
}

run "instancia_segura_e_nomeada_pelo_ambiente" {
  command = plan

  variables {
    ambiente       = "producao"
    tipo_instancia = "t3.small"
  }

  assert {
    condition     = aws_instance.aplicacao.metadata_options[0].http_tokens == "required"
    error_message = "A instância deve exigir IMDSv2."
  }

  assert {
    condition     = aws_instance.aplicacao.root_block_device[0].encrypted
    error_message = "O disco da instância deve ser criptografado."
  }

  assert {
    condition     = aws_instance.aplicacao.tags["Name"] == "afazeres-producao-aplicacao"
    error_message = "Os recursos devem levar o nome do ambiente."
  }

  assert {
    condition     = aws_cloudwatch_log_group.aplicacao.name == "/afazeres/producao/aplicacao"
    error_message = "O grupo de logs deve ser separado por ambiente."
  }
}

run "ambiente_invalido_rejeitado" {
  command = plan

  variables {
    ambiente = "teste"
  }

  expect_failures = [var.ambiente]
}
