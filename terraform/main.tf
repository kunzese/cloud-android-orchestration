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

// docker build -t us-central1-docker.pkg.dev/kunzese-fast-demo-co-ko56/my-repository/cloud-orchestrator:latest .
// docker push us-central1-docker.pkg.dev/kunzese-fast-demo-co-ko56/my-repository/cloud-orchestrator:latest
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

# import {
#   id = "projects/525833519488/brands/525833519488"
#   to = google_iap_brand.project_brand
# }

# import {
#   id = "projects/525833519488/brands/525833519488/identityAwareProxyClients/525833519488-l515r5d03o3q04q9voe59b3vs0kclr8p.apps.googleusercontent.com"
#   to = google_iap_client.project_client
# }

resource "google_iap_client" "project_client" {
  display_name = "IAP-co-backend-service"
  brand        = google_iap_brand.project_brand.name
}

resource "google_iap_web_backend_service_iam_binding" "binding" {
  project             = var.project_id
  web_backend_service = module.lb-http.backend_services.default.name
  role                = "roles/iap.httpsResourceAccessor"
  members             = var.service_accessors
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
    service = google_cloud_run_service.default.name
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

resource "google_cloud_run_service" "default" {
  name     = "example"
  location = var.region

  template {
    spec {
      service_account_name = google_service_account.service_account.email
      containers {
        image = "gcr.io/cloudrun/hello"

        volume_mounts {
          mount_path = "/config"
          name       = "secret-1"
        }

        env {
          name  = "CONFIG_FILE"
          value = "/config/conf.toml"
        }

        env {
          name  = "IAP_AUDIENCE"
          value = "" // TODO: how to manage the audience (terraform cycle)?
        }
      }

      volumes {
        name = "secret-1"
        secret {
          secret_name = google_secret_manager_secret.co-config.secret_id
          items {
            key  = "latest"
            path = "./conf.toml"
          }
        }
      }
    }
  }

  metadata {
    annotations = {
      # For valid annotation values and descriptions, see
      # https://cloud.google.com/sdk/gcloud/reference/run/deploy#--ingress
      "run.googleapis.com/ingress" = "internal-and-cloud-load-balancing"
    }
  }

  lifecycle {
    ignore_changes = [
      template[0].spec[0].containers[0].image,
      template[0].spec[0].containers[0].env // TODO: is there a way to only ignore IAP_AUDIENCE?
    ]
  }
}

output "image_name" {
  value = "${google_artifact_registry_repository.my-repo.location}.pkg.dev/kunzese-fast-demo-co-ko56/${google_artifact_registry_repository.my-repo.name}/cloud-orchestrator:latest"
}

output "update-container-image" {
  value = "gcloud run services update ${google_cloud_run_service.default.name} --region=${google_cloud_run_service.default.location} --image=${google_artifact_registry_repository.my-repo.location}.pkg.dev/kunzese-fast-demo-co-ko56/${google_artifact_registry_repository.my-repo.name}/cloud-orchestrator:latest --update-env-vars=IAP_AUDIENCE=/projects/${data.google_project.project.number}/global/backendServices/${nonsensitive(module.lb-http.backend_services.default.generated_id)}"
}

resource "google_cloud_run_service_iam_member" "public-access" {
  location = google_cloud_run_service.default.location
  project  = google_cloud_run_service.default.project
  service  = google_cloud_run_service.default.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:service-${data.google_project.project.number}@gcp-sa-iap.iam.gserviceaccount.com"
}
