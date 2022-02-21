#!/bin/bash -e

# NUMA_0 "0-23,96-119"
# NUMA_1 "24-47,120-143"
# NUMA_2 "48-71,144-167"
# NUMA_3 "72-95,168-191"

case "$1" in
        outside)
            CORES_NUMA="72-83,168-179"
            ;;
        inside)
            CORES_NUMA="84-95,180-191"
            ;;
        wifi)
	    CORES_NUMA="48-59,144-155"
            ;;
        *)
            echo $"Usage: $0 {inside|wifi|outside}"
            exit 1
esac

INFLUXD_CONF_FILE="/etc/influxdb/influxdb-$1.conf"
INFLUXD_PID_FILE="/var/lib/influxdb/influxd-$1.pid"

if [ -f "$INFLUXD_PID_FILE" ]; then
    echo "PID file for influxd-$1 already found!"
    echo "   "$INFLUXD_PID_FILE "("`cat $INFLUXD_PID_FILE`")"
    exit 1
fi

numactl -C $CORES_NUMA /usr/bin/influxd -config $INFLUXD_CONF_FILE $INFLUXD_OPTS &
PID=`ps aux | grep "/usr/bin/influxd -config $INFLUXD_CONF_FILE" | grep ^influxdb | xargs | cut -d" " -f2`
echo $PID > $INFLUXD_PID_FILE

PROTOCOL="http"
BIND_ADDRESS=$(influxd config -config $INFLUXD_CONF_FILE | grep -A5 "\[http\]" | grep '^  bind-address' | cut -d ' ' -f5 | tr -d '"')
HTTPS_ENABLED_FOUND=$(influxd config -config $INFLUXD_CONF_FILE | grep "https-enabled = true" | cut -d ' ' -f5)
HTTPS_ENABLED=${HTTPS_ENABLED_FOUND:-"false"}
if [ $HTTPS_ENABLED = "true" ]; then
  HTTPS_CERT=$(influxd config -config $INFLUXD_CONF_FILE | grep "https-certificate" | cut -d ' ' -f5 | tr -d '"')
  if [ ! -f "${HTTPS_CERT}" ]; then
    echo "${HTTPS_CERT} not found! Exiting..."
    exit 1
  fi
  echo "$HTTPS_CERT found"
  PROTOCOL="https"
fi
HOST=${BIND_ADDRESS%%:*}
HOST=${HOST:-"localhost"}
PORT=${BIND_ADDRESS##*:}

set +e
attempts=0
url="$PROTOCOL://$HOST:$PORT/health"
echo $url

result=$(curl -k -s -o /dev/null $url -w %{http_code})
while [ "${result:0:2}" != "20" ] && [ "${result:0:2}" != "40" ]; do
  attempts=$(($attempts+1))
  echo "InfluxDB API unavailable after $attempts attempts..."
  sleep 1
  result=$(curl -k -s -o /dev/null $url -w %{http_code})
done
echo "InfluxDB started"
set -e

