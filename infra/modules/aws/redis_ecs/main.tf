locals {
  redis_dns_name = "${var.service_name}.${aws_service_discovery_private_dns_namespace.this.name}"
  redis_endpoint = "${local.redis_dns_name}:${var.container_port}"

  common_tags = merge(var.tags, {
    Project     = var.project
    Environment = var.environment
    Service     = var.service_name
  })
}

# =============================================================================
# CLOUD MAP — private DNS namespace + service so the API task resolves "redis.<ns>"
# =============================================================================

resource "aws_service_discovery_private_dns_namespace" "this" {
  name        = var.service_discovery_namespace_name
  description = "Private DNS namespace for internal services on the ${var.environment} ECS cluster"
  vpc         = var.vpc_id

  tags = local.common_tags
}

resource "aws_service_discovery_service" "redis" {
  name = var.service_name

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.this.id

    dns_records {
      ttl  = var.service_discovery_dns_ttl
      type = "A"
    }

    routing_policy = "MULTIVALUE"
  }

  tags = local.common_tags
}

# =============================================================================
# SECURITY GROUP — only the API task SG (or anything passed in) may dial Redis
# =============================================================================

resource "aws_security_group" "redis" {
  name        = "${var.project}-${var.environment}-${var.service_name}-sg"
  description = "Security group for the centralized Redis service"
  vpc_id      = var.vpc_id

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${var.project}-${var.environment}-${var.service_name}-sg"
  })
}

resource "aws_security_group_rule" "redis_ingress" {
  for_each = var.ingress_security_group_ids

  type                     = "ingress"
  from_port                = var.container_port
  to_port                  = var.container_port
  protocol                 = "tcp"
  security_group_id        = aws_security_group.redis.id
  source_security_group_id = each.value
  description              = "Allow Redis traffic from ${each.key}"
}

# =============================================================================
# IAM — task execution role (image pull + logs) and task role (no AWS calls needed)
# =============================================================================

data "aws_iam_policy_document" "ecs_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "task_execution" {
  name               = var.task_execution_role_name
  assume_role_policy = data.aws_iam_policy_document.ecs_assume_role.json
  tags               = local.common_tags
}

resource "aws_iam_role_policy_attachment" "task_execution_managed" {
  role       = aws_iam_role.task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "task" {
  name               = var.task_role_name
  assume_role_policy = data.aws_iam_policy_document.ecs_assume_role.json
  tags               = local.common_tags
}

# =============================================================================
# LOGS
# =============================================================================

resource "aws_cloudwatch_log_group" "redis" {
  name              = var.log_group_name
  retention_in_days = var.log_retention_days
  tags              = local.common_tags
}

# =============================================================================
# TASK DEFINITION — single redis container, no persistence
# =============================================================================

resource "aws_ecs_task_definition" "redis" {
  family                   = "${var.project}-${var.environment}-${var.service_name}"
  cpu                      = var.cpu
  memory                   = var.memory
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = aws_iam_role.task_execution.arn
  task_role_arn            = aws_iam_role.task.arn

  container_definitions = jsonencode([
    {
      name      = var.service_name
      image     = var.container_image
      essential = true

      command = [
        "redis-server",
        "--maxmemory", "${var.max_memory_mb}mb",
        "--maxmemory-policy", var.maxmemory_policy,
        "--appendonly", "no",
        "--save", ""
      ]

      portMappings = [
        {
          containerPort = var.container_port
          hostPort      = var.container_port
          protocol      = "tcp"
        }
      ]

      healthCheck = {
        command     = ["CMD", "redis-cli", "ping"]
        interval    = 10
        timeout     = 3
        retries     = 3
        startPeriod = 5
      }

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.redis.name
          awslogs-region        = data.aws_region.current.name
          awslogs-stream-prefix = var.service_name
        }
      }
    }
  ])

  tags = local.common_tags
}

data "aws_region" "current" {}

# =============================================================================
# SERVICE — desired_count = 1 keeps the cache centralized; replication would
# require multiple tasks behind separate DNS records or true Redis replication,
# which we deliberately avoid here.
# =============================================================================

resource "aws_ecs_service" "redis" {
  name             = "${var.service_name}-service"
  cluster          = var.cluster_id
  task_definition  = aws_ecs_task_definition.redis.arn
  desired_count    = 1
  launch_type      = "FARGATE"
  platform_version = "1.4.0"

  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent         = 100

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [aws_security_group.redis.id]
    assign_public_ip = false
  }

  service_registries {
    registry_arn = aws_service_discovery_service.redis.arn
  }

  tags = local.common_tags
}
