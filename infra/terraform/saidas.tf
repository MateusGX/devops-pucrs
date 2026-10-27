output "ip_publico" {
  description = "IP elástico do host da aplicação (SERVIDOR_DEPLOY no GitHub)."
  value       = aws_eip.aplicacao.public_ip
}

output "url_api" {
  description = "URL base da API."
  value       = "http://${aws_eip.aplicacao.public_ip}"
}

output "comando_ssh" {
  description = "Comando SSH para diagnóstico."
  value       = "ssh ec2-user@${aws_eip.aplicacao.public_ip}"
}

output "grupo_logs" {
  description = "Grupo de logs da aplicação no CloudWatch."
  value       = aws_cloudwatch_log_group.aplicacao.name
}
