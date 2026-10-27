variable "projeto" {
  description = "Nome do projeto, usado como prefixo de todos os recursos."
  type        = string
  default     = "afazeres"
}

variable "ambiente" {
  description = "Ambiente de deploy."
  type        = string

  validation {
    condition     = contains(["homologacao", "producao"], var.ambiente)
    error_message = "O ambiente deve ser homologacao ou producao."
  }
}

variable "regiao_aws" {
  description = "Região da AWS."
  type        = string
  default     = "us-east-1"
}

variable "cidr_vpc" {
  description = "Bloco CIDR da VPC."
  type        = string
  default     = "10.20.0.0/16"
}

variable "cidr_subrede_publica" {
  description = "Bloco CIDR da sub-rede pública."
  type        = string
  default     = "10.20.1.0/24"
}

variable "tipo_instancia" {
  description = "Tipo da instância EC2 (t3.micro cabe no nível gratuito)."
  type        = string
  default     = "t3.micro"
}

variable "chave_publica_ssh" {
  description = "Chave pública usada pelo pipeline de CD para acessar o host por SSH."
  type        = string
}

variable "cidrs_ssh_permitidos" {
  description = "CIDRs com acesso à porta 22. Mantenha o mais restrito possível."
  type        = list(string)
  default     = []
}

variable "cidrs_monitoramento_permitidos" {
  description = "CIDRs com acesso ao Grafana (3000) e ao Prometheus (9090)."
  type        = list(string)
  default     = []
}
