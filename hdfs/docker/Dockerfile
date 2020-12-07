# FROM ubuntu
FROM openjdk:8-jdk

ARG HADOOP_VERSION=3.1.2

USER root

RUN apt-get -y update

RUN apt-get install -y curl tar sudo openssh-server rsync hostname net-tools findutils less lsof vim bc jq

RUN mkdir /tmp/hadoop && \
    curl -s https://archive.apache.org/dist/hadoop/common/hadoop-${HADOOP_VERSION}/hadoop-${HADOOP_VERSION}.tar.gz | \
    tar -xz -C /tmp/hadoop --exclude='share/doc' && \
    mv -v /tmp/hadoop/hadoop-${HADOOP_VERSION} /usr/local/hadoop-${HADOOP_VERSION} && \
    cd /usr/local && ln -s ./hadoop-${HADOOP_VERSION} hadoop

ENV HDFS_NAMENODE_USER=root
ENV HDFS_DATANODE_USER=root
ENV HDFS_SECONDARYNAMENODE_USER=root
ENV YARN_RESOURCEMANAGER_USER=root
ENV YARN_NODEMANAGER_USER=root
ENV HADOOP_HOME=/usr/local/hadoop
ENV HADOOP_COMMON_HOME=/usr/local/hadoop
ENV HADOOP_HDFS_HOME=/usr/local/hadoop
ENV HADOOP_MAPRED_HOME=/usr/local/hadoop
ENV HADOOP_YARN_HOME=/usr/local/hadoop
ENV HADOOP_CONF_DIR=/usr/local/hadoop/etc/hadoop
ENV YARN_CONF_DIR=/usr/local/hadoop/etc/hadoop

EXPOSE 8030/tcp 8031/tcp 8032/tcp 8033/tcp 8040/tcp 8042/tcp 8088/tcp

EXPOSE 2122/tcp 49707/tcp

EXPOSE 19888/tcp

EXPOSE 50010/tcp 50020/tcp 50070/tcp 50075/tcp 50090/tcp

COPY bootstrap.sh /usr/local/hadoop/sbin/bootstrap.sh

RUN chmod 755 /usr/local/hadoop/sbin/bootstrap.sh

ENTRYPOINT ["/usr/local/hadoop/sbin/bootstrap.sh"]
