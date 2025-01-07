

provider "kubernetes" {
  config_path = "~/.kube/config"  # Your kubeconfig path
}

# Kubernetes Deployment
resource "kubernetes_deployment" "chat_interface" {
  metadata {
    name = "chat-interface"
    labels = {
      app = "chat-interface"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "chat-interface"
      }
    }

    template {
      metadata {
        labels = {
          app = "chat-interface"
        }
      }

      spec {
        container {
          name  = "chat-interface"
          image = "339712897205.dkr.ecr.us-east-2.amazonaws.com/chat-interface:v1"
          
          port {
            container_port = 80
          }

          resources {
            requests = {
              cpu    = "250m"
              memory = "512Mi"
            }
            limits = {
              cpu    = "500m"
              memory = "1Gi"
            }
          }
        }
      }
    }
  }
}

# Kubernetes Service
resource "kubernetes_service" "chat_interface" {
  metadata {
    name = "chat-interface-service"
  }

  spec {
    selector = {
      app = "chat-interface"
    }

    port {
      port        = 80
      target_port = 80
      protocol    = "TCP"
    }

    type = "LoadBalancer"
  }
}
# EKS Cluster
resource "aws_eks_cluster" "main" {
  name     = "chat-interface-cluster"
  role_arn = aws_iam_role.eks_cluster.arn
  version  = "1.27"  # Specify your desired version

  vpc_config {
    subnet_ids = ["subnet-xxxxx", "subnet-yyyyy"]  # Replace with your subnet IDs
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy
  ]
}

# Node Group
resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "chat-interface-nodes"
  node_role_arn   = aws_iam_role.eks_nodes.arn
  subnet_ids      = ["subnet-xxxxx", "subnet-yyyyy"]  # Replace with your subnet IDs

  scaling_config {
    desired_size = 2
    max_size     = 3
    min_size     = 1
  }

  instance_types = ["t3.medium"]

  depends_on = [
    aws_iam_role_policy_attachment.eks_worker_node_policy,
    aws_iam_role_policy_attachment.eks_cni_policy,
    aws_iam_role_policy_attachment.eks_container_registry_policy
  ]
}

# IAM Roles and Policies for EKS
resource "aws_iam_role" "eks_cluster" {
  name = "eks-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster.name
}

resource "aws_iam_role" "eks_nodes" {
  name = "eks-node-group-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "eks_worker_node_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.eks_nodes.name
}

resource "aws_iam_role_policy_attachment" "eks_cni_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.eks_nodes.name
}

resource "aws_iam_role_policy_attachment" "eks_container_registry_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.eks_nodes.name
}