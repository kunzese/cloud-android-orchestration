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

variable "project_id" {
  type = string
}

variable "region" {
  description = "Location for load balancer and Cloud Run resources"
  default     = "europe-west3"
}

variable "domain" {
  description = "Domain name to run the load balancer on."
  type        = string
}

variable "lb_name" {
  description = "Name for load balancer and associated resources"
  default     = "tf-cr-lb"
}

variable "oauth_support_email" {
  description = "eMail address displayed to users regarding questions about their consent"
}

variable "artifact_repository_id" {
  default = "cloud-android-orchestration"
}

variable "service_accessors" {
  description = "List of principals which should be able to call the cloud orchestrator"
  default     = []
}
