output "cluster_endpoint" {
  value = aws_eks_cluster.eks_cluster.endpoint
}

output "oidc_issuer_url" {
  value = aws_eks_cluster.eks_cluster.identity[0].oidc[0].issuer
}

output "oidc_provider_arn" {
  value = aws_iam_openid_connect_provider.eks.arn
}

output "cluster_name" {
  value       = aws_eks_cluster.eks_cluster.name
  description = "EKS Cluster name"
}

output "cluster_ca" {
  description = "Base64 encoded CA certificate for the EKS cluster"
  value       = aws_eks_cluster.eks_cluster.certificate_authority[0].data
}


output "private_node_1_name" {
  value = aws_eks_node_group.private_node_1.node_group_name
}

output "private_node_2_name" {
  value = aws_eks_node_group.private_node_2.node_group_name
}

