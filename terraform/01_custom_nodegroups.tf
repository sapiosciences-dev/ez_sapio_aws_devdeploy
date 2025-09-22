###############
#
# AWS Infrastructure EKS Cluster
# Defines custom node-groups for special workloads such as containers that disallows 21-day auto-termination (Sapio BLS)
# And nodes that needs GPU support (ML workloads)
# Logical order: 01
##### "Logical order" refers to the order a human would think of these executions
##### (although Terraform will determine actual order executed)
#
###############

# These are for AI project, not needed yet in the current work...
resource "kubernetes_manifest" "nodeclass_gpu" {
  manifest = {
    "apiVersion" = "eks.amazonaws.com/v1"
    "kind"       = "NodeClass"
    "metadata" = {
      "name" = "gpu"
    }
    "spec" = {
      "ephemeralStorage" = {
        "size"       = "80Gi"
        "iops"       = 3000
        "throughput" = 125
      }
    }
  }
  depends_on = [module.eks]
}

# --- GPU NodePool for NVIDIA workloads (Auto Mode) ---
resource "kubernetes_manifest" "nodepool_gpu" {
  manifest = {
    "apiVersion" = "karpenter.sh/v1"
    "kind"       = "NodePool"
    "metadata" = {
      "name" = "gpu"
    }
    "spec" = {
      "disruption" = {
        "budgets" = [{ "nodes" = "10%" }]
        "consolidateAfter"   = "1h"
        "consolidationPolicy"= "WhenEmpty"
      }
      "template" = {
        "spec" = {
          # Use your custom NodeClass if you created it; otherwise 'default'
          "nodeClassRef" = {
            "group" = "eks.amazonaws.com"
            "kind"  = "NodeClass"
            "name"  = "gpu"
          }
          "requirements" = [
            { "key" = "karpenter.sh/capacity-type",      "operator" = "In", "values" = ["on-demand"] },
            { "key" = "kubernetes.io/arch",              "operator" = "In", "values" = ["amd64"] },
            # Limit to GPU families (L40s-enabled g6e/g6 shown; adjust as needed)
            { "key" = "eks.amazonaws.com/instance-family","operator" = "In", "values" = ["g6e","g6"] }
          ]
          # Taint so only GPU-tolerating pods land here
          "taints" = [{
            "key"    = "nvidia.com/gpu"
            "effect" = "NoSchedule"
          }]
          "terminationGracePeriod" = "24h0m0s"
        }
      }
    }
  }
  depends_on = [module.eks]
}