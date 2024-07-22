resource "aws_rds_cluster" "cluster" {
  cluster_identifier     = "production-database"
  engine                 = "aurora-mysql"
  engine_version         = "8.0.mysql_aurora.3.05.2"
  availability_zones     = ["eu-west-2a", "eu-west-2b", "eu-west-2c"]
  database_name          = "prod"
  port                   = 3306
  master_username        = "admin"
  manage_master_user_password = true
  db_subnet_group_name   = aws_db_subnet_group.subnet_group.name
  vpc_security_group_ids = [aws_security_group.database.id]
  skip_final_snapshot    = true

  serverlessv2_scaling_configuration {
    max_capacity = 4
    min_capacity = 0.5
  }
}

resource "aws_rds_cluster_instance" "replica" {
  cluster_identifier   = aws_rds_cluster.cluster.id
  identifier           = "replica-a"
  instance_class       = "db.t3.medium"
  engine               = aws_rds_cluster.cluster.engine
  engine_version       = aws_rds_cluster.cluster.engine_version
  publicly_accessible  = true
  db_subnet_group_name = aws_db_subnet_group.subnet_group.name
  availability_zone    = "eu-west-2a"
  ca_cert_identifier   = "rds-ca-rsa2048-g1"
}

resource "aws_db_subnet_group" "subnet_group" {
  name = "rds"

  subnet_ids = [
    aws_subnet.private-eu-west-2a.id,
    aws_subnet.private-eu-west-2b.id,
    aws_subnet.private-eu-west-2c.id,
  ]
}
