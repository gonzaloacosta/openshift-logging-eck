#!/bin/bash

# CronJob - Tomar Snapshot

# ElastiSearch por defecto guarda un indice por día con un histórico de tres dias
# en los servidores de infra. El script toma un snapshot del indice del día previo
# al día actual y lo guarda en el repo de snapshot previamente configurado. 
# Autor: Semperti

# Variables
DATE=$(date --date='-1 day' +"%Y.%m.%d")
INDICES="project.*.$DATE"
SNAPREPONAME='mysnapshots'

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
curl -s --key /etc/elasticsearch/secret/admin-key --cert /etc/elasticsearch/secret/admin-cert --cacert /etc/elasticsearch/secret/admin-ca "https://logging-es:9200/_cat/indices"

echo ">> Tomamos Snapshots del día $DATE"
curl -s -k --cert /etc/elasticsearch/secret/admin-cert --key /etc/elasticsearch/secret/admin-key  -X PUT "https://logging-es:9200/_snapshot/${SNAPREPONAME}/project.all-apps-projects.${DATE}?pretty" -H 'Content-Type: application/json' --data "$(generate_post_data)" 

echo ">> Listamos los Snapshots de ElasticSearch existentes del día $DATE"
curl -s -k --cert /etc/elasticsearch/secret/admin-cert --key /etc/elasticsearch/secret/admin-key  -X GET "https://logging-es:9200/_snapshot/${SNAPREPONAME}/_all?pretty"
