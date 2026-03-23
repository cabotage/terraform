variable "tailscale_operator_oauth_client_id" {
  description = "OAuth client ID for the Tailscale operator (platform tailnet)"
  type        = string
  default     = ""
}

variable "tailscale_operator_oauth_client_secret" {
  description = "OAuth client secret for the Tailscale operator (platform tailnet)"
  type        = string
  default     = ""
  sensitive   = true
}
