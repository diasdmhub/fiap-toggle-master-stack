# Security group do Lambda: sem ingress (não recebe conexões diretas),
# egress liberado só para HTTPS (API do EKS e, se precisar, outros endpoints AWS).
resource "aws_security_group" "lambda" {
  name        = "${var.name_prefix}-selfheal-lambda-sg"
  description = "SG do Lambda de self-healing (egress HTTPS apenas)"
  vpc_id      = var.vpc_id

  egress {
    description = "HTTPS para a API do EKS e endpoints AWS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Libera no security group do control plane do EKS o ingress vindo do Lambda.
# Necessário mesmo com endpoint público, e obrigatório com endpoint privado.
resource "aws_security_group_rule" "cluster_from_lambda" {
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  security_group_id        = var.cluster_security_group_id
  source_security_group_id = aws_security_group.lambda.id
  description              = "Permite que o Lambda de self-healing acesse a API do EKS"
}
