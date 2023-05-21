data "aws_caller_identity" "current" {}

resource "aws_eks_cluster" "default" {
  name    = "my-cluster"
  version = "1.25"
  /* vpc_id            = module.vpc_example_ipv6.vpc_id */
  role_arn  = aws_iam_role.example.arn
  /* ip_family = "ipv6" */
  vpc_config {
    endpoint_private_access = true
    endpoint_public_access  = true
    subnet_ids              = [element(module.vpc_example_ipv6.public_subnets, 0), element(module.vpc_example_ipv6.public_subnets, 1)]
  }
  kubernetes_network_config{
    ip_family = "ipv6"
  }
}

resource "aws_eks_node_group" "example" {
  cluster_name    = aws_eks_cluster.default.name
  node_group_name = "demo"
  node_role_arn   = aws_iam_role.managed-ng.arn
  subnet_ids      = [element(module.vpc_example_ipv6.public_subnets, 0), element(module.vpc_example_ipv6.public_subnets, 1)]
  instance_types  = ["t3a.micro"]

  scaling_config {
    desired_size = 1
    max_size     = 2
    min_size     = 1
  }

  update_config {
    max_unavailable = 1
  }

  # Ensure that IAM Role permissions are created before and deleted after EKS Node Group handling.
  # Otherwise, EKS will not be able to properly delete EC2 Instances and Elastic Network Interfaces.
  depends_on = [
    aws_iam_role_policy_attachment.managed-ng-AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.managed-ng-AmazonEKS_CNI_Policy,
    aws_iam_role_policy_attachment.managed-ng-AmazonEC2ContainerRegistryReadOnly,
  ]
}


output "cluster_endpoint" {
  value = aws_eks_cluster.default.endpoint
}

/* output "kubectl_config" {
  value = <<EOF
apiVersion: v1
clusters:
- name: default
  cluster:
    server: ${aws_eks_cluster.default.endpoint}
    aws_access_key_id: ${aws_access_key_id}
    aws_secret_access_key: ${aws_secret_access_key}
    region: ${aws_region}
contexts:
- name: default
  cluster: default
  namespace: default
users:
- name: default
  user:
    username: ${aws_eks_cluster.default.kube_config.username}
    password: ${aws_eks_cluster.default.kube_config.password}
EOF
} */

data "aws_iam_policy_document" "assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "example" {
  name               = "eks-cluster-example"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}

resource "aws_iam_role_policy_attachment" "example-AmazonEKSClusterPolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.example.name
}

# Optionally, enable Security Groups for Pods
# Reference: https://docs.aws.amazon.com/eks/latest/userguide/security-groups-for-pods.html
resource "aws_iam_role_policy_attachment" "example-AmazonEKSVPCResourceController" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
  role       = aws_iam_role.example.name
}


resource "aws_iam_role" "managed-ng" {
  name = "eks-node-group-managed-ng"

  assume_role_policy = jsonencode({
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
    Version = "2012-10-17"
  })
}

resource "aws_iam_role_policy_attachment" "managed-ng-AmazonEKSWorkerNodePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.managed-ng.name
}

resource "aws_iam_role_policy_attachment" "managed-ng-AmazonEKS_CNI_Policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.managed-ng.name
}

resource "aws_iam_role_policy_attachment" "managed-ng-AmazonEC2ContainerRegistryReadOnly" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.managed-ng.name
}


/* resource "aws_iam_role" "vpc-cni" {
  name                        = "my-vpc-cni-role"
  assume_role_policy_document = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "vpc-cni-policy-attachment" {
  role_name  = aws_iam_role.vpc-cni.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_eks_addon_vpc_cni" "default" {
  cluster_name = aws_eks_cluster.default.name
  name         = "vpc-cni"
  enabled      = true
}

resource "aws_iam_role" "core-dns" {
  name                        = "my-core-dns-role"
  assume_role_policy_document = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "core-dns-policy-attachment" {
  role_name  = aws_iam_role.core-dns.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CoreDNS_Policy"
}

resource "aws_eks_addon_core_dns" "default" {
  cluster_name = aws_eks_cluster.default.name
  name         = "core-dns"
  enabled      = true
}

resource "aws_iam_role" "kube-proxy" {
  name                        = "my-kube-proxy-role"
  assume_role_policy_document = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "kube-proxy-policy-attachment" {
  role_name  = aws_iam_role.kube-proxy.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
} */
