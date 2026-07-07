resource "aws_apigatewayv2_api" "this" {
  name          = "${var.name_prefix}-selfheal-api"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_integration" "lambda" {
  api_id                 = aws_apigatewayv2_api.this.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.selfheal.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "selfheal" {
  api_id    = aws_apigatewayv2_api.this.id
  route_key = "POST /selfheal"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.this.id
  name        = "$default"
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.apigw.arn
    format = jsonencode({
      requestId       = "$context.requestId"
      routeKey        = "$context.routeKey"
      status          = "$context.status"
      integrationError = "$context.integrationErrorMessage"
      sourceIp        = "$context.identity.sourceIp"
    })
  }
}

resource "aws_cloudwatch_log_group" "apigw" {
  name              = "/aws/apigateway/${var.name_prefix}-selfheal"
  retention_in_days = var.log_retention_days
}

# Permite que o API Gateway invoque a função Lambda
resource "aws_lambda_permission" "apigw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.selfheal.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.this.execution_arn}/*/*"
}
