terraform {
  required_version = ">= 1.8"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket = "meridian-tofu-state"
    key    = "meridian/terraform.tfstate"
    region = "us-east-1"

    endpoints = {
      s3       = "http://localhost:4566"
      dynamodb = "http://localhost:4566"
    }

    dynamodb_table = "meridian-tofu-locks"

    use_path_style              = true
    skip_credentials_validation = true
    skip_metadata_api_check     = true
  }
}

provider "aws" {
  region = var.region

  s3_use_path_style           = true
  skip_credentials_validation = true
  skip_metadata_api_check     = true

  endpoints {
    s3       = "http://localhost:4566"
    ec2      = "http://localhost:4566"
    sts      = "http://localhost:4566"
    dynamodb = "http://localhost:4566"
  }
}

locals {
  common_tags = {
    environment = var.environment
    project     = "meridian-labs"
  }
}

# ── VPC ──────────────────────────────────────────────────────────────────────

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.common_tags, {
    Name = "meridian-${var.environment}-vpc"
  })
}

# ── Public subnet ─────────────────────────────────────────────────────────────

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(local.common_tags, {
    Name = "meridian-${var.environment}-igw"
  })
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, 1)
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name = "meridian-${var.environment}-public-subnet"
  })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = merge(local.common_tags, {
    Name = "meridian-${var.environment}-public-rt"
  })
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# ── Security group (HTTPS inbound only) ──────────────────────────────────────

resource "aws_security_group" "https_only" {
  name        = "meridian-${var.environment}-https-only"
  description = "Allow inbound HTTPS; allow all outbound"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTPS from anywhere"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "meridian-${var.environment}-https-only-sg"
  })
}

# ── S3 bucket with versioning ─────────────────────────────────────────────────

resource "aws_s3_bucket" "main" {
  bucket = "meridian-labs-${var.environment}-${data.aws_caller_identity.current.account_id}"

  tags = merge(local.common_tags, {
    Name = "meridian-${var.environment}-bucket"
  })
}

resource "aws_s3_bucket_versioning" "main" {
  bucket = aws_s3_bucket.main.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "main" {
  bucket = aws_s3_bucket.main.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

data "aws_caller_identity" "current" {}
