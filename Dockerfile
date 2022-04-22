FROM python:3.7-slim-stretch as build-deps
ENV maven_version=3.6.3
ENV hive_version=2.3.7
ENV aws_java_sdk_version=1.11.797
ENV hadoop_version=3.2.0
ENV spark_version=3.1.1

RUN apt-get update \
  && echo "deb http://ftp.us.debian.org/debian sid main" >> /etc/apt/sources.list \
  && mkdir -p /usr/share/man/man1 \
  && apt-get install -y git curl wget openjdk-8-jdk patch \
  && rm -rf /var/cache/apt/*


RUN cd /opt \
  &&  wget https://downloads.apache.org/maven/maven-3/$maven_version/binaries/apache-maven-$maven_version-bin.tar.gz \
  &&  tar zxvf /opt/apache-maven-$maven_version-bin.tar.gz \
  &&  rm apache-maven-$maven_version-bin.tar.gz

ENV PATH=/opt/apache-maven-$maven_version/bin:$PATH
ENV MAVEN_HOME /opt/apache-maven-$maven_version

# configure the pentaho nexus repo to prevent build errors
# similar to the following: https://github.com/apache/hudi/issues/2479
COPY ./maven-settings.xml $MAVEN_HOME/conf/settings.xml

FROM build-deps as build-glue-hive-client

RUN wget https://github.com/apache/hive/archive/rel/release-$hive_version.tar.gz -O hive.tar.gz
RUN mkdir hive && tar xzf hive.tar.gz --strip-components=1 -C hive

## Build patched hive 2.3.7
# https://github.com/awslabs/aws-glue-data-catalog-client-for-apache-hive-metastore/issues/26
WORKDIR /hive
# Patch copied from: https://issues.apache.org/jira/secure/attachment/12958418/HIVE-12679.branch-2.3.patch
COPY ./aws-glue-spark-hive-client/HIVE-12679.branch-2.3.patch hive.patch
RUN patch -p0 <hive.patch && mvn clean  install -DskipTests

# Now with hive patched and installed, build the glue client
RUN git clone https://github.com/viaduct-ai/aws-glue-data-catalog-client-for-apache-hive-metastore /catalog

WORKDIR /catalog

RUN mvn clean package \
  -DskipTests \
  -Dhive2.version=$hive_version \
  -Dhadoop.version=$hadoop_version \
  -Daws.sdk.version=$aws_java_sdk_version \
  -pl -aws-glue-datacatalog-hive2-client

FROM build-glue-hive-client as build-spark

# Build spark
WORKDIR /
RUN git clone https://github.com/apache/spark.git --branch v$spark_version --single-branch 
RUN cd /spark && \
  ./dev/make-distribution.sh \
  --name spark \
  --pip \
  -DskipTests \
  -Pkubernetes \
  -Phadoop-cloud \
  -P"hadoop-$hadoop_version%.*" \
  -Dhadoop.version="$hadoop_version" \
  -Dhive.version="$hive_version" \
  -Phive \
  -Phive-thriftserver

# copy the glue client jars to spark jars directory
RUN find /catalog -name "*.jar" | grep -Ev "test|original" | xargs -I{} cp {} /spark/dist/jars/

RUN rm /spark/dist/jars/aws-java-sdk-bundle-*.jar
RUN wget --quiet https://repo1.maven.org/maven2/com/amazonaws/aws-java-sdk-bundle/$aws_java_sdk_version/aws-java-sdk-bundle-$aws_java_sdk_version.jar -P /spark/dist/jars/
RUN chmod 0644 /spark/dist/jars/aws-java-sdk-bundle*.jar

# replace with guava version compatible with latest aws-java-sdk-bundle
RUN rm -f /spark/dist/jars/guava-14.0.1.jar
RUN wget --quiet https://repo1.maven.org/maven2/com/google/guava/guava/23.0/guava-23.0.jar -P /spark/dist/jars/
RUN chmod 0644 /spark/dist/jars/guava-23.0.jar

FROM openjdk:8-jre-slim as build-spark-image
ARG spark_uid=185

RUN set -ex && \
  sed -i 's/http:\/\/deb.\(.*\)/https:\/\/deb.\1/g' /etc/apt/sources.list && \
  apt-get update && \
  ln -s /lib /lib64 && \
  apt install -y bash tini libc6 libpam-modules krb5-user libnss3 procps && \
  mkdir -p /opt/spark && \
  mkdir -p /opt/spark/examples && \
  mkdir -p /opt/spark/work-dir && \
  mkdir -p /opt/spark/conf && \
  touch /opt/spark/RELEASE && \
  rm /bin/sh && \
  ln -sv /bin/bash /bin/sh && \
  echo "auth required pam_wheel.so use_uid" >> /etc/pam.d/su && \
  chgrp root /etc/passwd && chmod ug+rw /etc/passwd && \
  rm -rf /var/cache/apt/*

COPY --from=build-spark /spark/dist/jars /opt/spark/jars
COPY --from=build-spark /spark/dist/bin /opt/spark/bin
COPY --from=build-spark /spark/dist/sbin /opt/spark/sbin
COPY --from=build-spark /spark/dist/kubernetes/dockerfiles/spark/entrypoint.sh /opt/
COPY --from=build-spark /spark/dist/kubernetes/dockerfiles/spark/decom.sh /opt/
COPY --from=build-spark /spark/dist/examples /opt/spark/examples
COPY --from=build-spark /spark/dist/kubernetes/tests /opt/spark/tests
COPY --from=build-spark /spark/dist/data /opt/spark/data

COPY ./conf/hive-site.xml /opt/spark/conf/hive-site.xml

ENV SPARK_HOME /opt/spark

WORKDIR /opt/spark/work-dir
RUN chmod g+w /opt/spark/work-dir
RUN chmod a+x /opt/decom.sh

USER 0

RUN mkdir $SPARK_HOME/python
RUN apt-get update && \
  apt install -y python3 python3-pip && \
  pip3 install --upgrade pip setuptools && \
  rm -r /root/.cache && rm -rf /var/cache/apt/*

COPY --from=build-spark /spark/dist/python/pyspark $SPARK_HOME/python/pyspark
COPY --from=build-spark /spark/dist/python/lib $SPARK_HOME/python/lib

ENV PATH "$PATH:$SPARK_HOME/bin"

WORKDIR /opt/spark/work-dir

ENTRYPOINT [ "/opt/entrypoint.sh" ]

ARG spark_uid=185
USER $spark_uid