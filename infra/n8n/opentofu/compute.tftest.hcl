mock_provider "google" {
  mock_resource "google_compute_network" {
    defaults = {
      id = "projects/abpiv-personal-brand/global/networks/abpiv-n8n-network"
    }
  }

  mock_resource "google_service_account" {
    defaults = {
      name  = "projects/abpiv-personal-brand/serviceAccounts/mocksa@abpiv-personal-brand.iam.gserviceaccount.com"
      email = "mocksa@abpiv-personal-brand.iam.gserviceaccount.com"
    }
  }
}

mock_provider "cloudflare" {}

run "private_runtime_defaults_are_safe" {
  command = plan

  assert {
    condition     = google_compute_instance.n8n.machine_type == "e2-custom-medium-6144"
    error_message = "The initial shared runtime size must remain e2-custom-medium-6144."
  }

  assert {
    condition     = google_compute_instance.n8n.deletion_protection
    error_message = "The production shared runtime must remain deletion-protected."
  }

  assert {
    condition     = length(google_compute_instance.n8n.network_interface[0].access_config) == 0
    error_message = "The private runtime VM must not have a public access configuration."
  }

  assert {
    condition     = google_compute_disk.n8n_data.size == 30
    error_message = "The independent n8n data disk must default to 30 GiB."
  }

  assert {
    condition     = google_compute_disk.plausible_data.size == 80
    error_message = "The independent Plausible data disk must default to 80 GiB."
  }

  assert {
    condition = local.required_services == toset([
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
    error_message = "Only APIs required by the current private runtime may remain in source."
  }

  assert {
    condition = alltrue([
      for role in [
        "roles/certificatemanager.editor",
        "roles/cloudsql.admin",
        "roles/compute.loadBalancerAdmin",
        "roles/run.admin",
        "roles/servicenetworking.networksAdmin",
        "roles/vpcaccess.admin",
      ] : !contains(local.github_deployer_project_roles, role)
    ])
    error_message = "No retired deployer permission may remain in the steady-state role set."
  }
}

run "managed_edge_uses_only_the_private_tunnel" {
  command = plan

  variables {
    enable_cloudflare_edge                = true
    editor_hostname                       = "workflows.lobst3rs.com"
    cloudflare_account_id                 = "mock-account"
    allanbpediniv_zone_id                 = "00000000000000000000000000000001"
    editor_zone_id                        = "00000000000000000000000000000002"
    editor_access_allowed_emails          = ["allan@example.com"]
    github_oidc_principal_set             = ""
    manage_cloudflare_access_organization = false
  }

  assert {
    condition     = cloudflare_dns_record.forms[0].type == "CNAME"
    error_message = "The public forms record must remain a Tunnel CNAME."
  }

  assert {
    condition     = cloudflare_dns_record.forms[0].content == "${cloudflare_zero_trust_tunnel_cloudflared.n8n[0].id}.cfargotunnel.com"
    error_message = "The public forms record must point only to the managed Tunnel."
  }

  assert {
    condition     = cloudflare_dns_record.editor[0].type == "CNAME"
    error_message = "The editor record must remain a Tunnel CNAME."
  }

  assert {
    condition     = cloudflare_dns_record.editor[0].content == "${cloudflare_zero_trust_tunnel_cloudflared.n8n[0].id}.cfargotunnel.com"
    error_message = "The editor record must point only to the managed Tunnel."
  }
}
