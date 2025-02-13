#!/bin/bash

# Global variables
export VERSION="1.0"
export PORT="8080"

# Color variables
export RED="\e[1;31m"
export GREEN="\e[1;32m"
export YELLOW="\e[1;33m"
export CYAN="\e[1;36m"
export GRAY="\e[1;90m"
export BOLD="\e[1m"
export ENDCOLOR="\e[0m"

# Info variables
export SUCCESS="${GRAY}[${GREEN}✓${GRAY}]${ENDCOLOR}"
export ERROR="${RED}Error:${ENDCOLOR}"
export WARNING="${GRAY}[${RED}!${GRAY}]${ENDCOLOR}"
export SECTION="${GRAY}[${YELLOW}!${GRAY}]${ENDCOLOR}"
export INFO="${GRAY}[${CYAN}i${GRAY}]${ENDCOLOR}"

# Functions
check_args() {
    case $1 in
    "start")
        start_service
        ;;
    "stop")
        stop_service
        ;;
    "restart")
        stop_service
        start_service
        ;;
    "status")
        show_status
        ;;
    "help")
        show_help
        ;;
    "version")
        show_version
        ;;
    "")
        echo -e "${ERROR} no operation specified. Use $0 help"
        exit 1
        ;;
    *)
        echo -e "${ERROR} unrecognized option '$1'. Use $0 help"
        exit 1
        ;;
    esac
}

find_temp_path() {
    local potential_paths=(
        "/sys/class/thermal/thermal_zone0/temp"
        "/sys/class/thermal/thermal_zone1/temp"
        "/sys/class/hwmon/hwmon0/temp1_input"
        "/sys/class/hwmon/hwmon1/temp1_input"
        "/sys/class/hwmon/hwmon0/temp2_input"
        "/sys/class/hwmon/hwmon1/temp2_input"
    )
    for path in "${potential_paths[@]}"; do
        if [[ -f "$path" ]]; then
            # Check if the sensor returns a valid value
            temp_value=$(cat "$path")
            if [[ $temp_value =~ ^[0-9]+$ ]]; then
                TEMP_PATH="$path"
                return 0
            fi
        fi
    done
}

get_data() {
    # System Overview
    show_hostname=$(cat /etc/hostname)
    show_kernel=$(uname -r)
    show_uptime=$(uptime -p | sed 's/up //')
    if [[ -f "/etc/machine-id" ]]; then
        show_age=$((($(date +%s) - $(date -r "/etc/machine-id" +%s)) / 86400))
    else
        show_age="Error: File not found"
    fi
    show_cpu=$(uptime | awk -F 'load average:' '{ print $2 }' | xargs)
    show_cpu_temp=$(($(cat "$TEMP_PATH") / 1000))
    show_ram=$(free -m | awk 'NR==2{used=$3; total=$2; printf "%dmb / %dmb (%.0f%%)", used, total, used/total*100}')
    show_disk_full=$(df -h --total | awk '/total/ {printf "%s / %s (%s)", $3, $2, $5}')
    show_local_ip=$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '127.0.0.1' | head -n 1)

    # System Stats
    show_cpu_stat=$(lscpu | grep "Model name" | sed 's/Model name: //')
    cpu_percentage=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}')

    show_ram_stat=$(free -g | awk 'NR==2{used=$3; total=$2; printf "%dGb / %dGb (%.0f%%)", used, total, used/total*100}')
    ram_percentage=$(free -m | awk 'NR==2{used=$3; total=$2; printf "%.0f", used/total*100}')

    show_disk_root=$(df -h / | awk 'NR==2{printf "%s / %s (%s)", $3, $2, $5}')

    show_network_stat=$(lspci | grep -i "Ethernet" | sed 's/.*Ethernet controller: //' | cut -c 1-32)

    # Foother
    current_time=$(date +"%d-%m-%Y %H:%M:%S")
}

export_response() {
    export response="<!DOCTYPE html>
<html lang='en'>

<head>
    <meta charset='UTF-8'>
    <meta name='viewport' content='width=device-width, initial-scale=1.0'>
    <link rel='shortcut icon' href='https://www.svgrepo.com/show/375388/cloud-shell.svg' type='image/x-icon'>
    <title>Web-Monitor</title>
</head>

<style>
    /* Basic stuff */
    body {
        font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
        background-color: #131313;
        color: white;
        padding: 0px;
        margin: 0px;
    }

    .container {
        justify-content: space-between;
        display: flex;
        padding: 20px;
    }

    .panel {
        box-shadow: 0px 3px 10px black;
        background-color: #1e1e1e;
        border-radius: 5px;
        padding: 20px;
        width: 48%;
    }

    /* System Information */
    .info {
        font-size: 20px;
        margin: 10px;
    }

    .info span {
        font-weight: bold;
        color: #89b4fa;
    }

    /* System Statistics */
    .stats {
        grid-template-columns: 2fr 1fr;
        display: grid;
        gap: 15px;
    }

    .stat {
        background-color: #333;
        text-align: center;
        border-radius: 10px;
        padding: 25px;
    }

    .stat h3 {
        font-size: 25px;
        margin: 0;
    }

    .stat p {
        font-size: 16px;
        color: gray;
    }

    /* Graphs */
    .graph {
        background-color: #45475a;
        border-radius: 10px;
        position: relative;
        margin-top: 15px;
        height: 20px;
        width: 100%;
    }

    .graph-bar {
        background-color: #89b4fa;
        border-radius: 10px;
        position: absolute;
        height: 100%;
    }

    /* Footer */
    .footer {
        transform: translateX(-50%);
        position: fixed;
        color: gray;
        bottom: 10px;
        left: 50%;
    }

    /* Fancy support for small screens :3 */
    @media (max-width: 768px) {
        .container {
            flex-direction: column;
            align-items: center;
        }

        .panel {
            width: 90%;
            margin-bottom: 20px;
        }

        .stats {
            grid-template-columns: 1fr;
        }

        .footer {
            transform: translateX(-50%);
            position: relative;
            left: 50%;
        }
    }
</style>

<body>
    <div class='container'>
        <div class='panel'>
            <h1>Overview</h1>
            <h3>System Information:</h3>
            <div class='info'>
                <span>Hostname:</span> ${show_hostname}
            </div>
            <div class='info'>
                <span>Uptime:</span> ${show_uptime}
            </div>
            <div class='info'>
                <span>Age:</span> ${show_age} days
            </div>
            <h3>Hardware:</h3>
            <div class='info'>
                <span>Kernel:</span> ${show_kernel}
            </div>
            <div class='info'>
                <span>Cpu-load:</span> ${show_cpu}
            </div>
            <div class='info'>
                <span>Cpu-temp:</span> ${show_cpu_temp}°C
            </div>
            <div class='info'>
                <span>Ram:</span> ${show_ram}
            </div>
        </div>
        <div class='panel'>
            <h1>Statistics</h1>
            <div class='stats'>
                <div class='stat'>
                    <h3>Processor</h3>
                    <p>${show_cpu_stat}</p>
                    <div class='graph'>
                        <div class='graph-bar' style='width: ${cpu_percentage}%;'></div>
                    </div>
                </div>
                <div class='stat'>
                    <h3>Disk</h3>
                    <p>Full ${show_disk_full}</p>
                    <p>Root ${show_disk_root}</p>
                </div>
                <div class='stat'>
                    <h3>Ram</h3>
                    <p>${show_ram_stat}</p>
                    <div class='graph'>
                        <div class='graph-bar' style='width: ${ram_percentage}%;'></div>
                    </div>
                </div>
                <div class='stat'>
                    <h3>Network</h3>
                    <p>${show_network_stat}</p>
                    <p>${show_local_ip}</p>
                </div>
            </div>
        </div>
        <div class='footer'>
            <p>Dashboard By Justus0405 | Last Updated: ${current_time}</p>
        </div>
</body>

</html>"
}

start_service() {
    find_temp_path
    while :; do
        get_data
        export_response
        echo -e "HTTP/1.1 200 OK\nContent-Type: text/html\n\n$response" | nc -l -k -p $PORT -q 1 || {
            echo -e "${ENDCOLOR} netcat is not installed. Please install it either 'netcat-openbsd' or 'openbsd-netcat'"
            exit 1
        }
    done &
    echo $! >".server_pid"
    echo -e "${SUCCESS} Started server on port: $PORT"
}

stop_service() {
    if [ -f ".server_pid" ]; then
        PID=$(cat ".server_pid")
        if kill -9 "$PID" >/dev/null 2>&1; then
            echo -e "${SUCCESS} Stopped server with PID: $PID"
            rm -f ".server_pid"
        else
            echo -e "${ERROR} Failed to stop server. Process may not be running."
        fi
    else
        echo -e "${INFO} No server PID found. Server is not running."
    fi
}

show_status() {
    if [ -f ".server_pid" ]; then
        PID=$(cat ".server_pid")
        echo -e "${INFO} Server is running with PID: $PID"
    else
        echo -e "${INFO} No server PID found. Server is not running."
    fi
    exit 0
}

show_help() {
    echo -e "usage: $0 [...]"
    echo -e "arguments:"
    echo -e "    start"
    echo -e "    stop"
    echo -e "    restart"
    echo -e "    status"
    echo -e "    help"
    echo -e "    version"
    echo -e ""
    exit 0
}

show_version() {
    echo -e "               web-monitor v$VERSION - bash 5.2.37"
    echo -e "               Copyright (C) 2025-present Justus0405"
    echo -e ""
    exit 0
}

# PROGRAM START

check_args "$@"
