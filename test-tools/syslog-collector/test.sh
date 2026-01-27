#!/bin/bash
# Test script for syslog collector

set -e

# Get the public IP from terraform output
PUBLIC_IP=$(terraform output -raw public_ip 2>/dev/null)

if [ -z "$PUBLIC_IP" ]; then
    echo "❌ Could not get public IP from terraform output."
    echo "   Make sure the infrastructure is deployed first."
    exit 1
fi

echo "🧪 Testing Syslog Collector"
echo "==========================="
echo "Target: $PUBLIC_IP"
echo ""

# Test 1: Check if web UI is accessible
echo "🌐 Testing web UI accessibility..."
if curl -s --connect-timeout 10 -u admin:changeme123! "http://$PUBLIC_IP" > /dev/null; then
    echo "✅ Web UI is accessible"
else
    echo "❌ Web UI is not accessible (may still be initializing)"
fi

# Test 2: Send UDP syslog message
echo ""
echo "📡 Sending UDP syslog test message..."
if command -v nc &> /dev/null; then
    echo "Test UDP message from $(hostname) at $(date)" | nc -u -w1 "$PUBLIC_IP" 514
    echo "✅ UDP message sent"
else
    echo "⚠️  netcat (nc) not available, skipping UDP test"
fi

# Test 3: Send TCP syslog message
echo ""
echo "📡 Sending TCP syslog test message..."
if command -v nc &> /dev/null; then
    echo "Test TCP message from $(hostname) at $(date)" | nc -w1 "$PUBLIC_IP" 514
    echo "✅ TCP message sent"
else
    echo "⚠️  netcat (nc) not available, skipping TCP test"
fi

# Test 4: Try logger command if available
echo ""
echo "📝 Testing with logger command..."
if command -v logger &> /dev/null; then
    logger -n "$PUBLIC_IP" -P 514 "Test message from logger command on $(hostname)"
    echo "✅ Logger command executed"
else
    echo "⚠️  logger command not available, skipping test"
fi

# Test 5: Python syslog test
echo ""
echo "🐍 Testing with Python syslog..."
python3 << EOF
import logging.handlers
import sys
try:
    handler = logging.handlers.SysLogHandler(address=('$PUBLIC_IP', 514))
    logger = logging.getLogger('test')
    logger.addHandler(handler)
    logger.info('Test log message from Python script')
    print("✅ Python syslog message sent")
except Exception as e:
    print(f"❌ Python syslog test failed: {e}")
EOF

echo ""
echo "🎯 Test Summary"
echo "==============="
echo "Syslog Endpoint: $PUBLIC_IP:514"
echo "Web UI: http://$PUBLIC_IP (admin / your-configured-password)"
echo ""
echo "💡 Tips:"
echo "• Wait 2-3 minutes after deployment for services to fully start"
echo "• Check the web UI to see if your test messages were received"
echo "• Use the download feature to get collected logs"
echo "• See README.md for more testing examples"

echo ""
echo "🔧 Troubleshooting commands:"
echo "terraform output                    # Show all outputs"
echo "ssh -i ~/.ssh/your-key.pem ec2-user@$PUBLIC_IP  # Connect to instance"
echo "curl -u admin:password http://$PUBLIC_IP         # Test web UI"
