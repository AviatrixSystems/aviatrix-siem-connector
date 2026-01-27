#!/bin/bash
# Webhook Viewer - Local Development
# Uses tarampampam/webhook-tester for viewing incoming webhooks
#
# Usage:
#   ./run.sh              # Start on default port 8080
#   ./run.sh 9000         # Start on custom port
#   ./run.sh stop         # Stop the container
#   ./run.sh logs         # View container logs
#   ./run.sh status       # Check if running

CONTAINER_NAME="webhook-tester"
IMAGE="ghcr.io/tarampampam/webhook-tester:2"
DEFAULT_PORT=8080

show_help() {
    echo "Webhook Viewer - Local Development Tool"
    echo ""
    echo "Usage: ./run.sh [command|port]"
    echo ""
    echo "Commands:"
    echo "  start [port]  Start the webhook viewer (default port: $DEFAULT_PORT)"
    echo "  stop          Stop the webhook viewer"
    echo "  restart       Restart the webhook viewer"
    echo "  logs          View container logs"
    echo "  status        Check if running"
    echo "  help          Show this help message"
    echo ""
    echo "Examples:"
    echo "  ./run.sh              # Start on port $DEFAULT_PORT"
    echo "  ./run.sh 9000         # Start on port 9000"
    echo "  ./run.sh start 9000   # Start on port 9000"
    echo "  ./run.sh stop         # Stop the container"
    echo ""
    echo "Once started, open http://localhost:<port> in your browser."
    echo "Create a new session to get a unique webhook URL for testing."
}

check_docker() {
    if ! command -v docker &> /dev/null; then
        echo "Error: Docker is not installed or not in PATH"
        exit 1
    fi

    if ! docker info &> /dev/null; then
        echo "Error: Docker daemon is not running"
        exit 1
    fi
}

start_container() {
    local port="${1:-$DEFAULT_PORT}"

    # Check if already running
    if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        echo "Webhook viewer is already running on port $(docker port $CONTAINER_NAME 8080 | cut -d: -f2)"
        echo "URL: http://localhost:$(docker port $CONTAINER_NAME 8080 | cut -d: -f2)"
        return 0
    fi

    # Remove stopped container if exists
    docker rm -f "$CONTAINER_NAME" 2>/dev/null

    echo "Starting webhook viewer on port $port..."
    docker run -d \
        --name "$CONTAINER_NAME" \
        -p "${port}:8080/tcp" \
        --restart unless-stopped \
        "$IMAGE"

    if [ $? -eq 0 ]; then
        echo ""
        echo "Webhook viewer started successfully!"
        echo ""
        echo "  UI:        http://localhost:${port}"
        echo "  Container: $CONTAINER_NAME"
        echo ""
        echo "To create a webhook endpoint:"
        echo "  1. Open the UI in your browser"
        echo "  2. Click 'New' to create a session"
        echo "  3. Copy the generated webhook URL"
        echo ""
        echo "To stop: ./run.sh stop"
    else
        echo "Failed to start webhook viewer"
        exit 1
    fi
}

stop_container() {
    if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        echo "Stopping webhook viewer..."
        docker stop "$CONTAINER_NAME"
        docker rm "$CONTAINER_NAME"
        echo "Stopped."
    else
        echo "Webhook viewer is not running."
        # Clean up stopped container if exists
        docker rm "$CONTAINER_NAME" 2>/dev/null
    fi
}

show_logs() {
    if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        docker logs -f "$CONTAINER_NAME"
    else
        echo "Webhook viewer container not found."
        exit 1
    fi
}

show_status() {
    if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        local port=$(docker port $CONTAINER_NAME 8080 2>/dev/null | cut -d: -f2)
        echo "Webhook viewer is RUNNING"
        echo "  URL:       http://localhost:${port}"
        echo "  Container: $CONTAINER_NAME"
        echo ""
        docker ps --filter "name=$CONTAINER_NAME" --format "table {{.Status}}\t{{.Ports}}"
    else
        echo "Webhook viewer is NOT running"
        exit 1
    fi
}

# Main
check_docker

case "${1:-start}" in
    start)
        start_container "$2"
        ;;
    stop)
        stop_container
        ;;
    restart)
        stop_container
        start_container "$2"
        ;;
    logs)
        show_logs
        ;;
    status)
        show_status
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        # Assume it's a port number
        if [[ "$1" =~ ^[0-9]+$ ]]; then
            start_container "$1"
        else
            echo "Unknown command: $1"
            echo ""
            show_help
            exit 1
        fi
        ;;
esac
