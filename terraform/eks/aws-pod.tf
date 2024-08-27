data "aws_eks_cluster" "eks_cluster" {
  name       = module.eks.cluster_name
  depends_on = [module.eks]
}

data "aws_eks_cluster_auth" "auth" {
  name = data.aws_eks_cluster.eks_cluster.name
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  token                  = data.aws_eks_cluster_auth.auth.token
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
}

resource "kubernetes_deployment" "pod_identities_demo" {
  metadata {
    name = "pod-identities-demo"
    labels = {
      app = "pod-identities-demo"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "pod-identities-demo"
      }
    }

    template {
      metadata {
        labels = {
          app = "pod-identities-demo"
        }
      }

      spec {
        container {
          name  = "main"
          image = "public.ecr.aws/aws-cli/aws-cli"
          command = ["sleep", "infinity"]
        }
      }
    }
  }
}
