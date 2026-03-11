# --- Cabotage Namespace ---
# Step 2 in start-cluster

resource "kubernetes_namespace_v1" "cabotage" {
  metadata {
    name = "cabotage"
  }
}
