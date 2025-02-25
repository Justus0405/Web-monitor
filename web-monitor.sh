#!/bin/bash

# Global variables
export version="1.0"
export port="8080"

# Color variables
export red="\e[1;31m"
export green="\e[1;32m"
export yellow="\e[1;33m"
export cyan="\e[1;36m"
export gray="\e[1;90m"
export bold="\e[1m"
export endColor="\e[0m"

# Info variables
export success="${gray}[${green}✓${gray}]${endColor}"
export error="${red}Error:${endColor}"
export warning="${gray}[${red}!${gray}]${endColor}"
export section="${gray}[${yellow}!${gray}]${endColor}"
export info="${gray}[${cyan}i${gray}]${endColor}"

# Functions
checkArgs() {
    case $1 in
    "start")
        startService
        ;;
    "stop")
        stopService
        ;;
    "restart")
        stopService
        startService
        ;;
    "status")
        showStatus
        ;;
    "help")
        showHelp
        ;;
    "version")
        showVersion
        ;;
    "")
        echo -e "${error} no operation specified. Use $0 help"
        exit 1
        ;;
    *)
        echo -e "${error} unrecognized option '$1'. Use $0 help"
        exit 1
        ;;
    esac
}

findTempPath() {
    local potentialPaths=(
        "/sys/class/thermal/thermal_zone0/temp"
        "/sys/class/thermal/thermal_zone1/temp"
        "/sys/class/hwmon/hwmon0/temp1_input"
        "/sys/class/hwmon/hwmon1/temp1_input"
        "/sys/class/hwmon/hwmon0/temp2_input"
        "/sys/class/hwmon/hwmon1/temp2_input"
    )
    for path in "${potentialPaths[@]}"; do
        if [[ -f "$path" ]]; then
            # Check if the sensor returns a valid value
            tempValue=$(cat "$path")
            if [[ $tempValue =~ ^[0-9]+$ ]]; then
                tempPath="$path"
                return 0
            fi
        fi
    done
}

getData() {
    # System Overview
    showHostname=$(cat /etc/hostname)
    showKernel=$(uname -r)
    showUptime=$(uptime -p | sed 's/up //')
    if [[ -f "/etc/machine-id" ]]; then
        showAge=$((($(date +%s) - $(date -r "/etc/machine-id" +%s)) / 86400))
    else
        showAge="Error: File not found"
    fi
    showCpu=$(uptime | awk -F 'load average:' '{ print $2 }' | xargs)
    showCpuTemp=$(($(cat "$tempPath") / 1000))
    showRam=$(free -m | awk 'NR==2{used=$3; total=$2; printf "%dmb / %dmb (%.0f%%)", used, total, used/total*100}')
    showDiskFull=$(df -h --total | awk '/total/ {printf "%s / %s (%s)", $3, $2, $5}')
    showLocalIp=$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '127.0.0.1' | head -n 1)

    # System Stats
    showCpuStat=$(lscpu | grep "Model name" | sed 's/Model name: //')
    cpuPercentage=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}')

    showRamStat=$(free -g | awk 'NR==2{used=$3; total=$2; printf "%dGb / %dGb (%.0f%%)", used, total, used/total*100}')
    ramPercentage=$(free -m | awk 'NR==2{used=$3; total=$2; printf "%.0f", used/total*100}')

    showDiskRoot=$(df -h / | awk 'NR==2{printf "%s / %s (%s)", $3, $2, $5}')

    showNetworkStat=$(lspci | grep -i "Ethernet" | sed 's/.*Ethernet controller: //' | cut -c 1-32)

    # Footer
    currentTime=$(date +"%d-%m-%Y %H:%M:%S")
}

exportResponse() {
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
                <span>Hostname:</span> ${showHostname}
            </div>
            <div class='info'>
                <span>Uptime:</span> ${showUptime}
            </div>
            <div class='info'>
                <span>Age:</span> ${showAge} days
            </div>
            <h3>Hardware:</h3>
            <div class='info'>
                <span>Kernel:</span> ${showKernel}
            </div>
            <div class='info'>
                <span>Cpu-load:</span> ${showCpu}
            </div>
            <div class='info'>
                <span>Cpu-temp:</span> ${showCpuTemp}°C
            </div>
            <div class='info'>
                <span>Ram:</span> ${showRam}
            </div>
        </div>
        <div class='panel'>
            <h1>Statistics</h1>
            <div class='stats'>
                <div class='stat'>
                    <h3>Processor</h3>
                    <p>${showCpuStat}</p>
                    <div class='graph'>
                        <div class='graph-bar' style='width: ${cpuPercentage}%;'></div>
                    </div>
                </div>
                <div class='stat'>
                    <h3>Disk</h3>
                    <p>Full ${showDiskFull}</p>
                    <p>Root ${showDiskRoot}</p>
                </div>
                <div class='stat'>
                    <h3>Ram</h3>
                    <p>${showRamStat}</p>
                    <div class='graph'>
                        <div class='graph-bar' style='width: ${ramPercentage}%;'></div>
                    </div>
                </div>
                <div class='stat'>
                    <h3>Network</h3>
                    <p>${showNetworkStat}</p>
                    <p>${showLocalIp}</p>
                </div>
            </div>
        </div>
        <div class='footer'>
            <p>Dashboard By Justus0405 | Last Updated: ${currentTime}</p>
        </div>
</body>

</html>"
}

startService() {
    findTempPath
    while :; do
        getData
        exportResponse
        echo -e "HTTP/1.1 200 OK\nContent-Type: text/html\n\n$response" | nc -l -k -p $port -q 1 || {
            echo -e "${endColor} netcat is not installed. Please install it either 'netcat-openbsd' or 'openbsd-netcat'"
            exit 1
        }
    done &
    echo $! >".serverPid"
    echo -e "${success} Started server on port: $port"
}

stopService() {
    if [ -f ".serverPid" ]; then
        pid=$(cat ".serverPid")
        if kill -9 "$pid" >/dev/null 2>&1; then
            echo -e "${success} Stopped server with PID: $pid"
            rm -f ".serverPid"
        else
            echo -e "${error} No PID associated with that process. Did the server crash? Removed Cache..."
            rm -f ".serverPid"
        fi
    else
        echo -e "${info} No server PID found. Server is not running."
    fi
}

showStatus() {
    if [ -f ".serverPid" ]; then
        pid=$(cat ".serverPid")
        echo -e "${info} Server is running with PID: $pid"
    else
        echo -e "${info} No server PID found. Server is not running."
    fi
    exit 0
}

showHelp() {
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

showVersion() {
    echo -e "               web-monitor v$version - bash 5.2.37"
    echo -e "               Copyright (C) 2025-present Justus0405"
    echo -e ""
    exit 0
}

# PROGRAM START

checkArgs "$@"
