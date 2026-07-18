provider "aws" {
  region = var.aws_region
}

resource "aws_vpc" "kubernetes_cluster" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true # Required
  enable_dns_hostnames = true # <-- THIS FIXES IT

  tags = {
    "kubernetes.io/cluster/kubernetes" = "owned"
    # Karpenter
    "karpenter.sh/discovery" = "kubernetes"
  }
}

resource "aws_subnet" "kubernetes_cluster" {
  vpc_id                                      = aws_vpc.kubernetes_cluster.id
  cidr_block                                  = "10.0.0.0/24"
  map_public_ip_on_launch                     = true
  enable_resource_name_dns_a_record_on_launch = true # <-- Ensures DNS A-record registration

  tags = {
    "kubernetes.io/cluster/kubernetes" = "owned"
    # Karpenter
    "karpenter.sh/discovery" = "kubernetes"
    # public
    # "kubernetes.io/role/elb"           = "1"
    # private
    # kubernetes.io/role/internal-elb    = "1"
  }
}

resource "aws_internet_gateway" "kubernetes_cluster_gw" {
  vpc_id = aws_vpc.kubernetes_cluster.id
}

resource "aws_route_table" "kubernetes_cluster_rt" {
  vpc_id = aws_vpc.kubernetes_cluster.id
}

resource "aws_route" "default_route" {
  route_table_id         = aws_route_table.kubernetes_cluster_rt.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.kubernetes_cluster_gw.id
}

resource "aws_route_table_association" "kubernetes_cluster_rt_association" {
  subnet_id      = aws_subnet.kubernetes_cluster.id
  route_table_id = aws_route_table.kubernetes_cluster_rt.id
}

resource "aws_security_group" "k8s" {
  name        = "k8s-security-group"
  description = "Allow SSH and outbound traffic"
  vpc_id      = aws_vpc.kubernetes_cluster.id

  tags = {
    Name                               = "k8s-security-group"
    "kubernetes.io/cluster/kubernetes" = "owned"
    # Karpenter
    "karpenter.sh/discovery" = "kubernetes"
  }
}

resource "aws_security_group_rule" "ssh" {
  type              = "ingress"
  security_group_id = aws_security_group.k8s.id

  from_port = 22
  to_port   = 22
  protocol  = "tcp"

  cidr_blocks = ["0.0.0.0/0"]

  description = "Allow SSH access"
}

resource "aws_security_group_rule" "internal" {
  type              = "ingress"
  security_group_id = aws_security_group.k8s.id

  from_port = 0
  to_port   = 0
  protocol  = "-1"

  self = true
}

resource "aws_security_group_rule" "egress" {
  type              = "egress"
  security_group_id = aws_security_group.k8s.id

  from_port = 0
  to_port   = 0
  protocol  = "-1"

  cidr_blocks = ["0.0.0.0/0"]

  description = "Allow all outbound traffic"
}

resource "aws_instance" "control_plane" {
  ami                         = data.aws_ami.ubuntu_ami.id
  instance_type               = "c7i-flex.large"
  # instance_type               = "t3.small"
  key_name                    = data.aws_key_pair.key_pair.key_name
  iam_instance_profile        = aws_iam_instance_profile.control_plane_profile.name
  vpc_security_group_ids      = [aws_security_group.k8s.id]
  subnet_id                   = aws_subnet.kubernetes_cluster.id
  associate_public_ip_address = true

  user_data_base64 = base64gzip(file("../scripts/master.sh"))

  root_block_device {
    volume_size           = 25      # Size in GiB
    volume_type           = "gp3"   # gp3, gp2, io1, io2, etc.
    # iops        = 3000
    # throughput  = 125  # For gp3 (e.g. 125, 250, 500)
    # encrypted             = true
    delete_on_termination = true
  }

  tags = {
    Name                               = "k8s-control-plane"
    "kubernetes.io/cluster/kubernetes" = "owned"
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required" # Require IMDSv2
    http_put_response_hop_limit = 4
  }

  private_dns_name_options {
    hostname_type                     = "ip-name" # Tells AWS to strictly use the ip-xxx format layout
    enable_resource_name_dns_a_record = true
  }
}

# worker node IAM Role
resource "aws_iam_role" "worker_role" {
  name = "worker-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

# Worker node IAM Policy
resource "aws_iam_policy" "worker_policy" {
  name = "worker-policy"

  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Action" : [
          "ec2:DescribeInstances",
          "ec2:DescribeRegions",
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:GetRepositoryPolicy",
          "ecr:DescribeRepositories",
          "ecr:ListImages",
          "ecr:BatchGetImage",
          ## Route53
          "route53:ChangeResourceRecordSets",
          "route53:ListHostedZones",
          "route53:ListHostedZonesByName",
          "route53:ListResourceRecordSets",
          "route53:GetHostedZone",
          "route53:GetChange",
          ## velero
          "ec2:DescribeVolumes",
          "ec2:DescribeSnapshots",
          "ec2:CreateTags",
          "ec2:CreateVolume",
          "ec2:CreateSnapshot",
          "ec2:DeleteSnapshot",
          "s3:GetObject",
          "s3:DeleteObject",
          "s3:PutObject",
          "s3:PutObjectTagging",
          "s3:AbortMultipartUpload",
          "s3:ListMultipartUploadParts",
          "s3:ListBucket",
        ],
        "Resource" : "*"
      }
    ]
  })
}

# Attach worker node IAM policy with worker node role
resource "aws_iam_role_policy_attachment" "worker_node_attach" {
  role       = aws_iam_role.worker_role.name
  policy_arn = aws_iam_policy.worker_policy.arn
}

# # Create an Instance profile for the worker node
# resource "aws_iam_instance_profile" "worker_node_profile" {
#   name = "worker-node-profile"
#   role = aws_iam_role.worker_role.name
# }

# Control Plane IAM Role
resource "aws_iam_role" "control_plane_role" {
  name = "control-plane-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

# Control Plane IAM Policy
resource "aws_iam_policy" "control_plane_policy" {
  name = "control-plane-policy"

  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Action" : [
          "autoscaling:DescribeAutoScalingGroups",
          "autoscaling:DescribeLaunchConfigurations",
          "autoscaling:DescribeTags",
          "ec2:DescribeInstances",
          "ec2:DescribeRegions",
          "ec2:DescribeRouteTables",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeSubnets",
          "ec2:DescribeVolumes",
          "ec2:DescribeAvailabilityZones",
          "ec2:DescribeInstanceTopology",
          "ec2:CreateSecurityGroup",
          "ec2:CreateTags",
          "ec2:CreateVolume",
          "ec2:ModifyInstanceAttribute",
          "ec2:ModifyVolume",
          "ec2:AttachVolume",
          "ec2:AuthorizeSecurityGroupIngress",
          "ec2:CreateRoute",
          "ec2:DeleteRoute",
          "ec2:DeleteSecurityGroup",
          "ec2:DeleteVolume",
          "ec2:DetachVolume",
          "ec2:RevokeSecurityGroupIngress",
          "ec2:DescribeVpcs",
          "elasticloadbalancing:AddTags",
          "elasticloadbalancing:AttachLoadBalancerToSubnets",
          "elasticloadbalancing:ApplySecurityGroupsToLoadBalancer",
          "elasticloadbalancing:CreateLoadBalancer",
          "elasticloadbalancing:CreateLoadBalancerPolicy",
          "elasticloadbalancing:CreateLoadBalancerListeners",
          "elasticloadbalancing:ConfigureHealthCheck",
          "elasticloadbalancing:DeleteLoadBalancer",
          "elasticloadbalancing:DeleteLoadBalancerListeners",
          "elasticloadbalancing:DescribeLoadBalancers",
          "elasticloadbalancing:DescribeLoadBalancerAttributes",
          "elasticloadbalancing:DetachLoadBalancerFromSubnets",
          "elasticloadbalancing:DeregisterInstancesFromLoadBalancer",
          "elasticloadbalancing:ModifyLoadBalancerAttributes",
          "elasticloadbalancing:RegisterInstancesWithLoadBalancer",
          "elasticloadbalancing:SetLoadBalancerPoliciesForBackendServer",
          "elasticloadbalancing:AddTags",
          "elasticloadbalancing:CreateListener",
          "elasticloadbalancing:CreateTargetGroup",
          "elasticloadbalancing:DeleteListener",
          "elasticloadbalancing:DeleteTargetGroup",
          "elasticloadbalancing:DescribeListeners",
          "elasticloadbalancing:DescribeLoadBalancerPolicies",
          "elasticloadbalancing:DescribeTargetGroups",
          "elasticloadbalancing:DescribeTargetHealth",
          "elasticloadbalancing:ModifyListener",
          "elasticloadbalancing:ModifyTargetGroup",
          "elasticloadbalancing:RegisterTargets",
          "elasticloadbalancing:DeregisterTargets",
          "elasticloadbalancing:SetLoadBalancerPoliciesOfListener",
          "iam:CreateServiceLinkedRole",
          "kms:DescribeKey",
          ## Route53
          "route53:ChangeResourceRecordSets",
          "route53:ListHostedZones",
          "route53:ListHostedZonesByName",
          "route53:ListResourceRecordSets",
          "route53:GetHostedZone",
          "route53:GetChange",
          ## karpenter
          "ec2:CreateFleet",
          "ec2:CreateLaunchTemplate",
          "ec2:CreateTags",
          "iam:CreateInstanceProfile",
          "iam:AddRoleToInstanceProfile",
          "iam:RemoveRoleFromInstanceProfile",
          "iam:DeleteInstanceProfile",
          "iam:GetInstanceProfile",
          "ec2:DeleteLaunchTemplate",
          "ec2:RunInstances",
          "ec2:TerminateInstances",
          "ec2:DescribeAvailabilityZones",
          "ec2:DescribeImages",
          "ec2:DescribeInstances",
          "ec2:DescribeInstanceTypeOfferings",
          "ec2:DescribeInstanceTypes",
          "ec2:DescribeLaunchTemplates",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeSubnets",
          "ec2:DescribeInstanceStatus",
          "iam:ListInstanceProfiles",
          "ec2:DescribeSpotPriceHistory",
          "ssm:GetParameter",
          "pricing:GetProducts",
          "iam:PassRole",
          "iam:GetInstanceProfile",
          "iam:CreateInstanceProfile",
          "iam:DeleteInstanceProfile",
          "iam:AddRoleToInstanceProfile",
          "iam:RemoveRoleFromInstanceProfile",
          "iam:TagInstanceProfile",
          "iam:GetRole",
          ## velero
          "ec2:DescribeVolumes",
          "ec2:DescribeSnapshots",
          "ec2:CreateTags",
          "ec2:CreateVolume",
          "ec2:CreateSnapshot",
          "ec2:DeleteSnapshot",
          "s3:GetObject",
          "s3:DeleteObject",
          "s3:PutObject",
          "s3:PutObjectTagging",
          "s3:AbortMultipartUpload",
          "s3:ListMultipartUploadParts",
          "s3:ListBucket",
        ],
        "Resource" : [
          "*"
        ]
      }
    ]
  })
}

# Attach the Control Plane policy to the Control Plane role
resource "aws_iam_role_policy_attachment" "control_plane_attach" {
  role       = aws_iam_role.control_plane_role.name
  policy_arn = aws_iam_policy.control_plane_policy.arn
}

# Create an Instance Profile for the Control Plane role
resource "aws_iam_instance_profile" "control_plane_profile" {
  name = "control-plane-profile"
  role = aws_iam_role.control_plane_role.name
}

# ebs volume policies
resource "aws_iam_role_policy_attachment" "control_plane_ebs_csi" {
  role       = aws_iam_role.control_plane_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEBSCSIDriverPolicyV2"
}
resource "aws_iam_role_policy_attachment" "worker_ebs_csi" {
  role       = aws_iam_role.worker_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEBSCSIDriverPolicyV2"
}

resource "aws_s3_bucket" "velero" {
  bucket = "velero-kubernetes-cluster-backups"
  force_destroy = true
}

resource "aws_s3_bucket_versioning" "velero" {
  bucket = aws_s3_bucket.velero.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "velero" {
  bucket = aws_s3_bucket.velero.id

  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "velero" {
  bucket = aws_s3_bucket.velero.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

output "bucket_name" {
  value = aws_s3_bucket.velero.bucket
}

# data "tls_certificate" "kubernetes" {
#   url = "https://oidc.shadoshops.com"
# }

# resource "aws_iam_openid_connect_provider" "kubernetes" {
#   url = "https://oidc.shadoshops.com"

#   client_id_list = [
#     "sts.amazonaws.com"
#   ]

#   thumbprint_list = []
#   # thumbprint_list = [data.tls_certificate.kubernetes.certificates[0].sha1_fingerprint]
# }


resource "aws_iam_policy" "s3_readonly" {
  name = "irsa-s3-readonly"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:ListAllMyBuckets"
        ]
        Resource = "*"
      }
    ]
  })
}

# resource "aws_iam_role" "irsa_demo" {
#   name = "irsa-demo-role"

#   assume_role_policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [
#       {
#         Effect = "Allow"

#         Principal = {
#           # Federated = aws_iam_openid_connect_provider.kubernetes.arn
#         }

#         Action = "sts:AssumeRoleWithWebIdentity"

#         Condition = {
#           StringEquals = {
#             "oidc.shadoshops.com:aud" = "sts.amazonaws.com"
#             "oidc.shadoshops.com:sub" = "system:serviceaccount:irsa-demo:s3-reader"
#           }
#         }
#       }
#     ]
#   })
# }

# resource "aws_iam_role_policy_attachment" "irsa_demo" {
#   role       = aws_iam_role.irsa_demo.name
#   policy_arn = aws_iam_policy.s3_readonly.arn
# }
