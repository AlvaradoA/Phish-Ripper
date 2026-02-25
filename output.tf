output "api_url" {
  value       = aws_apigatewayv2_api.api.api_endpoint
  description = "The endpoint URL for the API Gateway"
}

output "website_url" {
  value       = aws_s3_bucket_website_configuration.frontend_config.website_endpoint
  description = "The static website URL for the frontend application"
}