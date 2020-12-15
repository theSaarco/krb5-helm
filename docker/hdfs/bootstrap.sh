#!/bin/bash

##########
# Identifying role
# Applicable roles are 'master', 'worker', 'pseudo'
# Default vaule is 'pseudo'

if [ -z "${1}" ]
then
	role='pseudo'
else
	role="${1}"
fi

##########
# Setting JAVA_HOME

if [ -z "${JAVA_HOME}" ];
then
	echo "JAVA_HOME is not set. Exiting..."
	exit 1
fi

##########
# Setting up Java and Hadoop profile

echo "
export JAVA_HOME=${JAVA_HOME}
export PATH=${PATH}:${JAVA_HOME}/bin:${HADOOP_HOME}/bin
export CLASSPATH=$(${HADOOP_HOME}/bin/hadoop classpath)
" >> /etc/profile

sed -i "s|^#\? \?export JAVA_HOME.*|export JAVA_HOME=${JAVA_HOME}|g" ${HADOOP_HOME}/etc/hadoop/hadoop-env.sh

##########
# Resource allocation

if [ -z "${MAX_CPU_PERC}" ];
then
        MAX_CPU_PERC=80
fi

if [ -z "${MAX_MEM_PERC}" ];
then
        MAX_MEM_PERC=80
fi

TOTAL_CPU=$(cat /proc/cpuinfo | grep "processor" | wc -l)
TOTAL_MEM=$(free --mega | grep Mem | awk '{ print $2 }')

MAX_CPU=$(echo "${MAX_CPU_PERC} * ${TOTAL_CPU} / 100" | bc)
MIN_CPU=1

MAX_MEM=$(echo "${MAX_MEM_PERC} * ${TOTAL_MEM} / 100 / 256 * 256" | bc)
MIN_MEM=$(echo "${MAX_MEM} / ${MAX_CPU} / 256 * 256" | bc)
if [ ${MIN_MEM} -eq 0 ];
then
        MIN_MEM=1024
fi

MAP_MEMORY=${MIN_MEM}
REDUCE_MEMORY=$(echo "${MAP_MEMORY} * 2" | bc)

MAP_JAVA_MEMORY=$(echo "${MAP_MEMORY} * 80 / 100 / 64 * 64" | bc)
REDUCE_JAVA_MEMORY=$(echo "${REDUCE_MEMORY} * 80 / 100 / 64 * 64" | bc)

BLOCK_SIZE=16777216
if [ ${TOTAL_MEM} -gt 16384 ];
then
	BLOCK_SIZE=268435456
fi

##########
# Setting up SSH keys

[ ! -f /etc/ssh/ssh_host_dsa_key ] && ssh-keygen -q -N "" -t dsa -f /etc/ssh/ssh_host_dsa_key
[ ! -f /etc/ssh/ssh_host_rsa_key ] && ssh-keygen -q -N "" -t rsa -f /etc/ssh/ssh_host_rsa_key
[ ! -f /root/.ssh/id_rsa ] && ssh-keygen -q -N "" -t rsa -f /root/.ssh/id_rsa

public_key=$(awk '{ print $2 }' /root/.ssh/id_rsa.pub)
grep "${public_key}" /root/.ssh/authorized_keys > /dev/null 2>&1
if [ $? -ne 0 ];
then
	cat /root/.ssh/id_rsa.pub >> /root/.ssh/authorized_keys
fi

##########
# Store the public key of master in Kubernetes secret store

# If this container is running inside Kubernetes, then create a Kubernetes secret
# for authorized keys, so that hadoop worker nodes can pull the public key(s) of
# of the hadoop masters and allow them to access the worker pods through SSH.

pull_authorized_keys () {
        KUBE_TOKEN=$(</var/run/secrets/kubernetes.io/serviceaccount/token)
        NAMESPACE=$(</var/run/secrets/kubernetes.io/serviceaccount/namespace)
        SECRET_NAME="authorized-keys"
        PUBLIC_KEY=$(cat /root/.ssh/id_rsa.pub)

	response=$(curl -s \
	  --cacert /run/secrets/kubernetes.io/serviceaccount/ca.crt \
	  -X GET \
	  -H "Authorization: Bearer $KUBE_TOKEN" \
	  -H 'Accept: application/json' \
	  -H 'Content-Type: application/json' \
	  https://$KUBERNETES_SERVICE_HOST:$KUBERNETES_PORT_443_TCP_PORT/api/v1/namespaces/$NAMESPACE/secrets/$SECRET_NAME 2>&1)

	keys=$(echo "${response}" | jq '.data.key' | sed 's/"//g')
	resourceVersion=$(echo "${response}" | jq '.metadata.resourceVersion' | sed 's/"//g')

	if [ "${keys}" != "null" ];
	then
		if [ "${resourceVersion}" != "${prevResourceVersion}" ];
		then
			authorized_keys=$(echo "${keys}" | base64 -d)
			echo "${authorized_keys}" > /root/.ssh/authorized_keys
			chmod 600 /root/.ssh/authorized_keys
			prevResourceVersion="${resourceVersion}"
		else
			echo "Authorized keys are up-to-date"
		fi
	fi
}

update_authorized_keys() {
        KUBE_TOKEN=$(</var/run/secrets/kubernetes.io/serviceaccount/token)
        NAMESPACE=$(</var/run/secrets/kubernetes.io/serviceaccount/namespace)
        SECRET_NAME="authorized-keys"
        PUBLIC_KEY=$(cat /root/.ssh/id_rsa.pub)

	response=$(curl -s \
	  --cacert /run/secrets/kubernetes.io/serviceaccount/ca.crt \
	  -X GET \
	  -H "Authorization: Bearer $KUBE_TOKEN" \
	  -H 'Accept: application/json' \
	  -H 'Content-Type: application/json' \
	  https://$KUBERNETES_SERVICE_HOST:$KUBERNETES_PORT_443_TCP_PORT/api/v1/namespaces/$NAMESPACE/secrets/$SECRET_NAME 2>&1)

	keys=$(echo "${response}" | jq '.data.key' | sed 's/"//g')
	resourceVersion=$(echo "${response}" | jq '.metadata.resourceVersion' | sed 's/"//g')
	if [ "${keys}" == "null" ];
	then
		authorized_keys=$(echo "${PUBLIC_KEY}" | base64 -w0)
		method="POST"
		content_type="application/json"
		url="https://$KUBERNETES_SERVICE_HOST:$KUBERNETES_PORT_443_TCP_PORT/api/v1/namespaces/$NAMESPACE/secrets"
	else
		tmp_keys=$(echo "${keys}" | base64 -d)
		authorized_keys=$(echo -e "${tmp_keys}\n${PUBLIC_KEY}\n" | base64 -w0)
		method="PATCH"
		content_type="application/strategic-merge-patch+json"
		url="https://$KUBERNETES_SERVICE_HOST:$KUBERNETES_PORT_443_TCP_PORT/api/v1/namespaces/$NAMESPACE/secrets/${SECRET_NAME}"
	fi

        response=$(curl -s \
          --cacert /run/secrets/kubernetes.io/serviceaccount/ca.crt \
          -X ${method} \
          -d "{\"apiVersion\":\"v1\",\"kind\":\"Secret\",\"metadata\":{\"name\":\"${SECRET_NAME}\",\"namespace\":\"${NAMESPACE}\"},\"type\":\"Opaque\",\"data\":{\"key\":\"${authorized_keys}\"}}" \
          -H "Authorization: Bearer $KUBE_TOKEN" \
          -H 'Accept: application/json' \
          -H "Content-Type: ${content_type}" \
	  ${url} 2>&1)

	resourceVersion=$(echo "${response}" | jq '.metadata.resourceVersion' | sed 's/"//g')
	if [ "${resourceVersion}" == "null" ];
	then
		echo "Could not update authorized keys"
	else
		echo "Successfully updated authorized keys"
	fi
}

if [ -f /var/run/secrets/kubernetes.io/serviceaccount/token ];
then
	environment="kubernetes"
	if [ "${role}" == "master" ];
	then
		update_authorized_keys
	elif [ "${role}" == "worker" ];
	then
		pull_authorized_keys
	fi
else
	echo "Kubernetes service token is missing"
	echo "Could not connect to Kubernetes"
fi

##########
# Setup SSH client configurations
echo "
Host *
  UserKnownHostsFile /dev/null
  StrictHostKeyChecking no
LogLevel quiet
" >> /root/.ssh/config

chmod 600 /root/.ssh/config
chown root:root /root/.ssh/config

##########
# Setup SSH server configurations

sed -i 's/#\?PermitRootLogin.*/PermitRootLogin yes/g' /etc/ssh/sshd_config

# Create /run/sshd directory to avoid sshd service issues in ubuntu containers.
mkdir /run/sshd
/usr/sbin/sshd -D & disown

##########
# Create data directories for Hadoop
mkdir -p /hdfs/data/dfs/dn
mkdir -p /hdfs/namenode/dfs/nn

# if [ "${role}" == "worker" ];
# then
#         default_fs="hadoop-master.hadoop-domain.default-tenant.svc.cluster.local"
#         resource_tracker_addr="hadoop-master.hadoop-domain.default-tenant.svc.cluster.local"
# 
#	if [ "${environment}" == "kubernetes" ];
#	then
#		namespace=$(</var/run/secrets/kubernetes.io/serviceaccount/namespace)
#		default_fs="hadoop-master.${namespace}.svc.cluster.local"
#		resource_tracker_addr="hadoop-master.${namespace}.svc.cluster.local"
#	else
#		default_fs="hadoop-master"
#		resource_tracker_addr="hadoop-master"
#	fi
# 
# else
# 	default_fs="0.0.0.0"
# 	resource_tracker_addr="0.0.0.0"
# fi

default_fs="hadoop-master.hadoop-domain.default-tenant.svc.cluster.local"
resource_tracker_addr="hadoop-master.hadoop-domain.default-tenant.svc.cluster.local"

##########
# Create Hadoop configuration files

echo "<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<?xml-stylesheet type=\"text/xsl\" href=\"configuration.xsl\"?>

<configuration>
    <property>
        <name>fs.defaultFS</name>
        <value>hdfs://${default_fs}:9000</value>
    </property>
    <property>
        <name>hadoop.security.authentication</name>
        <value>kerberos</value> 
    </property>
    <property>
        <name>hadoop.security.authorization</name>
        <value>true</value>
    </property>
</configuration>
" > ${HADOOP_HOME}/etc/hadoop/core-site.xml

echo "<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<?xml-stylesheet type=\"text/xsl\" href=\"configuration.xsl\"?>

<configuration>
    <property>
        <name>dfs.replication</name>
        <value>1</value>
    </property>
    <property>
        <name>dfs.datanode.data.dir</name>
	<value>/hdfs/data/dfs/dn</value>
    </property>
    <property>
        <name>dfs.namenode.name.dir</name>
        <value>/hdfs/namenode/dfs/nn</value>
    </property>
    <property>
        <name>dfs.namenode.datanode.registration.ip-hostname-check</name>
        <value>false</value>
    </property>
    <property>
	<name>dfs.blocksize</name>
	<value>${BLOCK_SIZE}</value>
    </property>

    <property>
        <name>dfs.namenode.kerberos.principal.pattern</name>
        <value>hdfs/*@EXAMPLE.COM</value>
    </property>

    <property>
        <name>dfs.http.policy</name>
        <value>HTTPS_ONLY</value>
    </property>
    <property>
        <name>dfs.data.transfer.protection</name>
        <value>authentication</value>
    </property>
    <property>
        <name>dfs.block.access.token.enable</name>
        <value>true</value>
    </property>

<!-- Primary namenode security config -->
    <property>
        <name>dfs.namenode.kerberos.principal</name>
        <value>hdfs/_HOST@EXAMPLE.COM</value>
    </property>
    <property>
        <name>dfs.namenode.keytab.file</name>
        <value>/etc/krb5.keytab</value>
    </property>
    <property>
        <name>dfs.namenode.kerberos.internal.spnego.principal</name>
        <value>HTTP/_HOST@EXAMPLE.COM</value>
    </property>

<!-- DataNode security config -->
    <property>
        <name>dfs.datanode.kerberos.principal</name>
        <value>hdfs/_HOST@EXAMPLE.COM</value>
    </property>
    <property>
        <name>dfs.datanode.keytab.file</name>
        <value>/etc/krb5.keytab</value>
    </property>
    <property>
        <name>dfs.datanode.address</name>
        <value>0.0.0.0:30004</value>
    </property>
    <property>
        <name>dfs.datanode.http.address</name>
        <value>0.0.0.0:30006</value>
    </property>

<!-- Web authentication config -->
    <property>
        <name>dfs.web.authentication.kerberos.principal</name>
        <value>hdfs/_HOST@EXAMPLE.COM</value>
    </property>
    <property>
        <name>dfs.web.authentication.kerberos.keytab</name>
        <value>/etc/krb5.keytab</value>
    </property>

<!-- Secondary NameNode security config -->
    <property>
        <name>dfs.secondary.namenode.kerberos.principal</name>
        <value>hdfs/_HOST@EXAMPLE.COM</value>
    </property>
    <property>
        <name>dfs.secondary.namenode.keytab.file</name>
        <value>/etc/krb5.keytab</value>
    </property>
    <property>
        <name>dfs.secondary.namenode.kerberos.internal.spnego.principal</name>
        <value>HTTP/_HOST@EXAMPLE.COM</value>
    </property>

</configuration>
" > ${HADOOP_HOME}/etc/hadoop/hdfs-site.xml

echo "<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<?xml-stylesheet type=\"text/xsl\" href=\"configuration.xsl\"?>

<configuration>
    <property>
        <name>mapreduce.framework.name</name>
        <value>yarn</value>
    </property>
    <property>
	<name>mapreduce.map.memory.mb</name>
	<value>${MAP_MEMORY}</value>
    </property>
    <property>
	<name>mapreduce.reduce.memory.mb</name>
	<value>${REDUCE_MEMORY}</value>
    </property>
    <property>
	<name>mapreduce.map.java.opts</name>
	<value>-Xmx${MAP_JAVA_MEMORY}m</value>
    </property>
    <property>
	<name>mapreduce.reduce.java.opts</name>
        <value>-Xmx${REDUCE_JAVA_MEMORY}m</value>
    </property>

    <property>
        <name>mapreduce.jobhistory.principal</name>
        <value>hdfs/_HOST@EXAMPLE.COM</value>
    </property>
    <property>
        <name>mapreduce.jobhistory.keytab</name>
        <value>/etc/krb5.keytab</value>
    </property>

</configuration>
" > ${HADOOP_HOME}/etc/hadoop/mapred-site.xml

echo "<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<?xml-stylesheet type=\"text/xsl\" href=\"configuration.xsl\"?>

<configuration>

    <property>
        <name>yarn.nodemanager.principal</name>
        <value>hdfs/_HOST@EXAMPLE.COM</value>
    </property>
    <property>
        <name>yarn.nodemanager.keytab</name>
        <value>/etc/krb5.keytab</value>
    </property>
    <property>
        <name>yarn.resourcemanager.principal</name>
        <value>hdfs/_HOST@EXAMPLE.COM</value>
    </property>
    <property>
        <name>yarn.resourcemanager.keytab</name>
        <value>/etc/krb5.keytab</value>
    </property>

    <property>
        <name>yarn.resourcemanager.resource-tracker.address</name>
        <value>${resource_tracker_addr}:8031</value>
    </property>
    <property>
        <name>yarn.nodemanager.resource.memory-mb</name>
        <value>${MAX_MEM}</value>
    </property>
    <property>
        <name>yarn.nodemanager.resource.cpu-vcores</name>
        <value>${MAX_CPU}</value>
    </property>
    <property>
	<name>yarn.scheduler.minimum-allocation-vcores</name>
	<value>${MIN_CPU}</value>
    </property><property>
	<name>yarn.scheduler.maximum-allocation-vcores</name>
	<value>${MAX_CPU}</value>
    </property>
    <property>
	<name>yarn.scheduler.minimum-allocation-mb</name>
	<value>${MIN_MEM}</value>
    </property>
    <property>
	<name>yarn.scheduler.maximum-allocation-mb</name>
	<value>${MAX_MEM}</value>
    </property>
    <property>
        <name>yarn.nodemanager.aux-services</name>
        <value>mapreduce_shuffle</value>
    </property>
    <property>
        <name>yarn.nodemanager.env-whitelist</name>
        <value>JAVA_HOME,HADOOP_COMMON_HOME,HADOOP_HDFS_HOME,HADOOP_CONF_DIR,CLASSPATH_PREPEND_DISTCACHE,HADOOP_YARN_HOME,HADOOP_MAPRED_HOME</value>
    </property>
    <property>
	<name>yarn.log-aggregation-enable</name>
	<value>true</value>
    </property>
    <property>
    	<description>Where to aggregate logs to.</description>
    	<name>yarn.nodemanager.remote-app-log-dir</name>
    	<value>/tmp/logs</value>
    </property>
    <property>
    	<name>yarn.log-aggregation.retain-seconds</name>
	<value>259200</value>
    </property>
    <property>
    	<name>yarn.log-aggregation.retain-check-interval-seconds</name>
    	<value>3600</value>
    </property>
    <property>
	<name>yarn.resourcemanager.scheduler.class</name>
	<value>org.apache.hadoop.yarn.server.resourcemanager.scheduler.fair.FairScheduler</value>
    </property>
    <property>
    	<name>yarn.scheduler.fair.allow-undeclared-pools</name>
	<value>false</value>
    </property>
    <property>
	<name>yarn.scheduler.fair.user-as-default-queue</name>
	<value>false</value>
    </property>
    <property>
    	<name>yarn.scheduler.fair.preemption</name>
    	<value>true</value>
    </property>
    <property>
    	<name>yarn.scheduler.fair.preemption.cluster-utilization-threshold</name>
    	<value>0.8</value>
    </property>
    <property>
	<name>yarn.scheduler.fair.allocation.file</name>
	<value>${HADOOP_CONF_DIR}/fair-scheduler.xml</value>
    </property>
    <property>
	<name>yarn.nodemanager.vmem-pmem-ratio</name>
	<value>4</value>
    </property>
</configuration>
" > ${HADOOP_HOME}/etc/hadoop/yarn-site.xml

echo "
<allocations>
    <queue name=\"root\">
        <weight>1.0</weight>
        <schedulingPolicy>drf</schedulingPolicy>
        <aclSubmitApps> </aclSubmitApps>
        <aclAdministerApps>*</aclAdministerApps>
        <queue name=\"production\">
            <weight>4.0</weight>
            <schedulingPolicy>drf</schedulingPolicy>
            <aclSubmitApps>*</aclSubmitApps>
            <aclAdministerApps>*</aclAdministerApps>
        </queue>
        <queue name=\"testing\">
            <weight>1.0</weight>
            <schedulingPolicy>drf</schedulingPolicy>
            <aclSubmitApps>*</aclSubmitApps>
            <aclAdministerApps>*</aclAdministerApps>
        </queue>
    </queue>
    <defaultQueueSchedulingPolicy>drf</defaultQueueSchedulingPolicy>
    <queuePlacementPolicy>
	<rule name=\"specified\"/>
	<rule name=\"default\" queue=\"production\" />
    </queuePlacementPolicy>
</allocations>
" > ${HADOOP_CONF_DIR}/fair-scheduler.xml

##########
# Start Hadoop services

if [ "${role}" == "pseudo" ];
then

	if ! [ -f /hdfs/namenode/dfs/nn/in_use.lock ];
	then
		${HADOOP_HOME}/bin/hdfs namenode -format
		namenode_formated="true"
	fi

	${HADOOP_HOME}/sbin/start-dfs.sh
	${HADOOP_HOME}/sbin/start-yarn.sh
	${HADOOP_HOME}/sbin/mr-jobhistory-daemon.sh start historyserver

	if [[ "${namenode_formated}" == "true" ]];
	then
		sleep 30
		${HADOOP_HOME}/bin/hadoop fs -mkdir /user/
		${HADOOP_HOME}/bin/hadoop fs -mkdir /user/root
		${HADOOP_HOME}/bin/hadoop fs -chmod 755 /tmp
	else
		${HADOOP_HOME}/bin/hadoop dfsadmin -safemode leave
	fi
elif [ "${role}" == "master" ];
then

	if ! [ -f /hdfs/namenode/dfs/nn/in_use.lock ];
	then
		${HADOOP_HOME}/bin/hdfs namenode -format
		namenode_formated="true"
	fi
	
	${HADOOP_HOME}/sbin/hadoop-daemon.sh start namenode
	${HADOOP_HOME}/sbin/hadoop-daemon.sh start secondarynamenode
        ${HADOOP_HOME}/sbin/yarn-daemon.sh start resourcemanager
	${HADOOP_HOME}/sbin/mr-jobhistory-daemon.sh start historyserver

	if [[ "${namenode_formated}" == "true" ]];
	then
		sleep 30
		${HADOOP_HOME}/bin/hadoop fs -mkdir /user/
		${HADOOP_HOME}/bin/hadoop fs -mkdir /user/root
		${HADOOP_HOME}/bin/hadoop fs -chmod 755 /tmp
	else
		${HADOOP_HOME}/bin/hadoop dfsadmin -safemode leave
	fi
elif [ "${role}" == "worker" ];
then
	${HADOOP_HOME}/sbin/hadoop-daemon.sh start datanode
	${HADOOP_HOME}/sbin/yarn-daemon.sh start nodemanager

fi

while true; 
do 
	if [ "${environment}" == "kubernetes" ];
	then
		pull_authorized_keys
	fi
	sleep 1000; 
done

