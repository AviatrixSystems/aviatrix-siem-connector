#!/bin/bash
# Quick deployment script for syslog collector

set -e

echo "🚀 Syslog Collector Deployment Script"
echo "======================================"

# Check if terraform is installed
if ! command -v terraform &> /dev/null; then
    echo "❌ Terraform is not installed. Please install Terraform first."
    exit 1
fi

# Check if terraform.tfvars exists
if [ ! -f "terraform.tfvars" ]; then
    echo "📝 Creating terraform.tfvars from example..."
    cp terraform.tfvars.example terraform.tfvars
    echo "⚠️  Please edit terraform.tfvars with your settings before continuing."
    echo "   Key items to update:"
    echo "   - ssh_key_name: Your AWS EC2 key pair name"
    echo "   - web_ui_password: A secure password for the web UI"
    echo "   - aws_region: Your preferred AWS region"
    echo ""
    read -p "Press Enter after you've updated terraform.tfvars..."
fi

# Validate required variables
echo "🔍 Validating configuration..."

# Check if ssh_key_name is set
if grep -q "your-key-name" terraform.tfvars; then
    echo "❌ Please update ssh_key_name in terraform.tfvars"
    exit 1
fi

# Check if password is default
if grep -q "changeme123!" terraform.tfvars; then
    echo "⚠️  Warning: You're using the default password. Consider changing it for security."
    read -p "Continue anyway? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

echo "✅ Configuration looks good!"

# Initialize Terraform
echo "🔧 Initializing Terraform..."
terraform init

# Plan deployment
echo "📋 Planning deployment..."
terraform plan -out=tfplan

# Confirm deployment
echo ""
echo "🚀 Ready to deploy syslog collector!"
read -p "Deploy now? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "❌ Deployment cancelled."
    exit 0
fi

# Apply deployment
echo "⚡ Deploying infrastructure..."
terraform apply tfplan

# Show outputs
echo ""
echo "🎉 Deployment complete!"
echo "======================"
terraform output

echo ""
echo "📖 Next steps:"
echo "1. Wait 2-3 minutes for the instance to fully initialize"
echo "2. Access the web UI using the URL above (username: admin)"
echo "3. Send test logs to the syslog endpoint"
echo "4. Use the web UI to download collected logs"
echo ""
echo "💡 See README.md for usage examples and troubleshooting tips."
