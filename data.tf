data "aws_iam_role" "ecs_task_execution_role" {
  name = "ecsTaskExecutionRole"
}

data "aws_secretsmanager_secret" "rds_credentials" {
  name = aws_rds_cluster.cluster.master_user_secret[0].secret_arn
}
