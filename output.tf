output "ecr_repo_uri" {
  value = aws_ecr_repository.my_site.repository_url
}
output "jenkins_password" {
  value       = random_password.jenkins.result
  description = "Admin password for Jenkins"
  sensitive   = true
}