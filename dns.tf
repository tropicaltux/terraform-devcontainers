# Find the parent hosted zone
data "aws_route53_zone" "parent" {
  count = local.create_dns_records ? 1 : 0

  name         = var.dns.high_level_domain
  private_zone = false
}

# Create a separate hosted zone for the subdomain
resource "aws_route53_zone" "subdomain" {
  count = local.create_dns_records ? 1 : 0

  name = local.subdomain_fqdn

  tags = {
    Name = "${var.name}-devcontainers-subdomain"
  }
}

# Delegate the subdomain by creating NS records in the parent zone
resource "aws_route53_record" "subdomain_delegation" {
  count = local.create_dns_records ? 1 : 0

  zone_id = data.aws_route53_zone.parent[0].zone_id
  name    = var.name
  type    = "NS"
  ttl     = 300
  records = aws_route53_zone.subdomain[0].name_servers
}

# Create an A record in the subdomain zone pointing to the EC2 instance
resource "aws_route53_record" "subdomain_a" {
  count = local.create_dns_records ? 1 : 0

  zone_id = aws_route53_zone.subdomain[0].zone_id
  name    = "" # apex/root of the subdomain zone
  type    = "A"
  ttl     = 300
  records = [aws_instance.this.public_ip]
}

# Create a wildcard record in the subdomain zone
resource "aws_route53_record" "wildcard" {
  count = local.create_dns_records ? 1 : 0

  zone_id = aws_route53_zone.subdomain[0].zone_id
  name    = "*" # wildcard for the subdomain zone
  type    = "A"
  ttl     = 300
  records = [aws_instance.this.public_ip]
}
