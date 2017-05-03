#!/bin/bash

docker-compose down
docker-compose pull

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

# Update hawkular javaagent configuration to make it suitable for tests.
docker-compose create hawkular
DOCKER_HAWKULAR_ID=`docker-compose ps -q hawkular`
export DOCKER_`docker inspect -f '{{range $index, $value := .Config.Env}}{{println $value}}{{end}}' $DOCKER_HAWKULAR_ID  | grep JBOSS_HOME`

docker cp ${DOCKER_HAWKULAR_ID}:${DOCKER_JBOSS_HOME}/standalone/configuration/hawkular-javaagent-config.yaml hawkular-javaagent-config.yaml
ruby ./.travis/build_config_for_testing.rb hawkular-javaagent-config.yaml
docker cp hawkular-javaagent-config.yaml ${DOCKER_HAWKULAR_ID}:${DOCKER_JBOSS_HOME}/standalone/configuration/hawkular-javaagent-config.yaml
rm hawkular-javaagent-config.yaml

# Ensure the volume exists and has correct permissions.
mkdir -p /tmp/opt/hawkular/server
chown 1000:1000 -R /tmp/opt/hawkular
docker-compose start hawkular
