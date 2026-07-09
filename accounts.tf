# =============================================================================
# MULTI-CUENTA - AWS Organizations (Sandbox, UAT, PreProd, Prod)
# =============================================================================
#
# Estrategia de cuentas separadas:
# - Sandbox:      Experimentación libre, datos efímeros, sin impacto
# - UAT:          Pruebas de aceptación con datos de prueba
# - PreProd:      Réplica de producción para validación final
# - Prod:         Ambiente productivo con controles estrictos
#
# Habilitar con: enable_multi_account = true
# =============================================================================

# -----------------------------------------------------------------------------
# AWS Organizations (solo si se habilita multi-cuenta)
# -----------------------------------------------------------------------------

resource "aws_organizations_organization" "data_lake" {
  count = var.enable_multi_account ? 1 : 0

  feature_set = "ALL"

  enabled_policy_types = [
    "SERVICE_CONTROL_POLICY"
  ]
}

# OU (Organizational Unit) para el Data Lake
resource "aws_organizations_organizational_unit" "data_lake" {
  count     = var.enable_multi_account ? 1 : 0
  name      = "${var.project_name}-environments"
  parent_id = aws_organizations_organization.data_lake[0].roots[0].id
}

# Cuenta: Sandbox
resource "aws_organizations_account" "sandbox" {
  count     = var.enable_multi_account ? 1 : 0
  name      = "${var.project_name}-sandbox"
  email     = var.account_emails["sandbox"]
  parent_id = aws_organizations_organizational_unit.data_lake[0].id
  role_name = "OrganizationAccountAccessRole"

  tags = merge(local.common_tags, { Environment = "sandbox" })

  lifecycle {
    ignore_changes = [role_name]
  }
}

# Cuenta: UAT
resource "aws_organizations_account" "uat" {
  count     = var.enable_multi_account ? 1 : 0
  name      = "${var.project_name}-uat"
  email     = var.account_emails["uat"]
  parent_id = aws_organizations_organizational_unit.data_lake[0].id
  role_name = "OrganizationAccountAccessRole"

  tags = merge(local.common_tags, { Environment = "uat" })

  lifecycle {
    ignore_changes = [role_name]
  }
}

# Cuenta: Pre-Producción
resource "aws_organizations_account" "preprod" {
  count     = var.enable_multi_account ? 1 : 0
  name      = "${var.project_name}-preprod"
  email     = var.account_emails["preprod"]
  parent_id = aws_organizations_organizational_unit.data_lake[0].id
  role_name = "OrganizationAccountAccessRole"

  tags = merge(local.common_tags, { Environment = "preprod" })

  lifecycle {
    ignore_changes = [role_name]
  }
}

# Cuenta: Producción
resource "aws_organizations_account" "prod" {
  count     = var.enable_multi_account ? 1 : 0
  name      = "${var.project_name}-prod"
  email     = var.account_emails["prod"]
  parent_id = aws_organizations_organizational_unit.data_lake[0].id
  role_name = "OrganizationAccountAccessRole"

  tags = merge(local.common_tags, { Environment = "prod" })

  lifecycle {
    ignore_changes = [role_name]
  }
}

# SCP: Restringir regiones en sandbox (solo us-east-1)
resource "aws_organizations_policy" "sandbox_region_restrict" {
  count   = var.enable_multi_account ? 1 : 0
  name    = "${var.project_name}-sandbox-region-restrict"
  type    = "SERVICE_CONTROL_POLICY"
  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyOutsideRegion"
        Effect    = "Deny"
        Action    = "*"
        Resource  = "*"
        Condition = {
          StringNotEquals = {
            "aws:RequestedRegion" = [var.aws_region]
          }
        }
      }
    ]
  })
}

resource "aws_organizations_policy_attachment" "sandbox_region" {
  count     = var.enable_multi_account ? 1 : 0
  policy_id = aws_organizations_policy.sandbox_region_restrict[0].id
  target_id = aws_organizations_account.sandbox[0].id
}
