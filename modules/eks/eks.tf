# EKS cluster IAM role para o control plane
resource "aws_iam_role" "eks_cluster" {
  name = "${var.name_prefix}-eks-cluster-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action    = "sts:AssumeRole"
        Effect    = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.name_prefix}-eks-cluster-cluster-role"
  }
}

resource "aws_iam_role_policy_attachment" "eks_cluster_AmazonEKSClusterPolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster.name
}


# EKS Node Group IAM role para os nodes
resource "aws_iam_role" "eks_nodes" {
  name = "${var.name_prefix}-eks-cluster-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action    = "sts:AssumeRole"
        Effect    = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.name_prefix}-eks-cluster-node-role"
  }
}

resource "aws_iam_role_policy_attachment" "eks_nodes_AmazonEKSWorkerNodePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.eks_nodes.name
}

resource "aws_iam_role_policy_attachment" "eks_nodes_AmazonEKS_CNI_Policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.eks_nodes.name
}

resource "aws_iam_role_policy_attachment" "eks_nodes_AmazonEC2ContainerRegistryReadOnly" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.eks_nodes.name
}


# Cluster EKS
resource "aws_eks_cluster" "main" {
  name     = "${var.name_prefix}-eks-cluster"
  role_arn = aws_iam_role.eks_cluster.arn
  version  = "1.36"

  vpc_config {
    # ENIs do control plane em subnets privadas
    subnet_ids = var.private_subnet_ids
  }

  tags = {
    Name = "${var.name_prefix}-eks-cluster"
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_AmazonEKSClusterPolicy
  ]
}


# EKS Managed Node Group
resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.name_prefix}-eks-cluster-nodes"
  node_role_arn   = aws_iam_role.eks_nodes.arn

  # Nodes na subnet privada
  subnet_ids = var.private_subnet_ids

  instance_types = ["m7i-flex.large"]
  disk_size      = 20

  scaling_config {
    desired_size = 2
    min_size     = 1
    max_size     = 4
  }

  labels = {
    "alpha.eksctl.io/cluster-name" = "${var.name_prefix}-eks-cluster"
  }

  # Opicional: força o update quando o node group mudar
  update_config {
    max_unavailable = 1
  }

  tags = {
    Name = "${var.name_prefix}-eks-cluster-nodes"
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_nodes_AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.eks_nodes_AmazonEKS_CNI_Policy,
    aws_iam_role_policy_attachment.eks_nodes_AmazonEC2ContainerRegistryReadOnly,
    aws_eks_cluster.main
  ]
}


# EKS Add-ons
resource "aws_eks_addon" "coredns" {
  cluster_name = aws_eks_cluster.main.name
  addon_name   = "coredns"

  depends_on = [aws_eks_cluster.main, aws_eks_node_group.main]
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name = aws_eks_cluster.main.name
  addon_name   = "kube-proxy"

  depends_on = [aws_eks_cluster.main, aws_eks_node_group.main]
}

resource "aws_eks_addon" "vpc_cni" {
  cluster_name = aws_eks_cluster.main.name
  addon_name   = "vpc-cni"

  depends_on = [aws_eks_cluster.main, aws_eks_node_group.main]
}

# OIDC Provider - necessário para IRSA
data "tls_certificate" "eks" {
  url = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  url             = aws_eks_cluster.main.identity[0].oidc[0].issuer
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]

  tags = {
    Name = "${var.name_prefix}-eks-oidc"
  }

  depends_on = [aws_eks_cluster.main]
}


# EBS CSI Driver - necessário para provisionar PersistentVolumes
# IAM Role para o EBS CSI Driver (IRSA)
data "aws_iam_policy_document" "ebs_csi_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.eks.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${trimprefix(aws_eks_cluster.main.identity[0].oidc[0].issuer, "https://")}:sub"
      values   = ["system:serviceaccount:kube-system:ebs-csi-controller-sa"]
    }

    condition {
      test     = "StringEquals"
      variable = "${trimprefix(aws_eks_cluster.main.identity[0].oidc[0].issuer, "https://")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ebs_csi" {
  name               = "${var.name_prefix}-eks-ebs-csi-role"
  assume_role_policy = data.aws_iam_policy_document.ebs_csi_assume_role.json

  tags = {
    Name = "${var.name_prefix}-eks-ebs-csi-role"
  }
}

resource "aws_iam_role_policy_attachment" "ebs_csi_AmazonEBSCSIDriverPolicy" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
  role       = aws_iam_role.ebs_csi.name
}

# Add-on do EBS CSI Driver
resource "aws_eks_addon" "ebs_csi" {
  cluster_name             = aws_eks_cluster.main.name
  addon_name               = "aws-ebs-csi-driver"
  service_account_role_arn = aws_iam_role.ebs_csi.arn

  depends_on = [
    aws_eks_node_group.main,
    aws_iam_role_policy_attachment.ebs_csi_AmazonEBSCSIDriverPolicy
  ]
}

# StorageClass padrão - gp3 via EBS CSI Driver
resource "kubernetes_storage_class_v1" "gp3" {
  metadata {
    name = "gp3"
    annotations = {
      # Marca como StorageClass padrão do cluster
      "storageclass.kubernetes.io/is-default-class" = "true"
    }
  }

  # Provisionador do EBS CSI Driver
  storage_provisioner    = "ebs.csi.aws.com"
  reclaim_policy         = "Delete"
  volume_binding_mode    = "WaitForFirstConsumer"
  allow_volume_expansion = true

  parameters = {
    type      = "gp3"
    fsType    = "ext4"
    encrypted = "true"
  }

  depends_on = [aws_eks_addon.ebs_csi]
}