output "ecr_repository_url" {
  description = "The repo URL for backend ECR"
  value = module.ecr_backend.ecr_repository_url
}
