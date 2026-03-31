# --- gVisor Runtime ---
#
# When enable_gvisor is true, this creates:
# 1. A RuntimeClass "gvisor" with scheduling constraints for gvisor-labeled nodes
# 2. An installer DaemonSet that installs runsc + containerd-shim on labeled nodes
#
# Node groups opt in via gvisor_enabled = true in their config, which adds the
# sandbox.gvisor.dev/runtime label and taint.

resource "kubernetes_runtime_class_v1" "gvisor" {
  count = var.enable_gvisor ? 1 : 0

  metadata {
    name = "gvisor"
  }

  handler = "runsc"

  scheduling {
    node_selector = {
      "sandbox.gvisor.dev/runtime" = "true"
    }

    toleration {
      key      = "sandbox.gvisor.dev/runtime"
      operator = "Equal"
      value    = "true"
      effect   = "NoSchedule"
    }
  }

  depends_on = [module.eks]
}

resource "kubernetes_service_account_v1" "gvisor_installer" {
  count = var.enable_gvisor ? 1 : 0

  metadata {
    name      = "gvisor-installer"
    namespace = var.gvisor_installer_namespace
    labels = {
      "app" = "gvisor-installer"
    }
  }

  depends_on = [module.eks]
}

resource "kubernetes_daemon_set_v1" "gvisor_installer" {
  count = var.enable_gvisor ? 1 : 0

  metadata {
    name      = "gvisor-installer"
    namespace = var.gvisor_installer_namespace
    labels = {
      "app" = "gvisor-installer"
    }
  }

  spec {
    selector {
      match_labels = {
        "app" = "gvisor-installer"
      }
    }

    strategy {
      type = "RollingUpdate"
    }

    template {
      metadata {
        labels = {
          "app" = "gvisor-installer"
        }
      }

      spec {
        service_account_name = kubernetes_service_account_v1.gvisor_installer[0].metadata[0].name
        host_pid             = true

        node_selector = {
          "sandbox.gvisor.dev/runtime" = "true"
        }

        toleration {
          key      = "sandbox.gvisor.dev/runtime"
          operator = "Equal"
          value    = "true"
          effect   = "NoSchedule"
        }

        init_container {
          name  = "install"
          image = var.gvisor_runsc_image

          security_context {
            privileged = true
          }

          command = ["/bin/sh", "-c"]
          args = [<<-EOT
            set -eu

            echo "==> Installing runsc binaries to host..."
            cp /usr/local/bin/runsc /host/usr/local/bin/runsc
            cp /usr/local/bin/containerd-shim-runsc-v1 /host/usr/local/bin/containerd-shim-runsc-v1
            chmod +x /host/usr/local/bin/runsc /host/usr/local/bin/containerd-shim-runsc-v1

            echo "==> Verifying installation..."
            nsenter -t 1 -m -- /usr/local/bin/runsc --version

            echo "==> Configuring /etc/containerd/runsc.toml..."
            cat > /host/etc/containerd/runsc.toml <<'TOML'
            [runsc_config]
              metric-server = "0.0.0.0:1337"
            TOML

            echo "==> Checking containerd config..."
            if nsenter -t 1 -m -- grep -q 'ConfigPath.*runsc.toml' /etc/containerd/config.toml; then
              echo "runsc runtime handler already configured"
            else
              echo "Adding runsc runtime handler to containerd config..."
              cat >> /host/etc/containerd/config.toml <<'EOF'

            [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runsc]
              runtime_type = "io.containerd.runsc.v1"
              pod_annotations = [ "dev.gvisor.*" ]
            [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runsc.options]
              TypeUrl = "io.containerd.runsc.v1.options"
              ConfigPath = "/etc/containerd/runsc.toml"
            EOF
              echo "==> Restarting containerd..."
              nsenter -t 1 -m -u -i -n -p -- systemctl restart containerd
              echo "==> Waiting for containerd to be ready..."
              sleep 5
              nsenter -t 1 -m -u -i -n -p -- systemctl is-active containerd
            fi

            echo "==> gVisor installation complete"
          EOT
          ]

          volume_mount {
            name       = "host"
            mount_path = "/host"
          }
        }

        container {
          name  = "pause"
          image = "registry.k8s.io/pause:3.10"

          resources {
            requests = {
              cpu    = "10m"
              memory = "16Mi"
            }
            limits = {
              cpu    = "10m"
              memory = "16Mi"
            }
          }
        }

        volume {
          name = "host"
          host_path {
            path = "/"
            type = "Directory"
          }
        }
      }
    }
  }

  wait_for_rollout = false

  depends_on = [
    kubernetes_service_account_v1.gvisor_installer,
  ]
}
