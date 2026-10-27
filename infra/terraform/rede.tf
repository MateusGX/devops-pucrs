data "aws_availability_zones" "disponiveis" {
  state = "available"
}

resource "aws_vpc" "principal" {
  cidr_block           = var.cidr_vpc
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${local.nome}-vpc" }
}

resource "aws_internet_gateway" "principal" {
  vpc_id = aws_vpc.principal.id

  tags = { Name = "${local.nome}-igw" }
}

resource "aws_subnet" "publica" {
  vpc_id                  = aws_vpc.principal.id
  cidr_block              = var.cidr_subrede_publica
  availability_zone       = data.aws_availability_zones.disponiveis.names[0]
  map_public_ip_on_launch = true

  tags = { Name = "${local.nome}-subrede-publica" }
}

resource "aws_route_table" "publica" {
  vpc_id = aws_vpc.principal.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.principal.id
  }

  tags = { Name = "${local.nome}-rotas-publicas" }
}

resource "aws_route_table_association" "publica" {
  subnet_id      = aws_subnet.publica.id
  route_table_id = aws_route_table.publica.id
}

resource "aws_security_group" "aplicacao" {
  name        = "${local.nome}-aplicacao"
  description = "Host da API Afazeres"
  vpc_id      = aws_vpc.principal.id

  ingress {
    description = "HTTP da API"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  dynamic "ingress" {
    for_each = length(var.cidrs_ssh_permitidos) > 0 ? [1] : []
    content {
      description = "SSH do pipeline de CD"
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = var.cidrs_ssh_permitidos
    }
  }

  dynamic "ingress" {
    for_each = length(var.cidrs_monitoramento_permitidos) > 0 ? [3000, 9090] : []
    content {
      description = "Monitoramento (Grafana e Prometheus)"
      from_port   = ingress.value
      to_port     = ingress.value
      protocol    = "tcp"
      cidr_blocks = var.cidrs_monitoramento_permitidos
    }
  }

  egress {
    description = "Todo trafego de saida"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.nome}-sg-aplicacao" }
}
