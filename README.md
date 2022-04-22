# DELTA SPARK ON KUBERNETES


This is a step by step guide on how to setup up spark on a kubernetes cluster along with aws glue as a catalog along with delta lake.

# Prerequisites
1. Helm >= 3
1. Kubernetes >= 1.16

# Installation

To set this up you would need to use [spark-on-k8s-operator](https://github.com/GoogleCloudPlatform/spark-on-k8s-operator). As referred in the official doc the easiest way to get it is 

```
$ helm repo add spark-operator https://googlecloudplatform.github.io/spark-on-k8s-operator

$ helm install my-release spark-operator/spark-operator --namespace spark-operator --create-namespace
```

This will install the Kubernetes Operator for Apache Spark into the namespace spark-operator. The operator by default watches and handles SparkApplications in every namespaces. If you would like to limit the operator to watch and handle SparkApplications in a single namespace, e.g., default instead, add the following option to the helm install command:

```
--set sparkJobNamespace=default
```

For all the configuration options you can reffer the [official documentation](https://github.com/GoogleCloudPlatform/spark-on-k8s-operator/blob/master/charts/spark-operator-chart/README.md) for this. 


1. Make the Dockerfile or use the public [image ](joshi95/delta-spark-on-kubernetes-spark-3.1.1) 