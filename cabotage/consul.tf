# --- Consul ---
# Step 7 in start-cluster
#
# Replaces: manifests/cabotage/consul/
#           scripts/cabotage/consul/bootstrap-acls
#           scripts/cabotage/vault/bootstrap-acls (Consul ACL portion)
#
# Existing clusters — import before apply:
#
#   terraform import 'module.cabotage.kubernetes_secret_v1.consul_gossip_key' 'cabotage/consul-gossip-key'
#   terraform import 'module.cabotage.kubernetes_secret_v1.consul_agent_token' 'cabotage/consul-agent-token'
#   terraform import 'module.cabotage.kubernetes_config_map_v1.consul' 'cabotage/consul'
#   terraform import 'module.cabotage.kubernetes_config_map_v1.consul_scripts' 'cabotage/consul-scripts'
#   terraform import 'module.cabotage.kubernetes_stateful_set_v1.consul' 'cabotage/consul'
#   terraform import 'module.cabotage.kubernetes_pod_disruption_budget_v1.consul' 'cabotage/consul'
#   terraform import 'module.cabotage.kubernetes_service_v1.consul' 'cabotage/consul'
#   terraform import 'module.cabotage.kubernetes_service_v1.consul_ingress' 'cabotage/consul-ingress'
#   terraform import 'module.cabotage.kubernetes_service_v1.consul_api' 'cabotage/consul-api'

# --- Gossip Encryption Key ---

resource "random_id" "consul_gossip_key" {
  byte_length = 32
}

resource "kubernetes_secret_v1" "consul_gossip_key" {
  metadata {
    name      = "consul-gossip-key"
    namespace = kubernetes_namespace_v1.cabotage.metadata[0].name
  }

  data = {
    key = random_id.consul_gossip_key.b64_std
  }

  lifecycle {
    ignore_changes = [data]
  }
}

# --- Agent Token (placeholder until bootstrap) ---

resource "kubernetes_secret_v1" "consul_agent_token" {
  metadata {
    name      = "consul-agent-token"
    namespace = kubernetes_namespace_v1.cabotage.metadata[0].name
  }

  data = {
    token = "null"
  }

  lifecycle {
    ignore_changes = [data]
  }
}

# --- ConfigMaps ---

resource "kubernetes_config_map_v1" "consul" {
  metadata {
    name      = "consul"
    namespace = kubernetes_namespace_v1.cabotage.metadata[0].name
  }

  data = {
    "server.json" = jsonencode({
      ca_file                = "/var/run/secrets/cabotage.io/ca.crt"
      cert_file              = "/etc/tls/tls.crt"
      key_file               = "/etc/tls/tls.key"
      primary_datacenter     = var.consul_datacenter
      acl = {
        enabled                = true
        default_policy         = "deny"
        enable_key_list_policy = true
      }
      verify_incoming        = false
      verify_outgoing        = true
      verify_server_hostname = true
      ports = {
        https = 8443
      }
      autopilot = {
        cleanup_dead_servers      = true
        last_contact_threshold    = "300ms"
        max_trailing_logs         = 250
        server_stabilization_time = "10s"
      }
    })
  }
}

resource "kubernetes_config_map_v1" "consul_scripts" {
  metadata {
    name      = "consul-scripts"
    namespace = kubernetes_namespace_v1.cabotage.metadata[0].name
  }

  data = {
    "write-secrets.sh" = <<-EOT
      if [ "$CONSUL_ACL_AGENT_TOKEN" != "null" ]; then
        cat > /etc/consul/secrets/acl_agent_token.json <<EOF
      {"acl": {"tokens": {"agent": "$CONSUL_ACL_AGENT_TOKEN"}}}
      EOF
        echo "Wrote /etc/consul/secrets/acl_agent_token.json"
      fi
      cat > /etc/consul/secrets/encrypt.json <<EOF
      {"encrypt": "$GOSSIP_ENCRYPTION_KEY"}
      EOF
      echo "Wrote /etc/consul/secrets/encrypt.json"
    EOT
  }
}

# --- StatefulSet ---

resource "kubernetes_stateful_set_v1" "consul" {
  metadata {
    name      = "consul"
    namespace = kubernetes_namespace_v1.cabotage.metadata[0].name
  }

  spec {
    service_name          = "consul"
    replicas              = var.consul_replicas
    pod_management_policy = "Parallel"

    selector {
      match_labels = {
        app = "consul"
      }
    }

    update_strategy {
      type = "RollingUpdate"
    }

    template {
      metadata {
        labels = {
          app                        = "consul"
          "ca-admission.cabotage.io" = "true"
        }
      }

      spec {
        automount_service_account_token = false
        enable_service_links            = false

        security_context {
          run_as_non_root = true
          run_as_user     = 20000
          run_as_group    = 20000
          fs_group        = 20000
        }

        affinity {
          pod_anti_affinity {
            required_during_scheduling_ignored_during_execution {
              label_selector {
                match_expressions {
                  key      = "app"
                  operator = "In"
                  values   = ["consul"]
                }
              }
              topology_key = "failure-domain.beta.kubernetes.io/zone"
            }
          }
        }

        init_container {
          name  = "consul-secret-writer"
          image = "alpine:3.17"

          env {
            name = "CONSUL_ACL_AGENT_TOKEN"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.consul_agent_token.metadata[0].name
                key  = "token"
              }
            }
          }

          env {
            name = "GOSSIP_ENCRYPTION_KEY"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.consul_gossip_key.metadata[0].name
                key  = "key"
              }
            }
          }

          command = ["/bin/sh"]
          args    = ["/opt/scripts/write-secrets.sh"]

          volume_mount {
            name       = "consul-secrets"
            mount_path = "/etc/consul/secrets"
          }

          volume_mount {
            name       = "consul-scripts"
            mount_path = "/opt/scripts"
          }
        }

        container {
          name  = "consul"
          image = var.consul_image

          env {
            name = "POD_IP"
            value_from {
              field_ref {
                field_path = "status.podIP"
              }
            }
          }

          env {
            name = "NAMESPACE"
            value_from {
              field_ref {
                field_path = "metadata.namespace"
              }
            }
          }

          env {
            name  = "INITIAL_CLUSTER_SIZE"
            value = tostring(var.consul_replicas)
          }

          env {
            name  = "CONSUL_DISABLE_PERM_MGMT"
            value = "true"
          }

          args = [
            "agent",
            "-advertise=$(POD_IP)",
            "-bind=0.0.0.0",
            "-bootstrap-expect=$(INITIAL_CLUSTER_SIZE)",
            "-retry-join=consul-0.consul.$(NAMESPACE).svc.cluster.local",
            "-retry-join=consul-1.consul.$(NAMESPACE).svc.cluster.local",
            "-retry-join=consul-2.consul.$(NAMESPACE).svc.cluster.local",
            "-client=0.0.0.0",
            "-domain=cluster.local",
            "-datacenter=${var.consul_datacenter}",
            "-config-file=/etc/consul/config/server.json",
            "-config-dir=/etc/consul/secrets/",
            "-server",
            "-ui",
          ]

          port {
            container_port = 8300
            name           = "server-rpc"
          }

          port {
            container_port = 8301
            name           = "serf-lan"
          }

          port {
            container_port = 8302
            name           = "serf-wan"
          }

          port {
            container_port = 8500
            name           = "http-api"
          }

          port {
            container_port = 8600
            name           = "dns-api"
          }

          volume_mount {
            name       = "tls"
            mount_path = "/etc/tls"
          }

          volume_mount {
            name       = "consul-config"
            mount_path = "/etc/consul/config"
          }

          volume_mount {
            name       = "consul-secrets"
            mount_path = "/etc/consul/secrets"
          }

          volume_mount {
            name       = "consul-data"
            mount_path = "/consul/data"
          }

          readiness_probe {
            http_get {
              path = "/v1/status/leader"
              port = 8500
            }
            initial_delay_seconds = 10
            period_seconds        = 30
          }

          lifecycle {
            pre_stop {
              exec {
                command = ["/bin/sh", "-c", "consul leave"]
              }
            }
          }
        }

        volume {
          name = "tls"

          csi {
            driver    = "csi.cert-manager.io"
            read_only = true
            volume_attributes = {
              "csi.cert-manager.io/issuer-name" = "certificate-approver-ca-issuer"
              "csi.cert-manager.io/issuer-kind" = "ClusterIssuer"
              "csi.cert-manager.io/duration"    = "9000h"
              "csi.cert-manager.io/dns-names"   = "$${POD_NAME}.consul.$${POD_NAMESPACE}.svc.cluster.local, consul.$${POD_NAMESPACE}.svc.cluster.local, consul.$${POD_NAMESPACE}.svc.cluster, consul.$${POD_NAMESPACE}.svc, server.${var.consul_datacenter}.cluster.local"
              "csi.cert-manager.io/fs-group"    = "20000"
            }
          }
        }

        volume {
          name = "consul-secrets"
          empty_dir {
            medium     = "Memory"
            size_limit = "1M"
          }
        }

        volume {
          name = "consul-config"
          config_map {
            name = kubernetes_config_map_v1.consul.metadata[0].name
          }
        }

        volume {
          name = "consul-scripts"
          config_map {
            name = kubernetes_config_map_v1.consul_scripts.metadata[0].name
          }
        }
      }
    }

    volume_claim_template {
      metadata {
        name = "consul-data"
        # Workaround: provider imports VCT with namespace="" which it
        # normalizes to "default", then forces replacement. Omitting
        # namespace causes the same issue. Setting it explicitly to
        # match the imported state prevents the forced replacement.
        namespace = ""
      }

      spec {
        access_modes = ["ReadWriteOnce"]

        resources {
          requests = {
            storage = var.consul_storage_size
          }
        }
      }
    }
  }

  depends_on = [
    helm_release.cert_manager_csi_driver,
    kubectl_manifest.certificate_approver_ca_issuer,
    null_resource.ca_admission_webhook_ready,
    null_resource.sign_intermediate_cas,
  ]
}

# --- PodDisruptionBudget ---

resource "kubernetes_pod_disruption_budget_v1" "consul" {
  metadata {
    name      = "consul"
    namespace = kubernetes_namespace_v1.cabotage.metadata[0].name
  }

  spec {
    max_unavailable = "1"

    selector {
      match_labels = {
        app = "consul"
      }
    }
  }
}

# --- Services ---

# Headless service for StatefulSet DNS
resource "kubernetes_service_v1" "consul" {
  metadata {
    name      = "consul"
    namespace = kubernetes_namespace_v1.cabotage.metadata[0].name
    labels = {
      app = "consul"
    }
  }

  spec {
    cluster_ip                  = "None"
    publish_not_ready_addresses = true

    selector = {
      app = "consul"
    }

    port {
      name        = "https"
      port        = 8443
      target_port = 8443
      protocol    = "TCP"
    }
  }
}

resource "kubernetes_service_v1" "consul_ingress" {
  metadata {
    name      = "consul-ingress"
    namespace = kubernetes_namespace_v1.cabotage.metadata[0].name
    labels = {
      app = "consul"
    }
  }

  spec {
    publish_not_ready_addresses = true

    selector = {
      app = "consul"
    }

    port {
      name        = "https"
      port        = 8443
      target_port = 8443
      protocol    = "TCP"
    }
  }
}

resource "kubernetes_service_v1" "consul_api" {
  metadata {
    name      = "consul-api"
    namespace = kubernetes_namespace_v1.cabotage.metadata[0].name
    labels = {
      app = "consul"
    }
  }

  spec {
    publish_not_ready_addresses = true

    selector = {
      app = "consul"
    }

    port {
      port        = 443
      target_port = 8443
      protocol    = "TCP"
    }
  }
}
