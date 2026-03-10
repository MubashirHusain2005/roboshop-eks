output "iam_cluster_role_arn" {
  value = aws_iam_role.cluster.arn
}


output "nodegroup_role_arn" {
  value = aws_iam_role.nodes.arn
}



output "vpc_flow_logs_role" {
  value = aws_iam_role.vpc_flow_logs_role.arn
}


output "node_instance_profile" {
  value = aws_iam_instance_profile.nodes
}
