#!/bin/sh
# Generate custom nginx welcome page with subnet and IP information
# This script runs inside the container at startup

set -e

# Get container information
HOSTNAME=$(hostname)
PRIVATE_IP=$(hostname -i | awk '{print $1}')

# Create custom HTML page
cat > /usr/share/nginx/html/index.html <<EOF
<!DOCTYPE html>
<html>
<head>
    <title>Azure Container - ${SUBNET_NAME}</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            max-width: 800px;
            margin: 50px auto;
            padding: 20px;
            background-color: #f5f5f5;
        }
        .container {
            background-color: white;
            padding: 30px;
            border-radius: 8px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }
        h1 {
            color: #0078d4;
            border-bottom: 3px solid #0078d4;
            padding-bottom: 10px;
        }
        .info-grid {
            display: grid;
            grid-template-columns: 200px 1fr;
            gap: 15px;
            margin-top: 20px;
        }
        .label {
            font-weight: bold;
            color: #666;
        }
        .value {
            color: #333;
            font-family: 'Courier New', monospace;
        }
        .subnet-badge {
            display: inline-block;
            background-color: #0078d4;
            color: white;
            padding: 5px 15px;
            border-radius: 4px;
            font-size: 14px;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>Azure Container Instance</h1>
        <p><span class="subnet-badge">${SUBNET_NAME:-unknown}</span></p>

        <div class="info-grid">
            <div class="label">Container Name:</div>
            <div class="value">${CONTAINER_NAME:-unknown}</div>

            <div class="label">Hostname:</div>
            <div class="value">${HOSTNAME}</div>

            <div class="label">Private IP:</div>
            <div class="value">${PRIVATE_IP}</div>

            <div class="label">Subnet:</div>
            <div class="value">${SUBNET_NAME:-unknown}</div>

            <div class="label">Subnet CIDR:</div>
            <div class="value">${SUBNET_CIDR:-unknown}</div>

            <div class="label">VNET:</div>
            <div class="value">${VNET_NAME:-unknown}</div>
        </div>

        <hr style="margin: 30px 0; border: none; border-top: 1px solid #ddd;">

        <p style="color: #666; font-size: 14px;">
            This page demonstrates Azure networking. The container is running in the specified subnet
            and can be accessed from other subnets based on NSG rules and routing configuration.
        </p>
    </div>
</body>
</html>
EOF

# Start nginx
exec nginx -g 'daemon off;'
