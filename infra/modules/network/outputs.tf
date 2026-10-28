output "vpc_id" {
  value = module.vpc.vpc_id
}

output "vpc_cidr" {
  value = module.vpc.vpc_cidr_block
}

output "private_subnet_ids" {
  value = module.vpc.private_subnets
}

output "public_subnet_cidrs" {
  value = module.vpc.public_subnets_cidr_blocks
}

output "database_subnet_group" {
  value = module.vpc.database_subnet_group_name
}

output "database_subnet_cidrs" {
  value = module.vpc.database_subnets_cidr_blocks
}
