# ==============================================================================
# AWS BACKUP — DynamoDB point-in-time recovery is enabled on the table itself,
# but AWS Backup adds an explicit vault with configurable retention, giving each
# environment (dev=7d, staging=14d, prod=30d) its own isolated backup window.
# ==============================================================================

resource "aws_iam_role" "backup" {
  name = "${var.environment}-dynamodb-backup-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "backup.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "backup" {
  role       = aws_iam_role.backup.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"
}

resource "aws_backup_vault" "main" {
  name = "${var.environment}-backup-vault"
}

resource "aws_backup_plan" "dynamodb_daily" {
  name = "${var.environment}-dynamodb-daily"

  rule {
    rule_name         = "daily-backup"
    target_vault_name = aws_backup_vault.main.name

    # 2:00 AM UTC — outside peak traffic window
    schedule = "cron(0 2 * * ? *)"

    lifecycle {
      delete_after = var.backup_retention_days
    }
  }
}

resource "aws_backup_selection" "dynamodb" {
  name         = "${var.environment}-visitor-counter"
  iam_role_arn = aws_iam_role.backup.arn
  plan_id      = aws_backup_plan.dynamodb_daily.id

  resources = [aws_dynamodb_table.visitor_counter.arn]
}
