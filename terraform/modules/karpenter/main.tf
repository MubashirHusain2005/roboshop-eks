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
###Policy needs fixing 
resource "aws_iam_policy" "iam_karpenter_policy" {
  name = "iampolicy-karpenter"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "iam:PassRole",
          "ec2:DescribeImages",
          "ec2:RunInstances",
          "ec2:DescribeSubnets",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeLaunchTemplates",
          "ec2:DescribeInstances",
          "ec2:DescribeInstanceTypes",
          "ec2:DescribeInstanceTypeOfferings",
          "ec2:DeleteLaunchTemplate",
          "ec2:CreateTags",
          "ec2:CreateLaunchTemplate",
          "ec2:CreateFleet",
          "ec2:DescribeSpotPriceHistory",
          "pricing:GetProducts",
          "sqs:SendMessage",
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes",
          "sqs:GetQueueUrl",
          "eks:DescribeCluster"
        ],
        Resource = "*"
      },
    ]
  })
}


resource "aws_iam_role_policy_attachment" "iampolicyattach_karpenter" {
  role       = aws_iam_role.karpenter_controller_role.arn
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
    aws_iam_role.karpenter_controller_role
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

#Karpenter Helm Chart- temporary

#resource "helm_release" "karpenter" {
#name       = "karpenter"
#repository = "https://charts.karpenter.sh"
#chart      = "karpenter"
#namespace  = "karpenter"
#version    = "v0.13.1"

#create_namespace = false

# set = [
# {
#   name  = "settings.clusterEndpoint"
#  value = var.cluster_endpoint
#}
# ]

# values = [
# templatefile("${path.root}/${var.karpenter_values_file}", {})
#]

# depends_on = [var.cluster_id, var.private_node_1_name, var.private_node_2_name, kubectl_manifest.karpenter_namespace]
#}



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