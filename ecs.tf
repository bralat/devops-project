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
      aws_subnet.private-eu-west-2a.id,
      aws_subnet.private-eu-west-2b.id
    ]
    security_groups  = [aws_security_group.api.id]
    assign_public_ip = false
  }

  load_balancer {
    container_name   = "nginx"
    container_port   = 80
    target_group_arn = aws_lb_target_group.api.arn
  }
}

resource "aws_ecs_task_definition" "helloworld" {
  family                   = "helloworld"
  cpu                      = 512
  memory                   = 1024
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]

  container_definitions = jsonencode(
    [
      {
        name      = "nginx"
        image     = "public.ecr.aws/nginx/nginx:stable-alpine3.19-slim"
        essential = true
        portMappings = [
          {
            protocol      = "tcp"
            hostPort      = 80
            containerPort = 80
          }
        ]
      }
    ]
  )
}

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
