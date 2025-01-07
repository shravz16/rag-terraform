resource "aws_iam_role" "lambda_exec_role" {
  name = "lambda_s3_presigned_url_role"
  lifecycle {
  ignore_changes = [tags, name, assume_role_policy]
}
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_policy" "lambda_s3_policy" {
  name = "lambda_s3_presigned_url_policy"
   lifecycle {
    ignore_changes = [name, description, path, tags]
    create_before_destroy = true
  }
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = ["s3:PutObject"],
        Effect = "Allow",
        Resource = "${aws_s3_bucket.rag.arn}/*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_policy_attach" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = aws_iam_policy.lambda_s3_policy.arn
}


resource "aws_s3_bucket" "rag" {
  lifecycle {
  prevent_destroy = true
  ignore_changes = [tags, bucket, force_destroy]
}
  bucket = var.bucket_name
  tags = {
    Name        = "rag bucket"
    Environment = "Dev"
  }
}

resource "aws_s3_bucket_cors_configuration" "rag_cors" {
  bucket = aws_s3_bucket.rag.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["PUT", "POST", "GET", "DELETE"]
    allowed_origins = ["*"]
    expose_headers  = ["ETag"]
    max_age_seconds = 3000
  }
}

resource "aws_lambda_function" "generate_presigned_url" {
  function_name = var.lambda_presigned
  runtime       = "nodejs16.x"
  role          = aws_iam_role.lambda_exec_role.arn
  handler       = "index.handler"
  environment {
    variables = {
      BUCKET_NAME = aws_s3_bucket.rag.bucket
    }
  }
  filename         = "index.zip"
  source_code_hash = filebase64sha256("index.zip")
}

resource "aws_api_gateway_rest_api" "api" {
  name = var.api_gate_way
}

resource "aws_api_gateway_resource" "lambda_resource" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "generate-presigned-url"
}

# Add OPTIONS method for CORS
resource "aws_api_gateway_method" "options_method" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.lambda_resource.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_method_response" "options_200" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.lambda_resource.id
  http_method = aws_api_gateway_method.options_method.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true,
    "method.response.header.Access-Control-Allow-Methods" = true,
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

resource "aws_api_gateway_integration" "options_integration" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.lambda_resource.id
  http_method = aws_api_gateway_method.options_method.http_method
  type        = "MOCK"

  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }
}

resource "aws_api_gateway_integration_response" "options_integration_response" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.lambda_resource.id
  http_method = aws_api_gateway_method.options_method.http_method
  status_code = aws_api_gateway_method_response.options_200.status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token,Access-Control-Allow-Origin'",
    "method.response.header.Access-Control-Allow-Methods" = "'GET,OPTIONS,POST,PUT'",
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }
}
resource "aws_api_gateway_integration_response" "process_document_post_integration_response" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.process_document.id
  http_method = aws_api_gateway_method.process_document_1.http_method
  status_code = aws_api_gateway_method_response.process_document_1_response.status_code
  
  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin"  = "'*'",
  }

  depends_on = [
    aws_api_gateway_integration.process_document_1_lambda_integration
  ]
}
# Add CORS headers to POST method
resource "aws_api_gateway_method" "lambda_method" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.lambda_resource.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_method_response" "lambda_method_response" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.lambda_resource.id
  http_method = aws_api_gateway_method.lambda_method.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = true
  }
}

resource "aws_api_gateway_integration" "lambda_integration" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.lambda_resource.id
  http_method             = aws_api_gateway_method.lambda_method.http_method
  integration_http_method = "POST"
  type                   = "AWS_PROXY"
  uri                    = aws_lambda_function.generate_presigned_url.invoke_arn
}

resource "aws_api_gateway_integration_response" "lambda_integration_response" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.lambda_resource.id
  http_method = aws_api_gateway_method.lambda_method.http_method
  status_code = aws_api_gateway_method_response.lambda_method_response.status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = "'*'",
 
  }

  depends_on = [
    aws_api_gateway_integration.lambda_integration
  ]
}

resource "aws_lambda_permission" "api_gateway" {
 
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.generate_presigned_url.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api.execution_arn}/*/${aws_api_gateway_method.lambda_method.http_method}${aws_api_gateway_resource.lambda_resource.path}"
}

resource "aws_api_gateway_deployment" "api_deployment" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  stage_name  = "default"

  depends_on = [
    aws_api_gateway_integration.lambda_integration,
    aws_api_gateway_integration.options_integration
  ]
}

output "api_endpoint" {
  value = "${aws_api_gateway_deployment.api_deployment.invoke_url}/generate-presigned-url"
}

# DynamoDB Table
resource "aws_dynamodb_table" "rag_table" {
  name           = "rag_documents"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "id"
   stream_enabled = true
  stream_view_type = "NEW_AND_OLD_IMAGES"
  attribute {
    name = "id"
    type = "S"
  }

  attribute {
    name = "customer_id"
    type = "S"
  }

  global_secondary_index {
    name               = "CustomerIdIndex"
    hash_key           = "customer_id"
    projection_type    = "ALL"
    write_capacity     = 0
    read_capacity      = 0
  }

  tags = {
    Environment = "Dev"
    Project     = "RAG"
  }
}

# SQS Queue
resource "aws_sqs_queue" "rag_queue" {
  name                      = "rag"
  delay_seconds             = 0
  max_message_size         = 262144
  message_retention_seconds = 86400
  receive_wait_time_seconds = 10
  visibility_timeout_seconds = 30

  tags = {
    Environment = "Dev"
    Project     = "RAG"
  }
}

# IAM Role for Lambda
resource "aws_iam_role" "lambda_dynamodb_role" {
  name = "lambda_dynamodb_sqs_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

# IAM Policy for DynamoDB and SQS access
resource "aws_iam_policy" "lambda_dynamodb_policy" {
  name = "lambda_dynamodb_sqs_policy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:UpdateItem",
          "dynamodb:Query",
          "sqs:SendMessage"
        ]
        Resource = [
          aws_dynamodb_table.rag_table.arn,
          aws_sqs_queue.rag_queue.arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

# Attach policy to role
resource "aws_iam_role_policy_attachment" "lambda_dynamodb_attach" {
  role       = aws_iam_role.lambda_dynamodb_role.name
  policy_arn = aws_iam_policy.lambda_dynamodb_policy.arn
}

# Lambda Function
resource "aws_lambda_function" "process_document" {
  filename         = "process_document.zip"
  function_name    = "process_document"
  role            = aws_iam_role.lambda_dynamodb_role.arn
  handler         = "index.handler"
  runtime         = "nodejs16.x"
  timeout         = 30

  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.rag_table.name
      SQS_QUEUE_URL = aws_sqs_queue.rag_queue.url
    }
  }
}

resource "aws_api_gateway_resource" "process_document" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "process-document"
}

# Add OPTIONS method for CORS
resource "aws_api_gateway_method" "process_document_options_method" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.process_document.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_method_response" "process_document_options_200" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.process_document.id
  http_method = aws_api_gateway_method.process_document_options_method.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true,
    "method.response.header.Access-Control-Allow-Methods" = true,
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

resource "aws_api_gateway_integration" "process_document_options_integration" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.process_document.id
  http_method = aws_api_gateway_method.process_document_options_method.http_method
  type        = "MOCK"

  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }
}

resource "aws_api_gateway_integration_response" "process_document_options_integration_response" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.process_document.id
  http_method = aws_api_gateway_method.process_document_options_method.http_method
  status_code = aws_api_gateway_method_response.process_document_options_200.status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token,Access-Control-Allow-Origin'",
    "method.response.header.Access-Control-Allow-Methods" = "'GET,OPTIONS,POST,PUT'",
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }
}

# Add CORS headers to POST method
resource "aws_api_gateway_method" "process_document_1" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.process_document.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_method_response" "process_document_1_response" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.process_document.id
  http_method = aws_api_gateway_method.process_document_1.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = true
  }
}

resource "aws_api_gateway_integration" "process_document_1_lambda_integration" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.process_document.id
  http_method             = aws_api_gateway_method.process_document_1.http_method
  integration_http_method = "POST"
  type                   = "AWS_PROXY"
  uri                    = aws_lambda_function.process_document.invoke_arn
}

resource "aws_api_gateway_integration_response" "process_document_lambda_integration_response" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.process_document.id
  http_method = aws_api_gateway_method.process_document_1.http_method
  status_code = aws_api_gateway_method_response.process_document_1_response.status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = "'*'",
 
  }

  depends_on = [
    aws_api_gateway_integration.process_document_1_lambda_integration
  ]
}

resource "aws_lambda_permission" "process_document_api_gateway" {
 
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.process_document.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api.execution_arn}/*/${aws_api_gateway_method.process_document_1.http_method}${aws_api_gateway_resource.process_document.path}"
}

resource "aws_api_gateway_deployment" "process_document_api_deployment" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  stage_name  = "default"

  depends_on = [
    aws_api_gateway_integration.process_document_1_lambda_integration,
    aws_api_gateway_integration.process_document_options_integration
  ]
}




data "aws_vpc" "existing" {
  id = "vpc-048abfcb0f83f169c"
}

# Get available subnets from the VPC
data "aws_subnets" "available" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.existing.id]
  }
}

# Create DB subnet group using existing subnets
resource "aws_db_subnet_group" "default" {
  name       = "main"
  subnet_ids = slice(data.aws_subnets.available.ids, 0, 2)  # Using first 2 subnets

  tags = {
    Name = "My DB subnet group"
  }
}

# Create security group for RDS
resource "aws_security_group" "rds" {
  name        = "rds_sg"
  description = "Security group for RDS MySQL"
  vpc_id      = data.aws_vpc.existing.id

  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # In production, restrict this to specific IPs
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Generate random password for RDS
resource "random_password" "master" {
  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

# Create RDS instance
resource "aws_db_instance" "default" {
  identifier        = "my-mysql-instance"
  engine            = "mysql"
  engine_version    = "8.0"
  instance_class    = "db.t3.micro"
  allocated_storage = 20

  db_name  = "myapp"  # This is the default database that will be created
  username = "admin"
  password = "password"

  db_subnet_group_name   = aws_db_subnet_group.default.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  skip_final_snapshot = true  # For development; enable for production

  tags = {
    Name = "MyRDSInstance"
  }
  publicly_accessible    = true
}

# Store the generated password in SSM Parameter Store
