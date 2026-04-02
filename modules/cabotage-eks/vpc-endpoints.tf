# --- VPC Gateway Endpoints ---

resource "aws_vpc_endpoint" "s3" {
  vpc_id       = module.vpc.vpc_id
  service_name = "com.amazonaws.${data.aws_region.current.id}.s3"

  vpc_endpoint_type = "Gateway"
  route_table_ids   = module.vpc.private_route_table_ids

  tags = merge(local.tags, {
    Name = "${var.cluster_name}-s3"
  })
}
