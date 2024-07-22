resource "aws_ecs_cluster" "api" {
  name = "api"
}

resource "aws_ecs_cluster_capacity_providers" "api" {
  cluster_name = aws_ecs_cluster.api.name

  capacity_providers = ["FARGATE"]

  default_capacity_provider_strategy {
    base              = 1
    weight            = 100
    capacity_provider = "FARGATE"
  }
}

resource "aws_ecs_service" "helloworld" {
  name            = "helloworld"
  cluster         = aws_ecs_cluster.api.id
  task_definition = aws_ecs_task_definition.helloworld.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

  network_configuration {
    subnets = [
      aws_subnet.private-eu-west-2a.id
    ]
    security_groups  = [aws_security_group.api.id]
    assign_public_ip = false
  }

  load_balancer {
    container_name   = "laravel"
    container_port   = 8000
    target_group_arn = aws_lb_target_group.api.arn
  }
}

resource "aws_cloudwatch_log_group" "my_log_group" {
  name              = "/ecs/api"
  retention_in_days = 30
}

resource "aws_ecs_task_definition" "helloworld" {
  family                   = "helloworld"
  cpu                      = 512
  memory                   = 1024
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = data.aws_iam_role.ecs_task_execution_role.arn

  container_definitions = jsonencode(
    [
      {
        name      = "laravel"
        image     = "public.ecr.aws/bitnami/laravel:latest"
        essential = true
        portMappings = [
          {
            protocol      = "tcp"
            hostPort      = 8000
            containerPort = 8000
          }
        ]

        logConfiguration = {
          logDriver = "awslogs"
          options = {
            awslogs-group         = aws_cloudwatch_log_group.my_log_group.name
            awslogs-region        = "eu-west-2"
            awslogs-stream-prefix = "ecs"
          }
        }

        environment = [
          {
            name = "DB_HOST",
            value = aws_rds_cluster.cluster.endpoint
          },
          {
            name = "DB_PORT",
            value = tostring(aws_rds_cluster.cluster.port)
          },
          {
            name = "DB_USERNAME",
            value = aws_rds_cluster.cluster.master_username
          },
          {
            name = "DB_DATABASE",
            value = aws_rds_cluster.cluster.database_name
          }
        ]

        secrets = [
          {
            name = "DB_PASSWORD",
            valueFrom = "${data.aws_secretsmanager_secret.rds_credentials.arn}:password::"
          },
        ]
      }
    ]
  )

  depends_on = [aws_rds_cluster_instance.replica]
}

### SECRETS MANAGER PERMISSION ###
resource "aws_iam_policy" "ecs_task_execution_policy" {
  name        = "ecs-task-execution-policy"
  description = "Policy to allow ECS tasks to access Database Credentials"
  
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "secretsmanager:GetSecretValue"
        ],
        Effect   = "Allow",
        Resource = data.aws_secretsmanager_secret.rds_credentials.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy_attachment" {
  role       = data.aws_iam_role.ecs_task_execution_role.name
  policy_arn = aws_iam_policy.ecs_task_execution_policy.arn
}

### AUTOSCALING ###
resource "aws_appautoscaling_target" "api_autoscaling" {
  max_capacity       = 3
  min_capacity       = 1
  resource_id        = "service/${aws_ecs_cluster.api.name}/${aws_ecs_service.helloworld.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "scale_up" {
  name               = "scale-up"
  policy_type        = "StepScaling"
  resource_id        = aws_appautoscaling_target.api_autoscaling.resource_id
  scalable_dimension = aws_appautoscaling_target.api_autoscaling.scalable_dimension
  service_namespace  = aws_appautoscaling_target.api_autoscaling.service_namespace

  step_scaling_policy_configuration {
    adjustment_type         = "ChangeInCapacity"
    cooldown                = 60
    metric_aggregation_type = "Average"

    step_adjustment {
      scaling_adjustment          = 1
      metric_interval_lower_bound = 0
    }
  }
}

resource "aws_appautoscaling_policy" "scale_down" {
  name               = "scale-down"
  policy_type        = "StepScaling"
  resource_id        = aws_appautoscaling_target.api_autoscaling.resource_id
  scalable_dimension = aws_appautoscaling_target.api_autoscaling.scalable_dimension
  service_namespace  = aws_appautoscaling_target.api_autoscaling.service_namespace

  step_scaling_policy_configuration {
    adjustment_type         = "ChangeInCapacity"
    cooldown                = 60
    metric_aggregation_type = "Average"

    step_adjustment {
      scaling_adjustment          = -1
      metric_interval_lower_bound = 0
    }
  }
}

resource "aws_cloudwatch_metric_alarm" "high_cpu_usage" {
  alarm_name          = "high-cpu-usage"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = "60"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "Trigger an alarm when the CPU usage exceeds 80% for 2 consecutive periods"
  dimensions = {
    ClusterName = aws_ecs_cluster.api.name
    ServiceName = aws_ecs_service.helloworld.name
  }

  alarm_actions = [aws_appautoscaling_policy.scale_up.arn]
}

resource "aws_cloudwatch_metric_alarm" "low_cpu_usage" {
  alarm_name          = "low-cpu-usage"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = "60"
  statistic           = "Average"
  threshold           = "20"
  alarm_description   = "Trigger task scale down when the CPU usage dips below 20% for 2 consecutive periods"
  dimensions = {
    ClusterName = aws_ecs_cluster.api.name
    ServiceName = aws_ecs_service.helloworld.name
  }

  alarm_actions = [aws_appautoscaling_policy.scale_up.arn]
}
