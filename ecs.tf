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
