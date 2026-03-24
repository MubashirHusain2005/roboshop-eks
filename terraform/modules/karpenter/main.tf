terraform {
  required_providers {

    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.2.0"
    }

    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.23.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.12.0"
    }


    kubectl = {
      source  = "gavinbunney/kubectl"
      version = ">= 1.7.0"
    }

    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}

data "aws_caller_identity" "current" {}


#Acts as the dead letter queue, so if the message fails to send after 5 attempts it goes here for debugging
resource "aws_sqs_queue" "karpenter_interruption_dlq" {
  name = "karpenter-spot-events-dlq"

  message_retention_seconds = 1209600
  sqs_managed_sse_enabled   = true

  tags = {
    "karpenter.sh/discovery" = var.cluster_id
  }

  depends_on = [var.cluster_id]

}

##Acts as the main queue, karpenter picks a message from the main queue and deletes it when done, if message failed to send goes to dead letter queue
resource "aws_sqs_queue" "karpenter_interruption" {
  name                       = "karpenter-spot-events"
  message_retention_seconds  = 1209600
  visibility_timeout_seconds = 300
  delay_seconds              = 0
  sqs_managed_sse_enabled    = true

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.karpenter_interruption_dlq.arn
    maxReceiveCount     = 5
  })

  tags = {
    "karpenter.sh/discovery" = var.cluster_id
  }

  depends_on = [var.cluster_id]
}

##This policy ensres that only EventBridge is allowed to send messages,without this spot interruption events cant reach the SQS queue
resource "aws_sqs_queue_policy" "karpenter_interruption_policy" {
  queue_url = aws_sqs_queue.karpenter_interruption.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
        Action   = "sqs:SendMessage"
        Resource = aws_sqs_queue.karpenter_interruption.arn
        Condition = {
          ArnEquals = {
            "aws:SourceArn" = [
              aws_cloudwatch_event_rule.spot_interruption_rule.arn,
              aws_cloudwatch_event_rule.rebalance_recommendation_rule.arn
            ]
          }
        }
      }
    ]
  })
  depends_on = [
    aws_cloudwatch_event_rule.spot_interruption_rule,
    aws_cloudwatch_event_rule.rebalance_recommendation_rule,
    var.cluster_id
  ]
}

##Watches for specific events happening in AWS and watches for the EC2 Spot interruption warning
resource "aws_cloudwatch_event_rule" "spot_interruption_rule" {
  name          = "karpenter-spot-interruption"
  description   = "Capture EC2 spot interruption warnings"
  event_pattern = <<PATTERN
{
  "source": ["aws.ec2"],
  "detail-type": ["EC2 Spot Instance Interruption Warning"]
}
PATTERN
}

resource "aws_cloudwatch_event_rule" "rebalance_recommendation_rule" {
  name        = "karpenter-rebalance-recommendation"
  description = "Capture EC2 Instance Rebalance Recommendations"

  event_pattern = <<PATTERN
{
  "source": ["aws.ec2"],
  "detail-type": ["EC2 Instance Rebalance Recommendation"]
}
PATTERN
}



##This acts as a target, so that the events can go to SQS
resource "aws_cloudwatch_event_target" "rebalance_to_sqs" {
  rule      = aws_cloudwatch_event_rule.rebalance_recommendation_rule.name
  target_id = "KarpenterRebalance"
  arn       = aws_sqs_queue.karpenter_interruption.arn
}


resource "aws_cloudwatch_event_target" "spot_to_sqs" {
  rule      = aws_cloudwatch_event_rule.spot_interruption_rule.name
  target_id = "KarpenterSpotInterruption"
  arn       = aws_sqs_queue.karpenter_interruption.arn
}


##IAM Instance Profile

resource "aws_iam_instance_profile" "karpenter" {
  name = "karpenter-controller"
  role = aws_iam_role.karpenter_profile_instance_role.name
}

resource "aws_iam_policy" "instance_profile_policy" {
  name        = "instance_profile-karpenter-policy"
  description = "instance profile for karpenter policy"

  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Action" : [
          "ec2:DescribeInstances",
          "ec2:DescribeInstanceTypes",
          "ec2:DescribeRouteTables",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeSubnets",
          "ec2:DescribeVolumes",
          "ec2:DescribeVolumesModifications",
          "ec2:DescribeVpcs",
          "eks:DescribeCluster"
        ],
        "Resource" : "*"
      },
      {
        "Effect" : "Allow",
        "Action" : [
          "ec2:AssignPrivateIpAddresses",
          "ec2:AttachNetworkInterface",
          "ec2:CreateNetworkInterface",
          "ec2:DeleteNetworkInterface",
          "ec2:DescribeInstances",
          "ec2:DescribeTags",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DescribeInstanceTypes",
          "ec2:DetachNetworkInterface",
          "ec2:ModifyNetworkInterfaceAttribute",
          "ec2:UnassignPrivateIpAddresses"
        ],
        "Resource" : "*"
      },
      {
        "Effect" : "Allow",
        "Action" : [
          "ec2:CreateTags"
        ],
        "Resource" : [
          "arn:aws:ec2:*:*:network-interface/*"
        ]
      },
      {
        "Effect" : "Allow",
        "Action" : [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:GetRepositoryPolicy",
          "ecr:DescribeRepositories",
          "ecr:ListImages",
          "ecr:DescribeImages",
          "ecr:BatchGetImage",
          "ecr:GetLifecyclePolicy",
          "ecr:GetLifecyclePolicyPreview",
          "ecr:ListTagsForResource",
          "ecr:DescribeImageScanFindings"
        ],
        "Resource" : "*"
      },
      {
        "Effect" : "Allow",
        "Action" : [
          "ssm:DescribeAssociation",
          "ssm:GetDeployablePatchSnapshotForInstance",
          "ssm:GetDocument",
          "ssm:DescribeDocument",
          "ssm:GetManifest",
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:ListAssociations",
          "ssm:ListInstanceAssociations",
          "ssm:PutInventory",
          "ssm:PutComplianceItems",
          "ssm:PutConfigurePackageResult",
          "ssm:UpdateAssociationStatus",
          "ssm:UpdateInstanceAssociationStatus",
          "ssm:UpdateInstanceInformation"
        ],
        "Resource" : "*"
      },
      {
        "Effect" : "Allow",
        "Action" : [
          "ssmmessages:CreateControlChannel",
          "ssmmessages:CreateDataChannel",
          "ssmmessages:OpenControlChannel",
          "ssmmessages:OpenDataChannel"
        ],
        "Resource" : "*"
      },
      {
        "Effect" : "Allow",
        "Action" : [
          "ec2messages:AcknowledgeMessage",
          "ec2messages:DeleteMessage",
          "ec2messages:FailMessage",
          "ec2messages:GetEndpoint",
          "ec2messages:GetMessages",
          "ec2messages:SendReply"
        ],
        "Resource" : "*"
      }
    ]
  })
}

##IAM Instance Profile Role

resource "aws_iam_role" "karpenter_profile_instance_role" {
  name = "karpenter-profile-instance"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          "Service" : "ec2.amazonaws.com"
        },
      }
    ]
  })
}

##IAM Policy attachment

resource "aws_iam_role_policy_attachment" "instance-profile-attach" {
  role       = aws_iam_role.karpenter_profile_instance_role.name
  policy_arn = aws_iam_policy.instance_profile_policy.arn
}


#Iam Role for Karpenter Controller

resource "aws_iam_role" "karpenter_controller_role" {
  name = "karpenter-controller-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = "${var.oidc_provider_arn}"
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${replace(var.oidc_issuer_url, "https://", "")}:sub" = "system:serviceaccount:karpenter:karpenter",
            "${replace(var.oidc_issuer_url, "https://", "")}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]

  })
}

resource "aws_iam_policy" "iam_karpenter_policy" {
  name = "iampolicy-karpenter"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # Read-only EC2 describe actions (safe to keep broad)
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeImages",
          "ec2:DescribeSubnets",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeLaunchTemplates",
          "ec2:DescribeInstances",
          "ec2:DescribeInstanceTypes",
          "ec2:DescribeInstanceTypeOfferings",
          "ec2:DescribeAvailabilityZones",
          "ec2:DescribeSpotPriceHistory",
          "pricing:GetProducts",
          "eks:DescribeCluster"
        ]
        Resource = "*"  
      },
      # IAM PassRole - only for specific Karpenter role
      {
        Effect = "Allow"
        Action = [
          "iam:PassRole"
        ]
        Resource = aws_iam_role.karpenter_profile_instance_role.arn
       
      },
      # IAM Instance Profile management - scoped to Karpenter resources
      {
        Effect = "Allow"
        Action = [
          "iam:CreateInstanceProfile",
          "iam:DeleteInstanceProfile",
          "iam:GetInstanceProfile",
          "iam:AddRoleToInstanceProfile",
          "iam:RemoveRoleFromInstanceProfile",
          "iam:TagInstanceProfile"
        ]
        Resource = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:instance-profile/karpenter-*"
      },
  
      {
        Effect = "Allow"
        Action = [
          "ec2:RunInstances"
        ]
        Resource = [
          "arn:aws:ec2:*:${data.aws_caller_identity.current.account_id}:instance/*",
          "arn:aws:ec2:*:${data.aws_caller_identity.current.account_id}:volume/*",
          "arn:aws:ec2:*:${data.aws_caller_identity.current.account_id}:network-interface/*",
          "arn:aws:ec2:*:${data.aws_caller_identity.current.account_id}:security-group/*",
          "arn:aws:ec2:*:${data.aws_caller_identity.current.account_id}:subnet/*",
          "arn:aws:ec2:*:${data.aws_caller_identity.current.account_id}:launch-template/*"
        ]
        Condition = {
          StringLike = {
            "ec2:InstanceProfile" = aws_iam_role.karpenter_profile_instance_role.arn
            
          }
        }
      },
      # EC2 CreateTags - only on Karpenter-tagged resources
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateTags"
        ]
        Resource = [
          "arn:aws:ec2:*:${data.aws_caller_identity.current.account_id}:instance/*",
          "arn:aws:ec2:*:${data.aws_caller_identity.current.account_id}:volume/*",
          "arn:aws:ec2:*:${data.aws_caller_identity.current.account_id}:network-interface/*"
        ]
        Condition = {
          StringEquals = {
            "aws:RequestedRegion" = var.aws_region
            # ✅ Only in this region
          }
        }
      },
      # EC2 TerminateInstances - only tagged instances
      {
        Effect = "Allow"
        Action = [
          "ec2:TerminateInstances"
        ]
        Resource = "arn:aws:ec2:*:${data.aws_caller_identity.current.account_id}:instance/*"
        Condition = {
          StringLike = {
            "ec2:ResourceTag/karpenter.sh/discovery" = var.cluster_id
            # ✅ Only instances tagged with cluster ID
          }
        }
      },
      # EC2 DeleteLaunchTemplate
      {
        Effect = "Allow"
        Action = [
          "ec2:DeleteLaunchTemplate"
        ]
        Resource = "arn:aws:ec2:*:${data.aws_caller_identity.current.account_id}:launch-template/*"
        Condition = {
          StringLike = {
            "ec2:ResourceTag/karpenter.sh/discovery" = var.cluster_id
            
          }
        }
      },
      # EC2 CreateLaunchTemplate
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateLaunchTemplate"
        ]
        Resource = "arn:aws:ec2:*:${data.aws_caller_identity.current.account_id}:launch-template/*"
      },
      # EC2 CreateFleet
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateFleet"
        ]
        Resource = "arn:aws:ec2:*:${data.aws_caller_identity.current.account_id}:fleet/*"
      },
      # SQS - only specific queue
      {
        Effect = "Allow"
        Action = [
          "sqs:SendMessage",
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes",
          "sqs:GetQueueUrl"
        ]
        Resource = aws_sqs_queue.karpenter_interruption.arn
       
      },
     
      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameter"
        ]
        Resource = "arn:aws:ssm:*:${data.aws_caller_identity.current.account_id}:parameter/karpenter/*"
      }
    ]
  })
}

###Policy needs fixing 
#resource "aws_iam_policy" "iam_karpenter_policy" {
 # name = "iampolicy-karpenter"

 # policy = jsonencode({
  #  Version = "2012-10-17"
    #Statement = [
    #  {
     #   Effect = "Allow"
      #  Action = [
     #     "ssm:GetParameter",
      #    "iam:PassRole",
      #    "iam:CreateInstanceProfile",
      #    "iam:DeleteInstanceProfile",
       #   "iam:GetInstanceProfile",
       #   "iam:AddRoleToInstanceProfile",
       #   "iam:RemoveRoleFromInstanceProfile",
        #  "iam:TagInstanceProfile",
        #  "ec2:DescribeImages",
        #  "ec2:RunInstances",
       #   "ec2:DescribeSubnets",
        #  "ec2:DescribeSecurityGroups",
        #  "ec2:DescribeLaunchTemplates",
        #  "ec2:DescribeInstances",
       #   "ec2:DescribeInstanceTypes",
       #   "ec2:DescribeInstanceTypeOfferings",
        #  "ec2:DeleteLaunchTemplate",
        #  "ec2:CreateTags",
      #    "ec2:DescribeAvailabilityZones",
       #   "ec2:TerminateInstances",
       #   "ec2:CreateLaunchTemplate",
        #  "ec2:CreateFleet",
        #  "ec2:DescribeSpotPriceHistory",
       #   "pricing:GetProducts",
        #  "sqs:SendMessage",
        #  "sqs:ReceiveMessage",
        #  "sqs:DeleteMessage",
        #  "sqs:GetQueueAttributes",
        #  "sqs:GetQueueUrl",
         # "eks:DescribeCluster"
      #  ],
      #  Resource = "*"
      #},
   # ]
  #})
#}


resource "aws_iam_role_policy_attachment" "iampolicyattach_karpenter" {
  role       = aws_iam_role.karpenter_controller_role.name
  policy_arn = aws_iam_policy.iam_karpenter_policy.arn
}


##Service Account for the karpenter pod 

resource "kubernetes_service_account_v1" "karpenter_serviceaact" {
  metadata {
    name      = "karpenter"
    namespace = "karpenter"
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.karpenter_controller_role.arn
    }
  }
  depends_on = [
    aws_iam_role_policy_attachment.iampolicyattach_karpenter,
    aws_iam_role.karpenter_controller_role,
    kubectl_manifest.karpenter_namespace
  ]
}

resource "kubectl_manifest" "karpenter_namespace" {
  yaml_body  = <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: karpenter
EOF
  depends_on = [var.cluster_id]
}

#Karpenter Helm Chart

resource "helm_release" "karpenter" {
  name       = "karpenter"
  repository = "oci://public.ecr.aws/karpenter"
  chart      = "karpenter"
  namespace  = "karpenter"
  version    = "1.1.1"

  create_namespace = false

  set = [
    {
      name  = "settings.clusterName"
      value = var.cluster_name
    },

    {
      name  = "settings.clusterEndpoint"
      value = var.cluster_endpoint
    },

    {
      name  = "settings.interruptionQueue"
      value = aws_sqs_queue.karpenter_interruption.name 
    },

    {
      name  = "serviceAccount.create"
      value = "false" 
    },

    {
      name  = "serviceAccount.name"
      value = "karpenter" 
    },

    {
      name  = "controller.resources.requests.cpu"
      value = "250m"
    },

    {
      name  = "controller.resources.requests.memory"
      value = "256Mi"
    },

    {
      name  = "controller.resources.limits.cpu"
      value = "1"
    },

    {
      name  = "controller.resources.limits.memory"
      value = "1Gi"
    },
  ]
  depends_on = [
    var.cluster_id,
    kubectl_manifest.karpenter_namespace,
    kubernetes_service_account_v1.karpenter_serviceaact,
    aws_sqs_queue.karpenter_interruption,
    aws_iam_role_policy_attachment.iampolicyattach_karpenter
  ]
}

resource "kubectl_manifest" "karpenter_node_class" {
  yaml_body = <<EOF

apiVersion: karpenter.k8s.aws/v1
kind: EC2NodeClass
metadata:
  name: default
spec:
  amiSelectorTerms:
    - alias: al2023@latest
  role: "${aws_iam_role.karpenter_profile_instance_role.name}"
  subnetSelectorTerms:
    - tags:
        karpenter.sh/discovery: "${var.cluster_id}"
  securityGroupSelectorTerms:
    - tags:
        karpenter.sh/discovery: "${var.cluster_id}"
  tags:
    karpenter.sh/discovery: "${var.cluster_id}"
EOF

  depends_on = [helm_release.karpenter]
}

resource "kubectl_manifest" "karpenter_nodepool" {
  yaml_body = <<EOF
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: default
spec:
  template:
    spec:
      nodeClassRef:
        group: karpenter.k8s.aws
        kind: EC2NodeClass
        name: default
      requirements:
        - key: karpenter.sh/capacity-type
          operator: In
          values: ["spot", "on-demand"]
        - key: kubernetes.io/arch
          operator: In
          values: ["amd64"]
        - key: karpenter.k8s.aws/instance-category
          operator: In
          values: ["c", "m", "r"]
        - key: karpenter.k8s.aws/instance-generation
          operator: Gt
          values: ["2"]
  limits:
    cpu: 1000
    memory: 1000Gi
  disruption:
    consolidationPolicy: WhenEmptyOrUnderutilized
    consolidateAfter: 2m
EOF

  depends_on = [
    helm_release.karpenter,
    kubectl_manifest.karpenter_node_class # ✅ node class must exist first
  ]
}


resource "kubernetes_config_map_v1" "aws_auth" {
  metadata {
    name      = "aws-auth"
    namespace = "kube-system"
  }

  data = {
    mapRoles = yamlencode([
      # your existing node group role
      {
        rolearn  = var.nodegroup_role_arn
        username = "system:node:{{EC2PrivateDNSName}}"
        groups   = ["system:bootstrappers", "system:nodes"]
      },
      # karpenter nodes role
      {
        rolearn  = aws_iam_role.karpenter_profile_instance_role.arn
        username = "system:node:{{EC2PrivateDNSName}}"
        groups   = ["system:bootstrappers", "system:nodes"]
      }
    ])
  }
}


resource "aws_eks_access_entry" "karpenter_node" {
  cluster_name  = var.cluster_name
  principal_arn = "arn:aws:iam::038774803581:role/karpenter-profile-instance"
  type          = "EC2_LINUX"
}


##Karpenter Workflow

#When AWS is about to terminate a Spot instance:

#EventBridge captures it

##EventBridge pushes it into SQS

#Karpenter reads from SQS

#Karpenter:

#Cordon node

#Drain pods

#Launch replacement node

#That’s graceful Spot handling.

#1️⃣ AWS detects a Spot instance interruption → creates an EventBridge event

#2️⃣ EventBridge rule (spot_interruption_rule or rebalance_recommendation_rule) matches the event

#3️⃣ EventBridge sends the event to SQS queue (karpenter_interruption)

#4️⃣ Karpenter controller (running in EKS, with IAM role) polls the SQS queue

#5️⃣ Karpenter processes the message:
# ├─ Marks Spot node for termination
#  ├─ Launches replacement EC2 node using instance profile
#  └─ Deletes the message from the queue

#6️⃣ If a message fails 5 times, it goes to DLQ (karpenter_interruption_dlq) for debugging