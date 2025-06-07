#!/bin/bash
# Server Diagnostics Script

LOGFILE="/var/log/server_diag_$(date +%F_%T).log"

echo "✨ Starting enhanced server diagnostics..." | tee -a $LOGFILE

############################################################
## 0. Pre-check: update repos and install essential tools
echo -e "\n🔧 [0] Updating repos and installing essential tools..." | tee -a $LOGFILE
yum install -y sysstat httpd-tools net-tools lsof wget curl -q >/dev/null 2>&1

############################################################
## 1. Disk I/O Check
echo -e "\n📁 [1] Checking Disk I/O with iostat" | tee -a $LOGFILE
iostat -x 1 3 | tee -a $LOGFILE

############################################################
## 2. CPU & Memory Check
echo -e "\n💻 [2] Checking CPU and Memory Usage" | tee -a $LOGFILE
ps -eo pid,ppid,cmd,%mem,%cpu --sort=-%cpu | head -n 15 | tee -a $LOGFILE

free -h | tee -a $LOGFILE
swapon --show | tee -a $LOGFILE

############################################################
## 3. Disk Space Usage
echo -e "\n💾 [3] Checking Disk Space Usage" | tee -a $LOGFILE
df -h | tee -a $LOGFILE

############################################################
## 4. Database Slow Query Check
echo -e "\n🛢️ [4] Checking MySQL/MariaDB Slow Queries" | tee -a $LOGFILE
mysqladmin processlist | grep -Ei 'sleep|Locked|Query' | tee -a $LOGFILE

mysqladmin extended-status | grep -E "Slow_queries|Threads_connected|Threads_running" | tee -a $LOGFILE

############################################################
## 5. PHP Handler & Performance Check
echo -e "\n⚙️ [5] Checking PHP Version & Handler" | tee -a $LOGFILE
if command -v /usr/local/cpanel/bin/rebuild_phpconf &>/dev/null; then
  /usr/local/cpanel/bin/rebuild_phpconf --current | tee -a $LOGFILE
else
  echo "No cPanel PHP handler found." | tee -a $LOGFILE
fi

php -v | head -n 1 | tee -a $LOGFILE

echo "<?php phpinfo(); ?>" > /usr/local/apache/htdocs/info.php
ab -n 100 -c 10 http://127.0.0.1/info.php | grep "Requests per second" | tee -a $LOGFILE
rm -f /usr/local/apache/htdocs/info.php

############################################################
## 6. Network Latency & Speed Test
echo -e "\n🌐 [6] Checking Network Connectivity & Download Speed" | tee -a $LOGFILE
ping -c 4 8.8.8.8 | tee -a $LOGFILE

curl -s https://speed.hetzner.de/100MB.bin -o /dev/null -w "Download speed: %{speed_download} bytes/sec\n" | tee -a $LOGFILE

############################################################
## 7. Firewall Status
echo -e "\n🔥 [7] Checking Firewall Rules (iptables & firewalld)" | tee -a $LOGFILE
iptables -L -v -n | tee -a $LOGFILE
if command -v firewall-cmd &>/dev/null; then
  firewall-cmd --state | tee -a $LOGFILE
  firewall-cmd --list-all | tee -a $LOGFILE
else
  echo "firewalld is not installed." | tee -a $LOGFILE
fi

############################################################
## 8. Check Web Server Status (Apache, Nginx, LiteSpeed)
echo -e "\n🌐 [8] Checking Web Server (Apache/Nginx/LiteSpeed) Status" | tee -a $LOGFILE
if systemctl list-unit-files | grep -q "httpd.service"; then
  echo -e "\n-- Apache (httpd) Status:" | tee -a $LOGFILE
  systemctl status httpd | tee -a $LOGFILE
  echo -e "\n-- Apache Listening Ports:" | tee -a $LOGFILE
  ss -tuln | grep ':80\|:443' | tee -a $LOGFILE
  echo -e "\n-- Testing Apache Response:" | tee -a $LOGFILE
  curl -I http://127.0.0.1 | tee -a $LOGFILE
elif systemctl list-unit-files | grep -q "nginx.service"; then
  echo -e "\n-- Nginx Status:" | tee -a $LOGFILE
  systemctl status nginx | tee -a $LOGFILE
  echo -e "\n-- Nginx Listening Ports:" | tee -a $LOGFILE
  ss -tuln | grep ':80\|:443' | tee -a $LOGFILE
  echo -e "\n-- Testing Nginx Response:" | tee -a $LOGFILE
  curl -I http://127.0.0.1 | tee -a $LOGFILE
elif systemctl list-unit-files | grep -q "litespeed.service"; then
  echo -e "\n-- LiteSpeed Status:" | tee -a $LOGFILE
  systemctl status litespeed | tee -a $LOGFILE
  echo -e "\n-- LiteSpeed Listening Ports:" | tee -a $LOGFILE
  ss -tuln | grep ':80\|:443' | tee -a $LOGFILE
  echo -e "\n-- Testing LiteSpeed Response:" | tee -a $LOGFILE
  curl -I http://127.0.0.1 | tee -a $LOGFILE
else
  echo "-- No supported web server (Apache/Nginx/LiteSpeed) detected." | tee -a $LOGFILE
fi

############################################################
## 9. Check Critical Services
echo -e "\n🛠️ [9] Checking Critical Services Status" | tee -a $LOGFILE
for service in mariadb mysql; do
  if systemctl list-unit-files | grep -q "${service}.service"; then
    echo -e "\n-- Status of $service:" | tee -a $LOGFILE
    systemctl status $service | tee -a $LOGFILE
  else
    echo "-- $service not installed." | tee -a $LOGFILE
  fi
done

############################################################
## 10. System Logs & Kernel Messages
echo -e "\n📝 [10] Checking System Logs & Kernel Messages" | tee -a $LOGFILE
echo -e "\n-- Last 20 lines of /var/log/messages:" | tee -a $LOGFILE
tail -n 20 /var/log/messages | tee -a $LOGFILE

echo -e "\n-- Kernel Ring Buffer (dmesg -T | tail):" | tee -a $LOGFILE
dmesg -T | tail -n 20 | tee -a $LOGFILE

############################################################
############################################################
## 11. Network Connections Analysis
echo -e "\n🔗 [11] Network Connections Analysis" | tee -a $LOGFILE

echo -e "\n-- Total Connections Count:" | tee -a $LOGFILE
netstat -an | wc -l | tee -a $LOGFILE

echo -e "\n-- Total Connections on Port 80:" | tee -a $LOGFILE
netstat -an | grep ':80' | wc -l | tee -a $LOGFILE

echo -e "\n-- Connections per IP (for DDoS detection):" | tee -a $LOGFILE
netstat -ntu | awk '{print $5}' | cut -d: -f1 | sort | uniq -c | sort -n | tee -a $LOGFILE

echo -e "\n-- Connections per IP with Port Info:" | tee -a $LOGFILE
netstat -na | awk '{print $5}' | cut -d "." -f1,2,3,4 | sort | uniq -c | sort -nr | tee -a $LOGFILE

echo -e "\n-- Connections per Port:" | tee -a $LOGFILE
netstat -tuna | awk -F':| +' 'NR>2{print $5}' | cut -d: -f2 | sort | uniq -c | sort -n | tee -a $LOGFILE

echo -e "\n✅ Diagnostics completed. Log file: $LOGFILE"

echo -e "\n📄 Log file content:\n"
cat "$LOGFILE"
