resource "aws_ecs_task_definition" "weather_api_task_def" {
  container_definitions = data.template_file.weather_api_task.rendered
  family                = "${var.environment}_weather_api"

  requires_compatibilities = ["EC2"]
  network_mode             = var.ecs_task_mode
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_execution_role.arn

  tags = merge(local.common_tags, map("Name", "Weather-API-Task"))
}


resource "aws_ecs_service" "weather_api_ecs_service" {
  depends_on = [aws_iam_role.ecs_service_role, aws_iam_role.ecs_task_execution_role]

  name                = "${var.component_name}-ecs-service"
  iam_role            = aws_iam_role.ecs_service_role.name
  cluster             = data.terraform_remote_state.ecs-cluster.outputs.ecs-cluster-id
  task_definition     = aws_ecs_task_definition.weather_api_task_def.arn
  desired_count       = var.service_desired_count
  scheduling_strategy = "REPLICA"

  deployment_maximum_percent         = 200
  deployment_minimum_healthy_percent = 70

  launch_type = var.service_launch_type

  load_balancer {
    target_group_arn = aws_lb_target_group.weather_api_ecs_alb_tg.arn
    container_name   = "Weather-API"
    container_port   = 8001
  }
}

resource "aws_alb_listener_rule" "ecs_alb_listener_rule" {
  depends_on = [aws_lb_target_group.weather_api_ecs_alb_tg]

  listener_arn = data.terraform_remote_state.ecs-cluster.outputs.alb-listner-arn
  priority     = "001"

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.weather_api_ecs_alb_tg.arn
  }
  condition {
    path_pattern {
      values = ["/"]
    }
  }
}

resource "aws_lb_target_group" "weather_api_ecs_alb_tg" {
  name = "${var.component_name}-${var.environment}-cs-tg"

  port        = var.default_target_group_port
  protocol    = "HTTP"
  vpc_id      = data.terraform_remote_state.vpc.outputs.vpc_id
  target_type = "instance"

  tags = {
    name = "${var.component_name}-tg"
  }

  health_check {
    enabled             = true
    protocol            = "HTTP"
    healthy_threshold   = 5
    unhealthy_threshold = 5
    timeout             = 5
    interval            = 20
    path                = "/internal/health"
    matcher             = "200,301,302"
  }
}