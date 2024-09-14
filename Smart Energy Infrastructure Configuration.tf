# Define the IoT Core Configurations

resource "aws_iot_policy" "iot_policy" {
  name   = "SmartEnergyIoTPolicy"
  policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "iot:Connect",
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": "iot:Publish",
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": "iot:Subscribe",
      "Resource": "*"
    }
  ]
}
POLICY
}

# Define Lambda function for processing energy data coming from IoT devices

resource "aws_lambda_function" "process_energy_data" {
    function_name = "ProcessEnergyData"
    role = aws_iam_role.lambda_role.arn
    handler = "lambda_function.lambda_handler"
    runtime = "python3.12"
    
    # ZIP file containing the function code
    filename = "${path.module}users/documents/smart-energy-monitoring-project/function.zip"

    environment {
        variables = {
            TABLE_NAME = aws_dynamodb_table.energy_data.name
        }
    }
}

# IAM Role for Lambda to interact with other AWS services

resource "aws_iam_role" "lambda_role" {
    name = "lambda_role"

    assume_role_policy = jsonencode({
        Version = "2012-10-17"
        Statement = [{
            Action = "sts:AssumeRole"
            Effect = "Allow"
            Principal = {
                Service = "lambda.amazonaws.com"
            }
        }]
    })
}

# DynamoDB to store energy consumption data

resource "aws_dynamodb_table" "energy_data" {
    name = "EnergyData"
    hash_key = "DeviceId"
    range_key = "Timestamp"
    billing_mode = "PAY_PER_REQUEST"

    attribute {
        name = "DeviceId"
        type = "S"
    }

    attribute { 
        name = "Timestamp"
        type = "N"
    }

    ttl {
        attribute_name = "TTL"
        enabled = true
    }
}

# S3 Bucket for archived raw energy data from IoT devices
resource "aws_s3_bucket" "energy_data_archive" {
    bucket = "smart-energy-data-archive"
}

resource "aws_s3_bucket_acl" "energy_data_archive_acl" {
  bucket = aws_s3_bucket.energy_data_archive.id
  acl    = "private"
}

resource "aws_s3_bucket_lifecycle_configuration" "energy_data_lifecycle_config" {
  bucket = aws_s3_bucket.energy_data_archive.id

    # Lifecycle rule for archiving raw energy data
    rule {
        id = "energy-data-archiving"

        expiration {
            days = 365
        } 
        
        filter {
            and {
                prefix = "raw_data/"

                tags = {
                    archive = "true"
                    datalife = "long"
                }
            }   
        }
    
    status = "Enabled"

    # Transition data to STANDARD_IA after 30 days
    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    # Transition data to GLACIER after 90 days
    transition {
      days          = 60
      storage_class = "GLACIER"
    }
  }
}

# S3 Bucket for Log Files
  resource "aws_s3_bucket" "energy_logs" {
    bucket = "smart-energy-logs"
  }
  
  resource "aws_s3_bucket_acl" "energy_logs_acl" {
    bucket = aws_s3_bucket.energy_logs.id
    acl = "private"
  }

# Enable versioning for the log bucket
resource "aws_s3_bucket_versioning" "energy_logs_versioning" {
    bucket = aws_s3_bucket.energy_logs.id
    versioning_configuration {
        status = "Enabled"
    }
}

# Lifecycle configuration for managing log files
resource "aws_s3_bucket_lifecycle_configuration" "energy_logs_lifecycle_config" {
    depends_on = [aws_s3_bucket_versioning.energy_logs_versioning]

    bucket = aws_s3_bucket.energy_logs.id

    rule {
        id = "log-files-archiving"

        filter {
            prefix = "log/"
        }
        
         noncurrent_version_expiration {
        noncurrent_days = 180 # Delete non-current log versions after 80 days
        }
        
        # Transition non-current log version to STANDARD_IA after 60 days
        noncurrent_version_transition {
            noncurrent_days = 60
            storage_class = "STANDARD_IA"
        }
        
        # Transition non-current log versions to GLACIER after 120 days
        noncurrent_version_transition {
            noncurrent_days = 120
            storage_class = "GLACIER"
        }

    status = "Enabled"
    } 
}


# API Gateway to provide energy data for web or mobile apps

resource "aws_api_gateway_rest_api" "energy_api" {
    name = "SmartEnergyAPI"
    description = "API for accessing energy consumption data"
}

resource "aws_api_gateway_resource" "energy_resource" {
    rest_api_id = aws_api_gateway_rest_api.energy_api.id
    parent_id = aws_api_gateway_rest_api.energy_api.root_resource_id
    path_part = "energy"
}

resource "aws_api_gateway_method" "energy_method" {
    rest_api_id = aws_api_gateway_rest_api.energy_api.id
    resource_id = aws_api_gateway_resource.energy_resource.id
    http_method = "GET"
    authorization = "NONE"
}

# Define the SNS topic resource
resource "aws_sns_topic" "energy_alerts" {
  name = "EnergyAlerts"
}

# Enable CloudWatch for monitoring and logging

resource "aws_cloudwatch_log_group" "lambda_log_group" {
    name = "/aws/lambda/ProcessEnergyData"
    retention_in_days = 14
}

# CloudWatch Alarm for anomalies 

resource "aws_cloudwatch_metric_alarm" "high_energy_alarm" {
    alarm_name = "HighEnergyConsumption"
    comparison_operator = "GreaterThanOrEqualToThreshold"
    evaluation_periods = 1
    metric_name = "EnergyUsage"
    namespace = "AWS/IoT"
    period = 300
    statistic = "Sum"
    threshold = 1000

    alarm_actions = [aws_sns_topic.energy_alerts.arn]
}

# Define IAM roles and policies for secure access from Lambda to DynamoDB

resource "aws_iam_policy" "lambda_dynamodb_policy" {
    name = "LambdaDynamoDBAccessPolicy"

    policy = jsonencode({
        Version = "2012-10-17",
        Statement = [
            {
                Action = [
                    "dynamodb:PutItem",
                    "dynamodb:UpdateItem",
                    "dynamodb:GetItem"
                ],
                Effect = "Allow",
                Resource = aws_dynamodb_table.energy_data.arn
            }
        ]
    })
}

resource "aws_iam_role_policy_attachment" "lambda_dynamodb_attach" {
    role = aws_iam_role.lambda_role.name
    policy_arn = aws_iam_policy.lambda_dynamodb_policy.arn
}