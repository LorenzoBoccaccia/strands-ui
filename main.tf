terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.100.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"  # Change to your preferred region
}

# Variables
variable "app_name" {
  description = "Name of the application"
  default     = "strands-gui"
}

variable "environment" {
  description = "Deployment environment"
  default     = "dev"
}

variable "admin_email" {
  description = "Email for the default admin user"
  default     = "admin@example.com"
}


# Generate a random password for the database
resource "random_password" "db_password" {
  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

# ECR Repository
resource "aws_ecr_repository" "app_repo" {
  name                 = var.app_name
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

# VPC Configuration
resource "aws_vpc" "app_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.app_name}-vpc-${var.environment}"
  }
}

# Public Subnets
resource "aws_subnet" "public_subnet_1" {
  vpc_id                  = aws_vpc.app_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "${data.aws_region.current.name}a"
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.app_name}-public-subnet-1-${var.environment}"
  }
}

resource "aws_subnet" "public_subnet_2" {
  vpc_id                  = aws_vpc.app_vpc.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "${data.aws_region.current.name}b"
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.app_name}-public-subnet-2-${var.environment}"
  }
}

# Private Subnets for App Runner
resource "aws_subnet" "private_subnet_1" {
  vpc_id                  = aws_vpc.app_vpc.id
  cidr_block              = "10.0.3.0/24"
  availability_zone       = "${data.aws_region.current.name}a"
  map_public_ip_on_launch = false

  tags = {
    Name = "${var.app_name}-private-subnet-1-${var.environment}"
  }
}

resource "aws_subnet" "private_subnet_2" {
  vpc_id                  = aws_vpc.app_vpc.id
  cidr_block              = "10.0.4.0/24"
  availability_zone       = "${data.aws_region.current.name}b"
  map_public_ip_on_launch = false

  tags = {
    Name = "${var.app_name}-private-subnet-2-${var.environment}"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.app_vpc.id

  tags = {
    Name = "${var.app_name}-igw-${var.environment}"
  }
}

# Route Tables
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.app_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "${var.app_name}-public-rt-${var.environment}"
  }
}

# NAT Gateway for private subnets
resource "aws_eip" "nat_eip" {
  domain = "vpc"
  tags = {
    Name = "${var.app_name}-nat-eip-${var.environment}"
  }
}

resource "aws_nat_gateway" "nat_gateway" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public_subnet_1.id

  tags = {
    Name = "${var.app_name}-nat-gateway-${var.environment}"
  }

  depends_on = [aws_internet_gateway.igw]
}

resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.app_vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_gateway.id
  }

  tags = {
    Name = "${var.app_name}-private-rt-${var.environment}"
  }
}

# Route Table Associations
resource "aws_route_table_association" "public_rta_1" {
  subnet_id      = aws_subnet.public_subnet_1.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table_association" "public_rta_2" {
  subnet_id      = aws_subnet.public_subnet_2.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table_association" "private_rta_1" {
  subnet_id      = aws_subnet.private_subnet_1.id
  route_table_id = aws_route_table.private_rt.id
}

resource "aws_route_table_association" "private_rta_2" {
  subnet_id      = aws_subnet.private_subnet_2.id
  route_table_id = aws_route_table.private_rt.id
}

# Security Group for App Runner
resource "aws_security_group" "app_runner_sg" {
  name        = "${var.app_name}-app-runner-sg"
  description = "Security group for App Runner service"
  vpc_id      = aws_vpc.app_vpc.id

  ingress {
    from_port   = 5000
    to_port     = 5000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.app_name}-app-runner-sg-${var.environment}"
  }
}

# Get current region
data "aws_region" "current" {}

# No VPC endpoints - using NAT Gateway instead

# App Runner VPC Connector
resource "aws_apprunner_vpc_connector" "connector" {
  vpc_connector_name = "${var.app_name}-vpc-connector"
  subnets            = [aws_subnet.private_subnet_1.id, aws_subnet.private_subnet_2.id]
  security_groups    = [aws_security_group.app_runner_sg.id]
}

# No VPC Endpoint for DSQL - using public endpoint with NAT Gateway instead

# App Runner Service
resource "aws_apprunner_service" "app_service" {
  service_name = var.app_name

  source_configuration {
    auto_deployments_enabled = true
    image_repository {
      image_configuration {
        port = "5000"
        runtime_environment_variables = {
          # Set the database URI using the DSQL public endpoint
          # We'll need to update this with the actual identifier after the cluster is created
          SQLALCHEMY_DATABASE_URI = "${aws_dsql_cluster.strands_db.identifier}.dsql.${data.aws_region.current.name}.on.aws"
          # Cognito configuration
          COGNITO_ENABLED = "true"
          COGNITO_USER_POOL_ID = aws_cognito_user_pool.strands_user_pool.id
          COGNITO_CLIENT_ID = aws_cognito_user_pool_client.strands_client.id
          COGNITO_CLIENT_SECRET = ""
          COGNITO_DOMAIN = "${var.app_name}-${var.environment}.auth.${data.aws_region.current.name}.amazoncognito.com"
          # Use a placeholder that will be updated after deployment
          COGNITO_REDIRECT_URI = "https://placeholder-url.amazonaws.com/auth/callback"
          OTEL_EXPORTER_OTLP_ENDPOINT="https://xray.us-east-1.amazonaws.com/v1/traces"
          STRANDS_OTEL_ENABLE_CONSOLE_EXPORT=true

        }
      }
      image_identifier      = "${aws_ecr_repository.app_repo.repository_url}:latest"
      image_repository_type = "ECR"
    }
    authentication_configuration {
      access_role_arn = aws_iam_role.app_runner_role.arn
    }
  }

  network_configuration {
    egress_configuration {
      egress_type       = "VPC"
      vpc_connector_arn = aws_apprunner_vpc_connector.connector.arn
    }
  }

  # Set the instance role for the App Runner service
  instance_configuration {
    instance_role_arn = aws_iam_role.app_runner_role.arn
  }

  depends_on = [
    aws_ecr_repository.app_repo,
    null_resource.docker_push
  ]
}

# IAM Role for App Runner
resource "aws_iam_role" "app_runner_role" {
  name = "${var.app_name}-app-runner-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = ["build.apprunner.amazonaws.com", "tasks.apprunner.amazonaws.com"]
        }
      }
    ]
  })
}

# IAM Policy for App Runner to pull from ECR
resource "aws_iam_role_policy_attachment" "app_runner_ecr_policy" {
  role       = aws_iam_role.app_runner_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSAppRunnerServicePolicyForECRAccess"
}

# IAM Policy for App Runner to access Amazon Bedrock
resource "aws_iam_policy" "bedrock_access_policy" {
  name        = "${var.app_name}-bedrock-access-policy"
  description = "Policy allowing access to Amazon Bedrock services"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel",
          "bedrock:InvokeModelWithResponseStream",
          "bedrock:ListFoundationModels",
          "bedrock:GetFoundationModel",
          "sts:GetCallerIdentity"
        ]
        Resource = "*"
      }
    ]
  })
}

# IAM Policy for App Runner to access Bedrock Knowledge Bases
resource "aws_iam_policy" "bedrock_kb_policy" {
  name        = "${var.app_name}-bedrock-kb-policy"
  description = "Policy allowing access to Amazon Bedrock Knowledge Bases"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "bedrock:Retrieve",
          "bedrock:RetrieveAndGenerate",
          "bedrock:ListKnowledgeBases",
          "bedrock:GetKnowledgeBase"
        ]
        Resource = "*"
      }
    ]
  })
}

# Attach Bedrock policy to App Runner role
resource "aws_iam_role_policy_attachment" "app_runner_bedrock_policy" {
  role       = aws_iam_role.app_runner_role.name
  policy_arn = aws_iam_policy.bedrock_access_policy.arn
}

# Attach Bedrock Knowledge Base policy to App Runner role
resource "aws_iam_role_policy_attachment" "app_runner_bedrock_kb_policy" {
  role       = aws_iam_role.app_runner_role.name
  policy_arn = aws_iam_policy.bedrock_kb_policy.arn
}

# Attach AmazonAuroraDSQLFullAccess policy to App Runner role
resource "aws_iam_role_policy_attachment" "app_runner_dsql_policy" {
  role       = aws_iam_role.app_runner_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonAuroraDSQLFullAccess"
}

# Attach AWSXrayWriteOnlyAccess policy to App Runner role
resource "aws_iam_role_policy_attachment" "app_runner_xray_policy" {
  role       = aws_iam_role.app_runner_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSXrayWriteOnlyAccess"
}

# Build and push Docker image
resource "null_resource" "docker_push" {
  triggers = {
    ecr_repository_url = aws_ecr_repository.app_repo.repository_url
    # Monitor app.py for changes
    app_py_hash = filemd5("${path.module}/app.py")
    # Monitor workflow_runner.py for changes
    workflow_runner_py_hash = filemd5("${path.module}/workflow_runner.py")
    # Monitor all files in templates directory
    templates_hash = sha256(join("", [for f in fileset("${path.module}/templates", "**") : filemd5("${path.module}/templates/${f}")]))
    df_py_hash = filemd5("${path.module}/Dockerfile")
  }

  provisioner "local-exec" {
    command = <<-EOT
      aws ecr get-login-password --region ${data.aws_region.current.name} |      podman login --username AWS --password-stdin  ${aws_ecr_repository.app_repo.repository_url}
      podman build --platform=linux/amd64 -t ${aws_ecr_repository.app_repo.repository_url}:latest .
      podman push ${aws_ecr_repository.app_repo.repository_url}:latest
    EOT
  }

  depends_on = [aws_ecr_repository.app_repo]
}

# DSQL Cluster
resource "aws_dsql_cluster" "strands_db" {
  deletion_protection_enabled = false

  tags = {
    Name = "${var.app_name}-dsql-cluster"
  }
}

# Output the App Runner URL
output "app_url" {
  value = aws_apprunner_service.app_service.service_url
}

# Output instructions for updating Cognito callback URLs
output "update_cognito_instructions" {
  value = <<-EOT
    After deployment, update the Cognito client callback URLs with:
    
    aws cognito-idp update-user-pool-client \
      --user-pool-id ${aws_cognito_user_pool.strands_user_pool.id} \
      --client-id ${aws_cognito_user_pool_client.strands_client.id} \
      --callback-urls https://${aws_apprunner_service.app_service.service_url}/auth/callback \
      --logout-urls https://${aws_apprunner_service.app_service.service_url}/
  EOT
}

# Output the DSQL Cluster ARN
output "dsql_cluster_arn" {
  value = aws_dsql_cluster.strands_db.arn
  description = "The ARN of the DSQL cluster"
}

# Cognito User Pool
resource "aws_cognito_user_pool" "strands_user_pool" {
  name = "${var.app_name}-user-pool"
  
  username_attributes = ["email"]
  
  # Use verification configuration instead of auto_verify_attributes
  verification_message_template {
    default_email_option = "CONFIRM_WITH_CODE"
  }
  
  email_configuration {
    email_sending_account = "COGNITO_DEFAULT"
  }
  
  password_policy {
    minimum_length    = 8
    require_lowercase = true
    require_numbers   = true
    require_symbols   = true
    require_uppercase = true
  }
  
  schema {
    attribute_data_type = "String"
    name                = "email"
    required            = true
    mutable             = true
  }
  
  admin_create_user_config {
    allow_admin_create_user_only = true
  }
  
  tags = {
    Name = "${var.app_name}-user-pool-${var.environment}"
  }
}

# Cognito User Pool Client
resource "aws_cognito_user_pool_client" "strands_client" {
  name                = "${var.app_name}-client"
  user_pool_id        = aws_cognito_user_pool.strands_user_pool.id
  
  generate_secret     = false
  explicit_auth_flows = [
    "ALLOW_USER_PASSWORD_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH",
    "ALLOW_USER_SRP_AUTH"
  ]
  
  # Use a placeholder URL that will be updated later
  callback_urls       = ["https://placeholder-url.amazonaws.com/auth/callback"]
  logout_urls         = ["https://placeholder-url.amazonaws.com/"]
  
  allowed_oauth_flows = ["code"]
  allowed_oauth_scopes = ["email", "openid", "profile"]
  supported_identity_providers = ["COGNITO"]
}

# Create default admin user
resource "aws_cognito_user" "admin_user" {
  user_pool_id = aws_cognito_user_pool.strands_user_pool.id
  username     = var.admin_email
  
  attributes = {
    email          = var.admin_email
    email_verified = true
  }
}

# Generate a random password for the admin user
resource "random_password" "admin_password" {
  length           = 12
  special          = true
  override_special = "!@#$%^&*()-_=+[]{}:;<>,.?"
  min_numeric      = 1
}


# Output the admin password
output "admin_password" {
  value     = random_password.admin_password.result
  sensitive = true
  description = "Password for the admin user (sensitive)"
}

output "admin_user" {
  value     = "admin@example.com"
  description = "The default admin user"
}


# Set the admin user's password
resource "null_resource" "set_admin_password" {
  depends_on = [aws_cognito_user.admin_user]
  
  provisioner "local-exec" {
    command = <<-EOT
      aws cognito-idp admin-set-user-password \
        --user-pool-id ${aws_cognito_user_pool.strands_user_pool.id} \
        --username ${var.admin_email} \
        --password '${random_password.admin_password.result}' \
        --permanent
    EOT
  }
}
