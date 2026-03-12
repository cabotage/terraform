# --- Cabotage Namespace ---
# Step 2 in start-cluster

resource "kubernetes_namespace_v1" "cabotage" {
  metadata {
    name = "cabotage"
  }
}

# --- Destroy-time Cleanup ---
# Dependency chain (create order):
#   namespace → namespace_cleanup → operator_deployment → enrollments
#
# Destroy order (reverse):
#   enrollments (stuck on kopf finalizer) →
#   operator_deployment (deleted, kopf gone) →
#   namespace_cleanup (provisioner fires, strips finalizers) →
#   namespace (deletes cleanly)

resource "null_resource" "namespace_cleanup" {
  triggers = {
    kube_context = var.kube_context
    namespace    = "cabotage"
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      echo "Pre-namespace-deletion cleanup..."
      CTX="${self.triggers.kube_context}"
      NS="${self.triggers.namespace}"
      echo "  Stripping finalizers from CabotageEnrollments..."
      for name in $(kubectl --context "$CTX" get cabotageenrollments -n "$NS" -o name 2>/dev/null); do
        kubectl --context "$CTX" patch "$name" -n "$NS" \
          --type merge -p '{"metadata":{"finalizers":[]}}' 2>/dev/null && echo "    $name" || true
      done
      echo "  Deleting pods..."
      kubectl --context "$CTX" delete pods --all -n "$NS" --force --grace-period=0 2>/dev/null || true
      echo "  Stripping PVC finalizers..."
      for name in $(kubectl --context "$CTX" get pvc -n "$NS" -o name 2>/dev/null); do
        kubectl --context "$CTX" patch "$name" -n "$NS" \
          --type merge -p '{"metadata":{"finalizers":[]}}' 2>/dev/null || true
      done
      echo "Cleanup done."
    EOT
  }

  depends_on = [kubernetes_namespace_v1.cabotage]
}
