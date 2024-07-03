/**
 * Copyright 2024 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

locals {
  apis = toset([
    "artifactregistry.googleapis.com",
    "compute.googleapis.com",
    "iap.googleapis.com",
    "run.googleapis.com",
    "secretmanager.googleapis.com",
    "vpcaccess.googleapis.com",
  ])
}

provider "google" {
  project = var.project_id
}

provider "google-beta" {
  project = var.project_id
}

resource "google_project_service" "apis" {
  for_each = local.apis
  service  = each.key
}

data "google_project" "project" {
}

resource "google_artifact_registry_repository" "my-repo" {
  location      = var.region
  repository_id = var.artifact_repository_id
  format        = "DOCKER"
}

// Secret Manager
resource "google_secret_manager_secret" "co-config" {
  secret_id = "cloud-orchestrator-config"

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "secret-version-basic" {
  secret      = google_secret_manager_secret.co-config.id
  secret_data = templatefile("conf.toml.tmpl", { PROJECT_ID = var.project_id })
}

resource "google_iap_brand" "project_brand" {
  support_email     = var.oauth_support_email
  application_title = "Cloud Orchestrator"
  project           = var.project_id
}

resource "google_iap_client" "project_client" {
  display_name = "IAP-co-backend-service"
  brand        = google_iap_brand.project_brand.name
}

resource "google_iap_web_backend_service_iam_member" "member" {
  for_each            = var.service_accessors
  project             = var.project_id
  web_backend_service = module.lb-http.backend_services.default.name
  role                = "roles/iap.httpsResourceAccessor"
  member              = each.key
}

module "lb-http" {
  source  = "terraform-google-modules/lb-http/google//modules/serverless_negs"
  version = "~> 11.0"

  name    = var.lb_name
  project = var.project_id

  load_balancing_scheme           = "EXTERNAL_MANAGED"
  ssl                             = true
  managed_ssl_certificate_domains = [var.domain]
  http_forward                    = false

  backends = {
    default = {
      protocol    = "HTTPS"
      description = null
      groups = [
        {
          group = google_compute_region_network_endpoint_group.serverless_neg.id
        }
      ]
      enable_cdn = false

      iap_config = {
        enable               = true
        oauth2_client_id     = google_iap_client.project_client.client_id
        oauth2_client_secret = google_iap_client.project_client.secret
      }
      log_config = {
        enable = false
      }
    }
  }
}

resource "google_compute_region_network_endpoint_group" "serverless_neg" {
  provider              = google-beta
  name                  = "serverless-neg"
  network_endpoint_type = "SERVERLESS"
  region                = var.region
  cloud_run {
    service = var.cloud_run_name
  }
}

resource "google_service_account" "service_account" {
  account_id   = "cloud-orchestrator"
  display_name = "Service Account used for Cloud Orchestrator"
}

resource "google_secret_manager_secret_iam_member" "member" {
  secret_id = google_secret_manager_secret.co-config.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = google_service_account.service_account.member
}

resource "google_project_iam_member" "member" {
  project = var.project_id
  role    = "roles/compute.admin"
  member  = google_service_account.service_account.member
}

# Networking
resource "google_compute_network" "network" {
  name                    = "default"
  auto_create_subnetworks = true
}

resource "google_vpc_access_connector" "connector" {
  region        = var.region
  name          = var.serverless_connector_name
  ip_cidr_range = "10.8.0.0/28"
  network       = google_compute_network.network.id
}

# Firewall
resource "google_compute_firewall" "default" {
  name    = "allow-cloud-orchestrator"
  network = google_compute_network.network.name

  allow {
    protocol = "tcp"
    ports    = ["1080", "1443", "15550-15599"]
  }

  allow {
    protocol = "udp"
    ports    = ["15550-15599"]
  }

  source_ranges = ["0.0.0.0/0"]
}

locals {
  image = "${google_artifact_registry_repository.my-repo.location}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.my-repo.name}/cloud-orchestrator:latest"
}

output "step_1_docker_build" {
  value = "docker build -t ${local.image} ."
}

output "step_2_docker_push" {
  value = "docker push ${local.image}"
}

output "step_3_cloud_run_deploy" {
  value = <<EOF
gcloud run deploy example \
  --image=${local.image} \
  --no-allow-unauthenticated \
  --port=8080 \
  --service-account=${google_service_account.service_account.email} \
  --set-env-vars='CONFIG_FILE=/config/conf.toml' --set-env-vars='IAP_AUDIENCE=/projects/${data.google_project.project.number}/global/backendServices/${nonsensitive(module.lb-http.backend_services.default.generated_id)}' \
  --set-secrets=/config/conf.toml=cloud-orchestrator-config:latest \
  --ingress=internal-and-cloud-load-balancing \
  --vpc-connector=${google_vpc_access_connector.connector.id} \
  --vpc-egress=private-ranges-only \
  --region=${var.region} \
  --project=${var.project_id}
EOF
}

output "step_4_gcloud_run_add_iam" {
  value = "gcloud run services add-iam-policy-binding ${var.cloud_run_name} --member=serviceAccount:service-${data.google_project.project.number}@gcp-sa-iap.iam.gserviceaccount.com --role=roles/run.invoker"
}
