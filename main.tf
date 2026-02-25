provider "aws" {
  region = "us-east-1"
}

resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

resource "aws_secretsmanager_secret" "abuseipdb_secret" {
  name                    = "phishripper_abuseipdb_key_${random_string.suffix.result}"
  recovery_window_in_days = 0 
}

resource "aws_secretsmanager_secret_version" "abuseipdb_secret_val" {
  secret_id     = aws_secretsmanager_secret.abuseipdb_secret.id
  secret_string = jsonencode({ abuseipdb_key = var.abuseipdb_api_key })
}

resource "aws_s3_bucket" "raw_bucket" {
  bucket        = "phishripperraw${random_string.suffix.result}"
  force_destroy = true
}

resource "aws_s3_bucket" "results_bucket" {
  bucket        = "phishripperresults${random_string.suffix.result}"
  force_destroy = true
}

resource "aws_s3_bucket" "frontend_bucket" {
  bucket        = "phishripperfrontend${random_string.suffix.result}"
  force_destroy = true
}

resource "aws_s3_bucket_website_configuration" "frontend_config" {
  bucket = aws_s3_bucket.frontend_bucket.id
  index_document { suffix = "index.html" }
}

resource "aws_s3_bucket_public_access_block" "frontend_public" {
  bucket                  = aws_s3_bucket.frontend_bucket.id
  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_policy" "frontend_policy" {
  bucket = aws_s3_bucket.frontend_bucket.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "PublicReadGetObject"
      Effect    = "Allow"
      Principal = "*"
      Action    = "s3:GetObject"
      Resource  = "${aws_s3_bucket.frontend_bucket.arn}/*"
    }]
  })
  depends_on = [aws_s3_bucket_public_access_block.frontend_public]
}

resource "aws_lambda_function" "ingest" {
  filename         = "backend/ingest.zip"
  function_name    = "PhishIngest"
  role             = data.aws_iam_role.lab_role.arn
  handler          = "ingest.lambda_handler"
  runtime          = "python3.9"
  environment { variables = { RAW_BUCKET = aws_s3_bucket.raw_bucket.id } }
}

resource "aws_lambda_function" "process" {
  filename         = "backend/process.zip"
  function_name    = "PhishProcess"
  role             = data.aws_iam_role.lab_role.arn
  handler          = "process.lambda_handler"
  runtime          = "python3.9"
  timeout          = 30
  environment { 
    variables = { 
        RESULTS_BUCKET = aws_s3_bucket.results_bucket.id 
        SECRET_NAME    = aws_secretsmanager_secret.abuseipdb_secret.arn 
    } 
  }
}

resource "aws_lambda_function" "retrieve" {
  filename         = "backend/retrieve.zip"
  function_name    = "PhishRetrieve"
  role             = data.aws_iam_role.lab_role.arn
  handler          = "retrieve.lambda_handler"
  runtime          = "python3.9"
  environment { variables = { RESULTS_BUCKET = aws_s3_bucket.results_bucket.id } }
}

resource "aws_lambda_permission" "allow_s3" {
  statement_id  = "AllowS3Invoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.process.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.raw_bucket.arn
}

resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = aws_s3_bucket.raw_bucket.id
  lambda_function {
    lambda_function_arn = aws_lambda_function.process.arn
    events              = ["s3:ObjectCreated:*"]
  }
  depends_on = [aws_lambda_permission.allow_s3]
}

resource "aws_apigatewayv2_api" "api" {
  name          = "phishripperapi"
  protocol_type = "HTTP"
  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["POST", "GET"]
    allow_headers = ["content-type"]
  }
}

resource "aws_apigatewayv2_stage" "api_stage" {
  api_id      = aws_apigatewayv2_api.api.id
  name        = "$default"
  auto_deploy = true
}

resource "aws_apigatewayv2_integration" "ingest_integration" {
  api_id           = aws_apigatewayv2_api.api.id
  integration_type = "AWS_PROXY"
  integration_uri  = aws_lambda_function.ingest.invoke_arn
}

resource "aws_apigatewayv2_route" "ingest_route" {
  api_id    = aws_apigatewayv2_api.api.id
  route_key = "POST /scan"
  target    = "integrations/${aws_apigatewayv2_integration.ingest_integration.id}"
}

resource "aws_apigatewayv2_integration" "retrieve_integration" {
  api_id           = aws_apigatewayv2_api.api.id
  integration_type = "AWS_PROXY"
  integration_uri  = aws_lambda_function.retrieve.invoke_arn
}

resource "aws_apigatewayv2_route" "retrieve_route" {
  api_id    = aws_apigatewayv2_api.api.id
  route_key = "GET /report"
  target    = "integrations/${aws_apigatewayv2_integration.retrieve_integration.id}"
}

resource "aws_lambda_permission" "api_ingest" {
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ingest.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.api.execution_arn}/*/*/scan"
}

resource "aws_lambda_permission" "api_retrieve" {
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.retrieve.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.api.execution_arn}/*/*/report"
}