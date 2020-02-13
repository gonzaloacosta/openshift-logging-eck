#!/bin/bash

# CronJob - Delete Old Snapshot

# Los snapshots se guardan en el repo previamente configurado en el archivo de 
# configuraci√n de elasticsearch configurado en el configmaps logging-es.
# Para poder rotar los logs y guardar un maximo de 30 dias diariamente borramos 
# los snapshots mas viejos 

# Autor: Semperti

# Variables
DATE=$(date --date='-30 day' +"%Y.%m.%d")
INDICES="project.*.$DATE"
SNAPREPO='mysnapshots'

# Funciones
generate_post_data()
{
  cat <<EOF
{
  "indices": "$INDICES",
  "ignore_unavailable": true,
  "include_global_state": false
}
EOF
}

# MAIN
echo ">> Listamos los Indices de ElasticSearch existentes"
curl -s -k --cert /etc/elasticsearch/secret/admin-cert --key /etc/elasticsearch/secret/admin-key  -X GET "https://logging-es:9200/_snapshot/${SNAPREPONAME}/project.*.${DATE}?pretty"

SNAPCOUNT=$(curl -s -k --cert /etc/elasticsearch/secret/admin-cert --key /etc/elasticsearch/secret/admin-key  -X GET "https://logging-es:9200/_snapshot/${SNAPREPONAME}/project.*.2019.10.20?pretty" | awk -F: '/SUCCESS/{print $2}' | wc -l)

if [ $SNAPCOUNT -gt 0 ] ; then
	# Limpio los snapshots de hace 30 dias
	curl -s -k --cert /etc/elasticsearch/secret/admin-cert --key /etc/elasticsearch/secret/admin-key  -X DELETE "https://logging-es:9200/_snapshot/${SNAPREPONAME}/project.*.${DATE}?pretty"
fi
