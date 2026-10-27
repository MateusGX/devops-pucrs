locals {
  nome = "${var.projeto}-${var.ambiente}"
}

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
}

resource "aws_key_pair" "deploy" {
  key_name   = "${local.nome}-deploy"
  public_key = var.chave_publica_ssh
}

# Permite que o host envie logs e métricas ao CloudWatch e seja acessado pelo SSM.
resource "aws_iam_role" "aplicacao" {
  name = "${local.nome}-ec2"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "cloudwatch" {
  role       = aws_iam_role.aplicacao.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.aplicacao.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "aplicacao" {
  name = "${local.nome}-ec2"
  role = aws_iam_role.aplicacao.name
}

resource "aws_instance" "aplicacao" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.tipo_instancia
  subnet_id              = aws_subnet.publica.id
  vpc_security_group_ids = [aws_security_group.aplicacao.id]
  key_name               = aws_key_pair.deploy.key_name
  iam_instance_profile   = aws_iam_instance_profile.aplicacao.name
  user_data              = file("${path.module}/inicializacao.sh")

  metadata_options {
    http_tokens = "required"
  }

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
    encrypted   = true
  }

  tags = { Name = "${local.nome}-aplicacao" }
}

resource "aws_eip" "aplicacao" {
  instance = aws_instance.aplicacao.id
  domain   = "vpc"

  tags = { Name = "${local.nome}-eip" }
}

resource "aws_cloudwatch_log_group" "aplicacao" {
  name              = "/${var.projeto}/${var.ambiente}/aplicacao"
  retention_in_days = 14
}
