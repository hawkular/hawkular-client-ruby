#!/bin/bash

docker-compose up -d myCassandra

# Wait for Cassandra
CASSANDRA_STATUS="undecided"
TOTAL_WAIT=0;
while [ "$CASSANDRA_STATUS" != "running" ] && [ $TOTAL_WAIT -lt 60 ]; do
 CASSANDRA_STATUS=`docker-compose exec myCassandra nodetool statusbinary | tr -dc '[[:print:]]'`
 echo "Cassandra server status: $CASSANDRA_STATUS."

 sleep 3

 TOTAL_WAIT=$((TOTAL_WAIT+3))
 echo "Waited $TOTAL_WAIT seconds for Cassandra to start."
done

# Ensure the volume exists and has correct permissions.
mkdir -p /tmp/opt/hawkular/server
chown 1000:1000 -R /tmp/opt/hawkular
docker-compose up -d hawkular
