resource "google_project_service" "required" {
  for_each = local.required_services

  project            = var.gcp_project_id
  service            = each.value
  disable_on_destroy = false
}

resource "google_compute_network" "n8n" {
  name                    = "${local.name_prefix}-network"
  auto_create_subnetworks = false

  depends_on = [
    google_project_service.required["compute.googleapis.com"],
  ]
}

resource "google_compute_subnetwork" "n8n" {
  name                     = "${local.name_prefix}-subnet"
  ip_cidr_range            = local.network_cidr
  network                  = google_compute_network.n8n.id
  region                   = var.gcp_region
  private_ip_google_access = true
}

resource "google_secret_manager_secret" "runtime" {
  for_each = local.runtime_secrets

  secret_id = each.value
  labels    = local.labels

  replication {
    auto {}
  }

  depends_on = [
    google_project_service.required["secretmanager.googleapis.com"],
  ]
}
