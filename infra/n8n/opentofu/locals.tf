locals {
  name_prefix = "abpiv-n8n"

  labels = {
    app         = "n8n"
    component   = "automation"
    environment = "production"
    managed_by  = "opentofu"
  }

  compute_labels = {
    app         = "shared-runtime"
    component   = "runtime"
    environment = "production"
    managed_by  = "opentofu"
  }

  network_cidr                     = "10.58.0.0/24"
  backup_bucket_name               = var.backup_bucket_name != "" ? var.backup_bucket_name : "${var.gcp_project_id}-n8n-backups"
  compute_instance_name            = "abpiv-runtime-vm"
  compute_data_disk_name           = "abpiv-n8n-data"
  compute_plausible_data_disk_name = "abpiv-plausible-data"

  editor_enabled = trimspace(var.editor_hostname) != ""
  editor_cloudflare_zone_id = (
    var.editor_zone_id != "" ?
    var.editor_zone_id :
    try(data.cloudflare_zones.editor[0].result[0].id, "")
  )

  editor_access_include_rules = concat(
    [
      for email in var.editor_access_allowed_emails : {
        email = {
          email = email
        }
      }
    ],
    [
      for group_id in var.editor_access_allowed_group_ids : {
        group = {
          id = group_id
        }
      }
    ]
  )

  public_forms_path_expression = join(" or ", [
    "http.request.uri.path eq \"/form\"",
    "starts_with(http.request.uri.path, \"/form/\")",
    "http.request.uri.path eq \"/form-waiting\"",
    "starts_with(http.request.uri.path, \"/form-waiting/\")",
    "http.request.uri.path eq \"/webhook\"",
    "starts_with(http.request.uri.path, \"/webhook/\")",
    "http.request.uri.path eq \"/webhook-waiting\"",
    "starts_with(http.request.uri.path, \"/webhook-waiting/\")",
  ])

  public_forms_request_expression = "(http.host eq \"${var.forms_hostname}\" and (${local.public_forms_path_expression}))"

  required_services = toset([
    "compute.googleapis.com",
    "iam.googleapis.com",
    "iap.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "oslogin.googleapis.com",
    "secretmanager.googleapis.com",
    "serviceusage.googleapis.com",
    "storage.googleapis.com",
  ])

  runtime_secrets = {
    encryption_key    = "${local.name_prefix}-encryption-key"
    postgres_password = "${local.name_prefix}-postgres-password"
  }

  plausible_runtime_secrets = {
    secret_key_base = {
      secret_id = "abpiv-plausible-secret-key-base"
    }
    postgres_password = {
      secret_id = "abpiv-plausible-postgres-password"
    }
    tunnel_token = {
      secret_id = "abpiv-plausible-tunnel-token"
    }
    backup_age_key = {
      secret_id = "abpiv-plausible-backup-age-key"
    }
  }

  github_deployer_project_roles = toset([
    "roles/compute.instanceAdmin.v1",
    "roles/compute.networkAdmin",
    "roles/compute.osAdminLogin",
    "roles/compute.securityAdmin",
    "roles/iam.serviceAccountAdmin",
    "roles/iap.tunnelResourceAccessor",
    "roles/logging.configWriter",
    "roles/monitoring.editor",
    "roles/secretmanager.admin",
    "roles/serviceusage.serviceUsageAdmin",
    "roles/resourcemanager.projectIamAdmin",
    "roles/storage.admin",
  ])
}
