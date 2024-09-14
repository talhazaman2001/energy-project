# Use AWS Secrets Manager to store GitHub token

resource "aws_secretsmanager_secret" "github_token" {
  name = "github-token1"
}

resource "aws_secretsmanager_secret_version" "github_token" {
  secret_id     = aws_secretsmanager_secret.github_token.id
  secret_string = "github_pat_11BLDH3TI0VsqyUJEefyqS_aBTygM5GI40W65zrmo1g8FQi5FqpLz8LQOhYP0OrBYw273RYG249924" #Changed to fake access key for my repo
}

# CodeBuild for building and applying Terraform

resource "aws_codebuild_project" "smart_energy_codebuild" {
  name         = "SmartEnergyBuild"
  service_role = aws_iam_role.codebuild_role.arn

  source {
    type            = "GITHUB"
    location        = "https://github.com/talhazaman2001/energy-project.git"
    git_clone_depth = 1
    buildspec       = <<EOF
version: 0.2

phases:
  install:
    commands:
      - echo "Installing Terraform..."
      - curl -LO https://releases.hashicorp.com/terraform/0.14.5/terraform_0.14.5_linux_amd64.zip
      - unzip terraform_0.14.5_linux_amd64.zip
      - mv terraform /usr/local/bin/

  build:
    commands: 
      - echo "Running Terraform Plan"
      - terraform init
      - terraform plan -out=tfplan

  post_build:
    commands:
      - echo "Running Terraform Apply"
      - terraform apply -auto-approve tfplan

EOF
  }

  environment {
    compute_type = "BUILD_GENERAL1_SMALL"
    image        = "aws/codebuild/standard:5.0"
    type         = "LINUX_CONTAINER"
      
    environment_variable {
      name  = "GITHUB_TOKEN"
      value = aws_secretsmanager_secret_version.github_token.secret_string
      type  = "PLAINTEXT"
    }
  }
  
  artifacts {
    type = "NO_ARTIFACTS"
  }
}

# Create CodeStar Connection

resource "aws_codestarconnections_connection" "github_connection" {
    name = "my-github-connection"
    provider_type = "GitHub"
}


# CodePipeline to orchestrate CI/CD Process

resource "aws_codepipeline" "smart_energy_pipeline" {
  name = "SmartEnergyPipeline"

  role_arn = aws_iam_role.codepipeline_role.arn

  artifact_store {
    type     = "S3"
    location = aws_s3_bucket.ci_cd_artifacts.bucket
  }

  stage {
    name = "Source"

    action {
      name             = "GitHubSource"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeStarSourceConnection"
      version          = "1"
      output_artifacts = ["source_output"]

      configuration = {
        ConnectionArn = "arn:aws:codestar-connections:eu-west-2:463470963000:connection/43c0e9a0-f3d6-4d89-9645-5044376ab9f4"
        FullRepositoryId = "https://github.com/talhazaman2001/energy-project.git"
        BranchName    = "main"
      }
    }
  }

  stage {
    name = "Build"

    action {
      name             = "BuildTerraform"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      version          = "1"
      input_artifacts  = ["source_output"]
      output_artifacts = ["build_output"]

      configuration = {
        ProjectName = "aws_codebuild_project.smart_energy_codebuild.name"
      }
    }
  }

  stage {
    name = "Deploy"

    action {
      name = "DeployInfrastructure"
      category        = "Deploy"
      owner           = "AWS"
      provider        = "CodeDeploy"
      version         = "1"
      input_artifacts = ["build_output"]

      configuration = {
        ApplicationName     = "aws_codedeploy_application.lambda_app.name"
        DeploymentGroupName = "aws_codedeploy_deployment_group.lambda_deployment_group.name"
      }

    }
  }
}

# CodeDeploy for deploying the Lambda Function

resource "aws_codedeploy_app" "lambda_app" {
  name             = "SmartEnergyApp"
  compute_platform = "Lambda"
}

resource "aws_codedeploy_deployment_group" "lambda_deployment_group" {
  app_name              = aws_codedeploy_app.lambda_app.name
  deployment_group_name = "SmartEnergyLambdaDeploymentGroup"
  service_role_arn      = aws_iam_role.codedeploy_role.arn

  deployment_config_name = "CodeDeployDefault.LambdaAllAtOnce"

  deployment_style {
    deployment_type = "BLUE_GREEN"
    deployment_option = "WITH_TRAFFIC_CONTROL"
  }

  auto_rollback_configuration {
    enabled = true
    events  = ["DEPLOYMENT_FAILURE"]
  }

  alarm_configuration {
    enabled = false
  }
}

# S3 Bucket for artifacts

resource "aws_s3_bucket" "ci_cd_artifacts" {
  bucket = "smart-energy-ci-cd-artifacts"
}

# Enable Versioning
resource "aws_s3_bucket_versioning" "ci_cd_artifacts_versioning" {
  bucket = aws_s3_bucket.ci_cd_artifacts.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "ci_cd_artifacts_block" {
    bucket = aws_s3_bucket.ci_cd_artifacts.id

    block_public_acls = true
    block_public_policy = false
    restrict_public_buckets = true
    ignore_public_acls = true
}

# IAM Role for CodePipeline

resource "aws_iam_role" "codepipeline_role" {
  name = "CodePipelineRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Principal = {
          Service = "codepipeline.amazonaws.com"
        },
        Effect = "Allow",
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "codepipeline_policy_attach" {
  role       = aws_iam_role.codepipeline_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSCodePipeline_FullAccess"
}

# IAM Role for CodeBuild

resource "aws_iam_role" "codebuild_role" {
  name = "CodeBuildRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole",
        Principal = {
          Service = "codebuild.amazonaws.com"
        },
        Effect = "Allow",
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "codebuild_policy_attach" {
  role       = aws_iam_role.codebuild_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSCodeBuildAdminAccess"
}

# IAM Role for CodeDeploy

resource "aws_iam_role" "codedeploy_role" {
  name = "CodeDeployRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Principal = {
          Service = "codedeploy.amazonaws.com"
        },
        Effect = "Allow",
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "codedeploy_policy_attach" {
  role       = aws_iam_role.codedeploy_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSCodeDeployRole"
}

