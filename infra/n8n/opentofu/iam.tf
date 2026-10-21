resource "google_service_account" "github_deployer" {
  account_id   = "n8n-github-deployer"
  display_name = "n8n GitHub deployer"
  description  = "Dedicated service account for GitHub Actions OIDC deployments of the n8n stack."

  depends_on = [
    google_project_service.required["iam.googleapis.com"],
  ]
}

resource "google_project_iam_member" "github_deployer_project_roles" {
  for_each = local.github_deployer_project_roles

  project = var.gcp_project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.github_deployer.email}"
}

resource "google_service_account" "n8n_compute" {
  account_id   = "n8n-compute-runtime"
  display_name = "ABPIV shared Compute runtime"
  description  = "Least-privilege runtime identity for the private VM shared by n8n and Plausible."

  depends_on = [
    google_project_service.required["iam.googleapis.com"],
  ]
}

resource "google_secret_manager_secret_iam_member" "compute_runtime_secret_accessor" {
  for_each = google_secret_manager_secret.runtime

  project   = var.gcp_project_id
  secret_id = each.value.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.n8n_compute.email}"
}

resource "google_secret_manager_secret_iam_member" "compute_tunnel_secret_accessor" {
  project   = var.gcp_project_id
  secret_id = google_secret_manager_secret.cloudflare_tunnel_token.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.n8n_compute.email}"
}

resource "google_secret_manager_secret_iam_member" "compute_plausible_secret_accessor" {
  for_each = google_secret_manager_secret.plausible_runtime

  project   = var.gcp_project_id
  secret_id = each.value.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.n8n_compute.email}"
}

resource "google_storage_bucket_iam_member" "compute_backup_object_user" {
  bucket = google_storage_bucket.n8n_backups.name
  role   = "roles/storage.objectUser"
  member = "serviceAccount:${google_service_account.n8n_compute.email}"
}

resource "google_project_iam_member" "compute_observability_roles" {
  for_each = toset([
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
  ])

  project = var.gcp_project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.n8n_compute.email}"
}

resource "google_service_account_iam_member" "github_deployer_compute_service_account_user" {
  service_account_id = google_service_account.n8n_compute.name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${google_service_account.github_deployer.email}"
}

resource "google_service_account_iam_member" "github_deployer_plausible_runtime_service_account_user" {
  service_account_id = "projects/${var.gcp_project_id}/serviceAccounts/plausible-analytics-vm@${var.gcp_project_id}.iam.gserviceaccount.com"
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${google_service_account.github_deployer.email}"
}

resource "google_service_account_iam_member" "github_oidc_workload_identity_user" {
  count = trimspace(var.github_oidc_principal_set) == "" ? 0 : 1

  service_account_id = google_service_account.github_deployer.name
  role               = "roles/iam.workloadIdentityUser"
  member             = var.github_oidc_principal_set
}

resource "google_service_account_iam_member" "github_oidc_service_account_token_creator" {
  count = trimspace(var.github_oidc_principal_set) == "" ? 0 : 1

  service_account_id = google_service_account.github_deployer.name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = var.github_oidc_principal_set
}
