
########################################
# RDS MySQL 8.0 (writer + 1 read replica)
# Logical Order: 03
########################################
# --- Locals (rename the service account for RDS use cases) ---
# WARNING: DO NOT MODIFY random_password spec after it has been put in any env.
# --- Generate a DB password ---
resource "random_password" "sapio_mysql_root" {
  length  = 32
  special = false
}

locals {
  app_serviceaccount = "app-${local.prefix_env}-serviceaccount"
  oidc               = module.eks.oidc_provider
  sql_root_user = "sapio"
}

# --- Subnet group for RDS in your private subnets ---
resource "aws_db_subnet_group" "sapio_mysql" {
  name       = "${local.prefix_env}-sapio-mysql-subnets"
  subnet_ids = module.vpc.private_subnets

  tags = {
    Environment = local.prefix_env
    Terraform   = "true"
  }
}

# --- Security Group for RDS (allow from EKS cluster SG; adjust if needed) ---
resource "aws_security_group" "rds_mysql" {
  name        = "${local.prefix_env}-sapio-mysql-sg"
  description = "RDS MySQL access for Sapio application"
  vpc_id      = module.vpc.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Environment = local.prefix_env
    Terraform   = "true"
  }
}

# Allow MySQL from the EKS cluster security group (replace with the right SG if different in your module)
resource "aws_security_group_rule" "eks_to_rds" {
  type                     = "ingress"
  from_port                = 3306
  to_port                  = 3306
  protocol                 = "tcp"
  security_group_id        = aws_security_group.rds_mysql.id
  source_security_group_id = module.eks.cluster_security_group_id
}


# Make sure we have the right parameter group for MySQL 8.0
resource "aws_db_parameter_group" "sapio_mysql8" {
  name   = "${var.env_name}-mysql8-lctn1"
  family = "mysql8.0"

  # YQ: Here are Sapio recommended parameters for MySQL 8.0 on RDS.
  # MUST BE lower case table name.
  parameter {
    name         = "lower_case_table_names"
    value        = "1"
    apply_method = "pending-reboot"  # static; must be in place before creation
  }
  # Character set utf8mb4 and encoding utf8mb4_unicode_ci
  parameter {
    name         = "character_set_server"
    value        = "utf8mb4"
    apply_method = "pending-reboot"  # static; must be in place before creation
  }
  parameter {
    name         = "collation_server"
    value        = "utf8mb4_unicode_ci"
    apply_method = "pending-reboot"  # static; must be in place before creation
  }
  # 250 max connections
  parameter {
    name         = "max_connections"
    value        = "250"
    apply_method = "immediate"  # dynamic; can be changed on the fly
  }
  # wait timeout wait_timeout=999999
  parameter {
    name         = "wait_timeout"
    value        = "999999"
    apply_method = "immediate"  # dynamic; can be changed on the fly
  }
  # innodb_flush_log_at_trx_commit set to 2
  parameter {
    name         = "innodb_flush_log_at_trx_commit"
    value        = "2"
    apply_method = "immediate"  # dynamic; can be changed on the fly
  }
  # innodb_buffer_pool_size to 384M
  parameter {
    name         = "innodb_buffer_pool_size"
    value        = "402653184"
    apply_method = "immediate"  # dynamic; can be changed on the fly
  }
  # range_optimizer_max_mem_size = 33554432
  parameter {
    name         = "range_optimizer_max_mem_size"
    value        = "33554432"
    apply_method = "immediate"  # dynamic; can be changed on the fly
  }
  # remove only_full_group_by from default sql_mode, keep the rest from default
  # So STRICT_TRANS_TABLES, NO_ZERO_IN_DATE, NO_ZERO_DATE, ERROR_FOR_DIVISION_BY_ZERO, and NO_ENGINE_SUBSTITUTION
  parameter {
    name  = "sql_mode"
    value = "STRICT_TRANS_TABLES,NO_ZERO_IN_DATE,NO_ZERO_DATE,ERROR_FOR_DIVISION_BY_ZERO,NO_ENGINE_SUBSTITUTION"
  }
}

# Secret with desired app password
# Note this is stored for ENV variables in the app deployment.
resource "kubernetes_secret_v1" "mysql_root_creds" {
  metadata {
    name      = "mysql-root-user"
    namespace = "sapio" # only sapio app namespace pods can read this secret.
  }
  data = {
    username = local.sql_root_user
    password = random_password.sapio_mysql_root.result
  }
  type = "Opaque"
  depends_on = [kubernetes_namespace.sapio]
}

# --- Primary (writer) MySQL 8.0 instance ---
resource "aws_db_instance" "sapio_mysql" {
  identifier                 = "${local.prefix_env}-sapio-mysql"
  engine                     = "mysql"
  engine_version             = "8.0"
  instance_class             = var.mysql_instance_class
  allocated_storage          = var.mysql_allocated_storage
  storage_type               = "gp3"
  db_subnet_group_name       = aws_db_subnet_group.sapio_mysql.name
  vpc_security_group_ids     = [aws_security_group.rds_mysql.id]
  username                   = local.sql_root_user
  password                   = random_password.sapio_mysql_root.result
  port                       = 3306
  publicly_accessible        = false
  multi_az                   = var.mysql_multi_az
  backup_retention_period    = var.mysql_retention_period_days
  deletion_protection        = false
  apply_immediately          = true
  skip_final_snapshot        = var.mysql_skip_final_snapshot
  parameter_group_name       = aws_db_parameter_group.sapio_mysql8.name
  iam_database_authentication_enabled = true # optional: enable IAM DB auth

  tags = {
    Environment = local.prefix_env
    Terraform   = "true"
  }

  depends_on = [module.eks]
}

# --- Read replica (single) ---
resource "aws_db_instance" "sapio_mysql_replica" {
  identifier             = "${local.prefix_env}-sapio-mysql-replica-1"
  engine                 = "mysql"
  engine_version         = aws_db_instance.sapio_mysql.engine_version
  instance_class         = var.mysql_instance_class
  replicate_source_db    = aws_db_instance.sapio_mysql.arn
  db_subnet_group_name   = aws_db_subnet_group.sapio_mysql.name
  vpc_security_group_ids = [aws_security_group.rds_mysql.id]
  publicly_accessible    = false
  apply_immediately      = true
  skip_final_snapshot    = var.mysql_skip_final_snapshot
  # Note: For MySQL (non-Aurora), each replica has its own endpoint.

  tags = {
    Environment = local.prefix_env
    Terraform   = "true"
  }

  depends_on = [aws_db_instance.sapio_mysql]
}

# Writer endpoint in sapio namespace, creates a local cluster addressable service.
resource "kubernetes_service_v1" "mysql_writer_svc_sapio" {
  metadata {
    name      = "mysql-writer"
    namespace = "sapio"
  }
  spec {
    type          = "ExternalName"
    external_name = aws_db_instance.sapio_mysql.address  # writer endpoint DNS
  }
  depends_on = [aws_db_instance.sapio_mysql]
}

# Replica endpoint, creates a local cluster addressable service.
resource "kubernetes_service_v1" "mysql_replica_svc_sapio" {
  metadata {
    name      = "mysql-replica"
    namespace = "sapio"
  }
  spec {
    type          = "ExternalName"
    external_name = aws_db_instance.sapio_mysql_replica.address
  }
  depends_on = [aws_db_instance.sapio_mysql_replica]
}