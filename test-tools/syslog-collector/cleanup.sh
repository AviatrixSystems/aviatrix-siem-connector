#!/bin/bash
# Cleanup script for syslog collector

set -e

echo "🗑️  Syslog Collector Cleanup Script"
echo "==================================="

# Check if terraform is installed
if ! command -v terraform &> /dev/null; then
    echo "❌ Terraform is not installed."
    exit 1
fi

# Check if we're in the right directory
if [ ! -f "main.tf" ]; then
    echo "❌ This doesn't appear to be the syslog-collector directory."
    echo "   Please run this script from the test-tools/syslog-collector directory."
    exit 1
fi

# Show what will be destroyed
echo "🔍 Checking what will be destroyed..."
terraform plan -destroy

echo ""
echo "⚠️  This will permanently delete:"
echo "   - EC2 instance and all collected logs"
echo "   - VPC and networking components"
echo "   - Security groups and elastic IP"
echo "   - All AWS resources created by this Terraform configuration"
echo ""

read -p "Are you sure you want to destroy all resources? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "❌ Cleanup cancelled."
    exit 0
fi

echo "💥 Destroying infrastructure..."
terraform destroy -auto-approve

echo ""
echo "✅ Cleanup complete!"
echo "All AWS resources have been destroyed."

# Optionally clean up local files
echo ""
read -p "Also remove local Terraform state files? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    rm -f terraform.tfstate*
    rm -f tfplan
    rm -rf .terraform/
    echo "🗑️  Local state files removed."
fi

echo "🎉 All done!"
