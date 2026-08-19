# ---------------------------------------------------------------------------
# Network
#
# Deliberately public-subnets-only. No NAT gateway means:
#   - ~4 minutes faster to create and destroy
#   - ~$0.045/hr cheaper per student
#   - one less thing to break during a 2-hour class
# This is a LAB topology. Production puts nodes in private subnets behind NAT
# (or VPC endpoints) and keeps only the load balancers public.
# ---------------------------------------------------------------------------

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  name = "${var.student_handle}-gitops"
  azs  = slice(data.aws_availability_zones.available.names, 0, 2)
}

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${local.name}-vpc"
  }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${local.name}-igw"
  }
}

resource "aws_subnet" "public" {
  count = 2

  vpc_id                  = aws_vpc.this.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, count.index)
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "${local.name}-public-${local.azs[count.index]}"

    # The AWS cloud controller inside EKS discovers subnets for
    # `Service type=LoadBalancer` using these two tags. Without them your
    # ArgoCD and NGINX services sit in <pending> forever.
    "kubernetes.io/role/elb"                = "1"
    "kubernetes.io/cluster/${local.name}"   = "shared"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = {
    Name = "${local.name}-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  count = length(aws_subnet.public)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}
