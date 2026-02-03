output "vpc_id" {
  value = aws_vpc.eks_vpc.id
}

output "priv_subnet2a_id" {
  value = aws_subnet.private-subnet-2a.id
}

output "priv_subnet2b_id" {
  value = aws_subnet.private-subnet-2b.id
}

output "nat_gateway_id" {

  value = aws_nat_gateway.ngw.id

}

output "kms_key_id" {
  value = aws_kms_key.kms_key.id

}

output "kms_key_arn" {
  value = aws_kms_key.kms_key.arn
}



