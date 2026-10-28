# Copy to terraform.auto.tfvars (git-ignored) and fill in. In CI these come from
# GitHub Environment variables.
api_allowed_cidrs = ["203.0.113.10/32"]
admin_role_arns = {
  sso-admin = "arn:aws:iam::123456789012:role/AWSReservedSSO_AdministratorAccess_xxxx"
}
viewer_role_arns = {
  gha-plan = "arn:aws:iam::123456789012:role/gha-weather-plan"
}
