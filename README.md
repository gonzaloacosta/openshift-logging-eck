	# Instalacion de Elasticsearch, Kibana y Cerebro para Openshift 3.9

Poder levantar en otro elasticsearch el backup de los snapshots tomados del elastisearch de Openshift 3.9.

## Pre-requisitos 
En el directorio de trabajo deben estar los siguientes archivos.


Storage snapshots projecto logging openshift 
```
pv-logging-snapshots.yml
pvc-logging-snapshots.yml
```

Storage restore de snapshots para proyecto semperti-eck
```
pv-elk-restore.yml
pvc-logging-snapshots.yml
```

Openshift Templates 
```
semperti-cerebro-temp.yml
semperti-es-temp.yml
semperti-kibana-temp.yml
```

### Instalacion templates para insta apps de Openshift 3.9

```
oc new-project semperti-eck
oc create -f semperti-elasticsearch-temp.yml
oc create -f semperti-kibana-temp.yml
oc create -f semperti-cerebro-temp.yml
```

### Crear volumenes para projecto logging, stack elk de openshift
El proyecto puede estar desplegado como logging o openshift-logging y previamente se debe contar con un 
volumen compartido en storage nfs, gluterfs, etc. Este volumen debe estar compartido entre todos los pods 
del despliegue de elasticsearch de openshift. 

```
oc project logging
oc create -f pv-logging-snapshots.yml
oc create -f pvc-logging-snapshots.yml
```

### Mapear el volumen recien creado con los deployments de elasticsearch

```
for i in $(oc get dc -o name | grep logging-es-data-master) ; do 
  oc volume $i --add --name=elasticsearch-snapshots -t pvc --claim-name=pvc-logging-snapshots -m /elasticsearch/persistent/logging-es/snapshots
done
```

### Editar el configMap para poder alojar el directorio de repo de snapshots


```
oc extract configmap/logging-elasticsearch --to=.
oc edit cm logging-elasticsearch
...
    path:
      ...
      repo: /elasticsearch/persistent/${CLUSTER_NAME}/snapshots
```
wq!

### Re desplegar los pod de elastisearcch
Se pueden hacer de a uno por vez o todos juntos, esto produce que se corte el servicio. Es recomendable hacerlo de a uno

```
for i in $(oc get dc -o name | grep logging-es-data-master) ; do 
  oc rollout latest $i 
  sleep 180
done
```

### Chequeamos que quede desplegado el volumen y el archivo de configuracion seteado correctamente

Chequeamos config/elasticsearch.yml
```
for i in $(oc get pods -o name | grep logging-es-data-master | sed 's/^pods\///') 
do  
  oc exec $i -- grep repo config/elasticsearch.yml 2>/dev/null; done
done
```

Chequeamos volume
```
for i in $(oc get pods -o name | grep logging-es-data-master | sed 's/^pods\///')  
do  
  oc exec $i -- df -hT /elasticsearch/persistent/logging-es/snapshots 
done
```

## Realizamos Snapshot 
En este paso hacemos el backup de la data persistente de elasticsearch al volumen que previamente hemos configurado en los pv y pvc

### Configuracion del repo
Desde un pod de elasticsearch o con el comando oc exec $pod_name --. En este caso accedemos a un pod.

```
oc rsh pods/logging-es-data-master-zycxl35d-16-9q6dh
$ 
``` 

dentro de el ejecutamos los curls.

### Chequeamos conectividad contra elasticsearch
```
 curl -s -k --cert /etc/elasticsearch/secret/admin-cert --key /etc/elasticsearch/secret/admin-key https://localhost:9200/
```

### Definimos repo para snapshots de tipo fs
El repo que vamos a definir en el proyecto logging y alojarálos snapshots que tomemos se llamara 'mysnapshots' pero puede tomarse cualquier
nombre. El parametro location deberá ser el mismo qeu el directorio que mapeamos con el volument/pvc.

```
curl -s -k --cert /etc/elasticsearch/secret/admin-cert --key /etc/elasticsearch/secret/admin-key -XPUT https://localhost:9200/_snapshot/mysnapshots -d '{
  "type": "fs",
  "settings": {
     "location": "/elasticsearch/persistent/logging-es/snapshots",
     "compress": true
  }
}'
```

### Chequeamos el repo creado
```
curl -s -k --cert /etc/elasticsearch/secret/admin-cert --key /etc/elasticsearch/secret/admin-key https://localhost:9200/_snapshot/mysnapshots\?pretty 
```

### Verificamos los indices y elegimos el que deseamos backupear 

Vemos todos los indices

```
$ curl -s -k --cert /etc/elasticsearch/secret/admin-cert --key /etc/elasticsearch/secret/admin-key https://localhost:9200/_cat/indices 
```


El indice elegido en este caso es el que posee el nombre project.elk.55d2f587-c8ce-11e9-918e-001a4ae6ef01.2019.08.29

```
curl -s -k --cert /etc/elasticsearch/secret/admin-cert --key /etc/elasticsearch/secret/admin-key https://localhost:9200/project.elk.55d2f587-c8ce-11e9-918e-001a4ae6ef01.2019.08.29/_settings/?pretty
 
```
### Tomamos un snapshot
El nombre del snapshot sera snapshot_1

```
curl -s -k --cert /etc/elasticsearch/secret/admin-cert --key /etc/elasticsearch/secret/admin-key  -X PUT "https://localhost:9200/_snapshot/mysnapshots/snapshot_1?pretty" -H 'Content-Type: application/json' -d'
{
  "indices": "project.elk.55d2f587-c8ce-11e9-918e-001a4ae6ef01.2019.08.29",
  "ignore_unavailable": true,
  "include_global_state": false
}
' 
```

### Chequeamos el snapshot_1
El estado final debe ser SUCCESS para que pueda ser restoreado.

```
$ curl -s -k --cert /etc/elasticsearch/secret/admin-cert --key /etc/elasticsearch/secret/admin-key "https://localhost:9200/_snapshot/mysnapshots/snapshot_1?pretty"
...
    "state" : "SUCCESS",
...
```

## Restore de Snapshots

### montar el volumen en el mismo filesystem

```
oc volume deployments/semperti-es --add --name=semperti-es-snapshots -t pvc --claim-name=pvc-elk-restore -m /restore
```

### Chequeamos repo de snapshots

```
curl -XPUT http://localhost:9200/_snapshot/mysnapshots -d '{
  "type": "fs",
  "settings": {
     "location": "/restore/logging-es/snapshots/",
     "compress": true
  }
}'
```

### Chequeamos que el repositorio haya sido creadoo

```
curl http://localhost:9200/_snapshot/?pretty
{
  "mysnapshots" : {
    "type" : "fs",
    "settings" : {
      "compress" : "true",
      "location" : "/restore/logging-es/snapshots/"
    }
  }
}
```


### Verificamos que el snapshot_1 se pueda visualizar desde el otro proyecto.

```
curl http://localhost:9200/_snapshot/mysnapshots/snapshot_1/?pretty
{
  "snapshots" : [ {
    "snapshot" : "snapshot_1",
    "version_id" : 2040499,
    "version" : "2.4.4",
    "indices" : [ "project.elk.55d2f587-c8ce-11e9-918e-001a4ae6ef01.2019.08.29" ],
    "state" : "SUCCESS",
    "start_time" : "2019-08-29T15:54:12.396Z",
    "start_time_in_millis" : 1567094052396,
    "end_time" : "2019-08-29T15:54:12.857Z",
    "end_time_in_millis" : 1567094052857,
    "duration_in_millis" : 461,
    "failures" : [ ],
    "shards" : {
      "total" : 3,
      "failed" : 0,
      "successful" : 3
    }
  } ]
}
```

### Realizamos restore del snapshot_1 el directorio entre los dos proyectos tiene que tener acceso de escritura para que se pueda hacer el restore.
```
curl -XPOST http://localhost:9200/_snapshot/mysnapshots/snapshot_1/_restore/?pretty
{
  "accepted" : true
}
```

### Chequeamos que el indice haya sido restoreado.

### curl http://localhost:9200/_cat/indices/
```
green  open project.elk.55d2f587-c8ce-11e9-918e-001a4ae6ef01.2019.08.29 3 0 961 0 737.8kb 737.8kb
yellow open .kibana                                                     1 1   1 0   3.1kb   3.1kb
```
#

### Lo podemos ver desde cerebro el estado del indice o sino consultar su contenido.
```
curl -X POST http://localhost:9200/project.elk.55d2f587-c8ce-11e9-918e-001a4ae6ef01.2019.08.29/_search
```
....

