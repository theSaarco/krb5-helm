# Helm chart for deploying Hadoop with Kerberos auth

Once you have successfully deployed the Kerberos server, you can now deploy a Hadoop cluster that uses it for authentication. This folder contains the Helm chart needed for that. To deploy, follow these instructions.

## Create Kerberos principals

Before installing the Hadoop cluster, you need to create Kerberos principals that the cluster will use for authentication. In our Hadoop implementation there are two nodes (`hadoop-master` and `hadoop-worker`) and we're using 2 user entities in these servers - `hdfs` and `HTTP`. To generate the principals you need to login to the `kadmin` container and perform the following commands in `kadmin.local`:

```bash
addprinc -pw <password> hdfs/hadoop-master.hadoop-domain.default-tenant.svc.cluster.local@EXAMPLE.COM
addprinc -pw <password> HTTP/hadoop-master.hadoop-domain.default-tenant.svc.cluster.local@EXAMPLE.COM
addprinc -pw <password> hdfs/hadoop-worker.hadoop-domain.default-tenant.svc.cluster.local@EXAMPLE.COM
addprinc -pw <password> HTTP/hadoop-worker.hadoop-domain.default-tenant.svc.cluster.local@EXAMPLE.COM
addprinc -pw <password> hdfs/hadoop-master@EXAMPLE.COM
addprinc -pw <password> hdfs/hadoop-worker@EXAMPLE.COM
addprinc -pw <password> HTTP/hadoop-master@EXAMPLE.COM
addprinc -pw <password> HTTP/hadoop-worker@EXAMPLE.COM

ktadd -k /etc/hdfs.keytab hdfs/hadoop-master.hadoop-domain.default-tenant.svc.cluster.local@EXAMPLE.COM HTTP/hadoop-master.hadoop-domain.default-tenant.svc.cluster.local@EXAMPLE.COM ... # Add all 8 principals here
```

> To be honest - some of these may be redundant, specifically the principals with the short host name. It might be nice to validate this claim at some future point.

Once this is done, exit the `kadmin` container and run the script which generates k8s secrets from keytabs:

```bash
source generate_keytab_secret
```

## Deploy Hadoop cluster

Generally speaking, the Helm chart provided has everything configured so that you should be able to run it out-of-the-box. The main thing that might break stuff is if you're deploying to a different k8s namespace than `default-tenant` since a lot of things assume that this is the namespace - mostly because it translates to host FQDNs in k8s. For example, the Kerberos principals created above all assume `default-tenant` is the namespace. This is good enough for PoC, so let's leave it at that.
The next step is to go and build the Hadoop container image. Do the following:

```bash
cd ../docker/hdfs
docker build -f Dockerfile -t hadoop:latest ./
```

> As always, this needs to run on the app-node.

Once the docker image is ready, deploy the Helm chart (from the data-node, of course):

```bash
helm -n default-tenant install hdfs-krb ./
```

Once this is done, you should have a Hadoop cluster up and running. To verify, first check that the pods are there:

```bash
$ kubectl -n default-tenant get pods -l name=hadoop
NAME            READY   STATUS    RESTARTS   AGE
hadoop-master   1/1     Running   0          33m
hadoop-worker   1/1     Running   0          33m
```

Now you can connect to either the master node or the worker node, and perform a basic HDFS command:

```bash
$ kubectl -n default-tenant exec -it hadoop-master -- /bin/bash
[container]$ /usr/local/hadoop/bin/hdfs dfs -ls /
Found 2 items
drwxr-xr-x   - hdfs supergroup          0 2020-12-15 09:56 /tmp
drwxr-xr-x   - hdfs supergroup          0 2020-12-15 09:57 /user
```

If this doesn't work, well - you're into a world of pain. Some suggestions:

1. Verify that Kerberos `kinit` was performed (using `klist`)
2. Verify that the environment variable `$KRB5CCNAME` is set and points at the Kerberos cache file. Without this piece of junk, no client operation will succeed
3. Make sure the various Hadoop configuration files are correct - the important ones are `core-site.xml` and `hdfs-site.xml`, but there are multiple others... The Hadoop configurations can all be found in `/usr/local/hadoop/etc/hadoop`
4. To debug you can also run the `hdfs` command with a higher `loglevel`:

```bash
/usr/local/hadoop/bin/hdfs --loglevel debug dfs -ls /
```

5. Try to run the `kdiag` option of the `hadoop` command, which prints a lot of useless information, but sometimes contains gems that can help. Specifically take a look at env variables that are defined and the various configurations that Hadoop thinks it has:

```bash
/usr/local/hadoop/bin/hadoop kdiag
```

6. Make sure the various Hadoop processes are running by executing `jps`. This should look pretty much like this:

```bash
# Master node
$ jps 
241 SecondaryNameNode
1347 Jps
422 JobHistoryServer
344 ResourceManager
173 NameNode

# Worker node
$ jps
465 Jps
211 NodeManager
123 DataNode
```

And, most importantly - pray. A lot. It does not help, but that's all you can do at this point.