#!/bin/bash
# User data script for syslog collector EC2 instance

# Update system
yum update -y

# Install Docker
yum install -y docker
systemctl start docker
systemctl enable docker

# Install Docker Compose
curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

# Create directories
mkdir -p /opt/syslog-collector/logs
mkdir -p /opt/syslog-collector/config
mkdir -p /opt/syslog-collector/web

# Create custom rsyslog configuration for raw message output
cat > /opt/syslog-collector/config/rsyslog.conf << 'EOF'
# Load modules
module(load="imudp")
module(load="imptcp")

# Listen on UDP and TCP 514
input(type="imudp" port="514")
input(type="imptcp" port="514")

# Template for raw syslog output (preserves original message format)
template(name="RawFormat" type="string" string="%rawmsg%\n")

# Write all logs to single file
*.* /logs/messages;RawFormat
EOF

# Create Docker Compose file
cat > /opt/syslog-collector/docker-compose.yml << 'EOF'
services:
  rsyslog:
    image: rsyslog/syslog_appliance_alpine:latest
    container_name: syslog-collector
    ports:
      - "514:514/udp"
      - "514:514/tcp"
    volumes:
      - ./logs:/logs
      - ./config/rsyslog.conf:/etc/rsyslog.conf:ro
    restart: unless-stopped

  web-ui:
    image: nginx:alpine
    container_name: syslog-web-ui
    ports:
      - "80:80"
    volumes:
      - ./web:/usr/share/nginx/html
      - ./logs:/var/log/syslog:ro
      - ./config/nginx.conf:/etc/nginx/nginx.conf:ro
      - ./config/.htpasswd:/etc/nginx/.htpasswd:ro
    restart: unless-stopped
    depends_on:
      - rsyslog
EOF

# Create nginx configuration with basic auth
cat > /opt/syslog-collector/config/nginx.conf << 'EOF'
events {
    worker_connections 1024;
}

http {
    include       /etc/nginx/mime.types;
    default_type  application/octet-stream;

    sendfile        on;
    keepalive_timeout  65;

    server {
        listen       80;
        server_name  localhost;

        auth_basic "Syslog Collector";
        auth_basic_user_file /etc/nginx/.htpasswd;

        location / {
            root   /usr/share/nginx/html;
            index  index.html index.htm;
        }

        location /logs/ {
            alias /var/log/syslog/;
            autoindex on;
            autoindex_exact_size off;
            autoindex_localtime on;
        }

        location /download/ {
            alias /var/log/syslog/;
            add_header Content-Disposition 'attachment';
        }

        error_page   500 502 503 504  /50x.html;
        location = /50x.html {
            root   /usr/share/nginx/html;
        }
    }
}
EOF

# Create htpasswd file with the provided password
yum install -y httpd-tools
echo "admin:$(openssl passwd -apr1 '${web_ui_password}')" > /opt/syslog-collector/config/.htpasswd

# Create web UI HTML
cat > /opt/syslog-collector/web/index.html << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Syslog Collector</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            max-width: 1200px;
            margin: 0 auto;
            padding: 20px;
            background-color: #f5f5f5;
        }
        .container {
            background-color: white;
            padding: 30px;
            border-radius: 8px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
        }
        h1 {
            color: #333;
            text-align: center;
            margin-bottom: 30px;
        }
        .info-section {
            background-color: #e7f3ff;
            padding: 20px;
            border-radius: 5px;
            margin-bottom: 30px;
            border-left: 4px solid #007cba;
        }
        .action-buttons {
            display: flex;
            gap: 15px;
            justify-content: center;
            margin: 30px 0;
        }
        .btn {
            padding: 12px 24px;
            border: none;
            border-radius: 5px;
            cursor: pointer;
            text-decoration: none;
            display: inline-block;
            font-size: 16px;
            transition: background-color 0.3s;
        }
        .btn-primary {
            background-color: #007cba;
            color: white;
        }
        .btn-primary:hover {
            background-color: #005a87;
        }
        .btn-secondary {
            background-color: #6c757d;
            color: white;
        }
        .btn-secondary:hover {
            background-color: #545b62;
        }
        .status {
            background-color: #d4edda;
            border: 1px solid #c3e6cb;
            color: #155724;
            padding: 15px;
            border-radius: 5px;
            margin: 20px 0;
        }
        .code {
            background-color: #f8f9fa;
            padding: 15px;
            border-radius: 5px;
            font-family: 'Courier New', monospace;
            border: 1px solid #dee2e6;
            margin: 10px 0;
        }
        .stats {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 20px;
            margin: 20px 0;
        }
        .stat-card {
            background-color: #f8f9fa;
            padding: 20px;
            border-radius: 5px;
            text-align: center;
            border: 1px solid #dee2e6;
        }
        .stat-number {
            font-size: 2em;
            font-weight: bold;
            color: #007cba;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>Syslog Collector Dashboard</h1>

        <div class="info-section">
            <h3>Collection Information</h3>
            <p><strong>Syslog Endpoint:</strong> <span id="server-ip">Loading...</span>:514 (UDP/TCP)</p>
            <p><strong>Status:</strong> <span class="status">Collecting logs</span></p>
            <p><strong>Storage:</strong> Logs stored in <code>/logs/messages</code></p>
        </div>

        <div class="stats">
            <div class="stat-card">
                <div class="stat-number" id="log-count">-</div>
                <div>Total Log Lines</div>
            </div>
            <div class="stat-card">
                <div class="stat-number" id="file-size">-</div>
                <div>File Size</div>
            </div>
            <div class="stat-card">
                <div class="stat-number" id="last-updated">-</div>
                <div>Last Updated</div>
            </div>
        </div>

        <div class="action-buttons">
            <a href="/logs/" class="btn btn-secondary">Browse Log Files</a>
            <a href="/download/messages" class="btn btn-primary" download>Download Logs</a>
            <button onclick="refreshStats()" class="btn btn-secondary">Refresh Stats</button>
        </div>

        <div class="info-section">
            <h3>How to Send Logs</h3>
            <p>Configure your systems to send syslog messages to this collector:</p>

            <h4>Linux rsyslog configuration:</h4>
            <div class="code">
# Add to /etc/rsyslog.conf:<br>
*.* @@<span id="server-ip-2">SERVER_IP</span>:514
            </div>

            <h4>Test with logger command:</h4>
            <div class="code">
logger -n <span id="server-ip-3">SERVER_IP</span> -P 514 "Test message from $(hostname)"
            </div>

            <h4>Python example:</h4>
            <div class="code">
import logging.handlers<br>
handler = logging.handlers.SysLogHandler(address=('<span id="server-ip-4">SERVER_IP</span>', 514))<br>
logger = logging.getLogger('test')<br>
logger.addHandler(handler)<br>
logger.info('Test log message')
            </div>
        </div>
    </div>

    <script>
        // Get server IP and update placeholders
        const serverIP = window.location.hostname;
        document.getElementById('server-ip').textContent = serverIP;
        document.getElementById('server-ip-2').textContent = serverIP;
        document.getElementById('server-ip-3').textContent = serverIP;
        document.getElementById('server-ip-4').textContent = serverIP;

        function refreshStats() {
            document.getElementById('log-count').textContent = 'N/A';
            document.getElementById('file-size').textContent = 'N/A';
            document.getElementById('last-updated').textContent = new Date().toLocaleString();
        }

        // Initialize stats on page load
        refreshStats();
    </script>
</body>
</html>
EOF

# Set permissions
chown -R ec2-user:ec2-user /opt/syslog-collector
chmod -R 755 /opt/syslog-collector

# Start services (use full path for docker-compose)
cd /opt/syslog-collector
/usr/local/bin/docker-compose up -d

# Add ec2-user to docker group
usermod -a -G docker ec2-user

# Create a startup script
cat > /etc/systemd/system/syslog-collector.service << 'EOF'
[Unit]
Description=Syslog Collector
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
RemainAfterExit=true
WorkingDirectory=/opt/syslog-collector
ExecStart=/usr/local/bin/docker-compose up -d
ExecStop=/usr/local/bin/docker-compose down
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
EOF

systemctl enable syslog-collector.service
