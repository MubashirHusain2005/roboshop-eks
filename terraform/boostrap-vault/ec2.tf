provider "aws" {
  region = "eu-west-2"
}

resource "aws_vpc" "vault_vpc" {
  cidr_block           = "10.50.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.vault_vpc.id

  tags = {
    Name = "IGW"
  }
}

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.vault_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }


  tags = {
    Name = "example"
  }
}

resource "aws_route_table_association" "public_assoc" {
  subnet_id      = aws_subnet.vault_subnet.id
  route_table_id = aws_route_table.public_rt.id
}


resource "aws_iam_instance_profile" "vault_profile" {
  name = "vault-instance-profile"
  role = aws_iam_role.vault_ec2_role.name
}


###Running Vault on a EC2 Instance to protect Secrets

resource "aws_iam_role" "vault_ec2_role" {
  name = "vault_ec2"
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

resource "aws_iam_policy" "vault_polices" {
  name = "vault-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams",
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "vault_attach" {
  role       = aws_iam_role.vault_ec2_role.name
  policy_arn = aws_iam_policy.vault_polices.arn
}


data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

resource "aws_subnet" "vault_subnet" {
  vpc_id                  = aws_vpc.vault_vpc.id
  cidr_block              = "10.50.1.0/24"
  availability_zone       = "eu-west-2a"
  map_public_ip_on_launch = true

  tags = {
    Name = "vault-subnet"
  }
}

data "aws_key_pair" "vault_key" {
  key_name = "vault-ec2"
}

resource "aws_instance" "vault_ec2" {
  ami           = data.aws_ami.al2023.id
  instance_type = "t3.micro"

  key_name = data.aws_key_pair.vault_key.key_name

  subnet_id              = aws_subnet.vault_subnet.id
  vpc_security_group_ids = [aws_security_group.vault-sg.id]
  iam_instance_profile   = aws_iam_instance_profile.vault_profile.name
  user_data              = file("script.sh")

  root_block_device {
    volume_size = 20
  }

  tags = {
    Name = "vault-ec2"
  }
}


resource "aws_security_group" "vault-sg" {
  name   = "vault-sg"
  vpc_id = aws_vpc.vault_vpc.id

  ingress {
    from_port   = 8200
    to_port     = 8200
    description = "Vault API"
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    description = "SSH"
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
