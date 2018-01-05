#!/usr/bin/env bash

#Compile
mvn clean package

# Project configuration
oc login -u developer
oc new-project clarksnut

APISERVER=$(oc version | grep Server | sed -e 's/.*http:\/\///g' -e 's/.*https:\/\///g')
NODE_IP=$(echo "${APISERVER}" | sed -e 's/:.*//g')
EXPOSER="Route"

TEMPLATE="packages/clarksnut-full-dependencies/target/classes/META-INF/fabric8/openshift.yml"

echo "Connecting to the API Server at: https://${APISERVER}"
echo "Using Node IP ${NODE_IP} and Exposer strategy: ${EXPOSER}"

# Elasticsearch configuration
oc login -u system:admin
echo "Now adding the SecurityContextConstraints to elasticsearch service account"
echo '{
  "apiVersion": "v1",
  "kind": "SecurityContextConstraints",
  "metadata": {
    "name": "scc-elasticsearch"
  },
  "allowPrivilegedContainer": true,
  "runAsUser": {
    "type": "RunAsAny"
  },
  "seLinuxContext": {
    "type": "RunAsAny"
  },
  "fsGroup": {
    "type": "RunAsAny"
  },
  "supplementalGroups": {
    "type": "RunAsAny"
  },
  "allowedCapabilities": [
    "IPC_LOCK",
    "SYS_RESOURCE"
  ]
}' | oc create -f -

echo "Now adding daemon"
echo '{
    "apiVersion" : "extensions/v1beta1",
    "kind" : "DaemonSet",
    "metadata" : {
      "name" : "sysctl-conf",
      "labels" : {
        "component" : "elasticsearch",
        "role" : "sysctl-conf"
      }
    },
    "spec" : {
      "template" : {
        "selector" : {
          "matchLabels" : {
             "component" : "elasticsearch"
            }
          },
        "metadata" : {
          "labels" : {
            "component" : "elasticsearch",
            "role" : "sysctl-conf"
          }
        },
        "spec" : {
          "containers" : [ {
            "name" : "sysctl-conf",
            "image" : "busybox:1.26.2",
            "command" : [ "sh", "-c", "sysctl -w vm.max_map_count=262166 && while true; do sleep 86400; done" ],
            "securityContext" : {
              "privileged" : true
            },
            "resources" : {
              "limits" : {
                "cpu" : "10m",
                "memory" : "50Mi"
              },
              "requests" : {
                "cpu" : "10m",
                "memory" : "50Mi"
              }
            }
          } ],
          "terminationGracePeriodSeconds" : 1
        }
      }
    }
}' | oc create -f -

oc adm policy add-scc-to-user scc-elasticsearch system:serviceaccount:$(oc project -q):default
oc policy add-role-to-user view system:serviceaccount:$(oc project -q):default

# General configuration
oc login -u developer
echo "Applying the CLARKSNUT template ${TEMPLATE}"
oc process -f ${TEMPLATE} -p APISERVER_HOSTPORT=${APISERVER} -p NODE_IP=${NODE_IP} -p EXPOSER=${EXPOSER} | oc apply -f -
echo "Please wait while the pods all startup!"