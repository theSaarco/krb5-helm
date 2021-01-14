# Deployment steps for customer environments

**Pre-requisite:** Spark service is deployed, running Spark >=3.0.0.

## Deploy Jupyter

when deploying Jupyter service, make sure to:

1. Add Spark support as part of the deployment, pick the Spark service. We are not going to use this spark service, but this option adds configurations to Jupyter that we'll need for k8s mode as well. Besides, if the user wants to work with the stand-alone Spark service, he can do it.
2. Add environment variables. The following environment vars should be added:

    ```bash
    KRB5CCNAME = FILE:/User/conf/kerberos/krb5_ccache
    HADOOP_CONF_DIR = /User/conf/hadoop
    KRB5_CONFIG = /User/conf/kerberos/krb5.conf
    ```

    Make sure to write them exactly as they're shown here. No need for any modifications in them.

## Create /User file heirarchy

Created filesystem heirarchy with the configuration files:

```bash
User/conf/hadoop:
    core-site.xml
    hdfs-site.xml

User/conf/kerberos:
    krb5.conf
    krb5.keytab
    krb5_ccache

User/conf/spark:
    worker_pod.yaml
```

It's ok to not have those files available at first delpoyment, as we need the customer to provide them (they are his Kerberos and Hadoop configurations), but the directory structure should be there, and the customer should be instructed to place the files in the correct locations, and use the exact names.

## Place `krb5.conf` in `/etc`

>**Note:** The `krb5.conf` file is a configuration file that should be <
provided by the customer. If we can have it available at deployment, then this step can be done then. Else, need to escort the customer on first usage.

Copy `krb5.conf` also to `/etc/krb5.conf` on Jupyter (currently it's the only location that it will accept). Unfortunately, this needs to be done as root, so from the node ssh do this:

```bash
JUPYTER_CONTAINER_ID=`docker ps|grep jupyter|grep bash|awk '{print $1}'`
docker exec -it -u root $JUPYTER_CONTAINER_ID cp /User/conf/kerberos/krb5.conf /etc/krb5.conf
```

## Create Spark executor image

Need to have the Spark distribution we are using in Jupyter, and from it generate the spark Docker images, using the command:

```bash
cd <spark root dir>
./bin/docker-image-tool.sh -r spark-exec -t latest -u 1000 -p kubernetes/dockerfiles/spark/bindings/python/Dockerfile build
```

Ensure both images (basic and python) were created:

```bash
$ docker images | grep spark-exec
spark-exec/spark-py                                                                                                               latest                                  f059bac69989        13 seconds ago       992MB
spark-exec/spark                                                                                                                  latest                                  22f1da7cc733        About a minute ago   522MB
```

## Pod template yaml file

Use this [yaml file](./worker_pod.yaml).

v3io_auth is reusing a k8s secret that Jupyter uses, so you need to ensure that the `jupyter-v3io-auth` secret exists (and if your Jupyter service and hence the secret is named differently, then you need to modify the template accordingly):

```yaml
  volumes:
  - name: v3io-auth
    secret:
      defaultMode: 420
      secretName: jupyter-v3io-auth
```

Also, it sets `IGZ_DATA_CONFIG_FILE` to point at `/User/conf/spark/v3io.conf`, so we need to place the file there. On shell service or Jupyter service, perform:

```bash
cp $IGZ_DATA_CONFIG_FILE /User/conf/spark/
```

## Modify `spark-defaults.conf` file

Start with the existing file (in `/spark/conf/spark-defaults.conf`) - it should be there if the Jupyter service was created with Spark support.

Add the following lines to the file:

```bash
# Configurations that are specific to HDFS/Kerberos with Spark k8s mode.

spark.hadoop.fs.v3io.impl=io.iguaz.v3io.hcfs.V3IOFileSystem
spark.hadoop.fs.AbstractFileSystem.v3io.impl=io.iguaz.v3io.hcfs.V3IOAbstractFileSystem
spark.kubernetes.container.image=spark-exec/spark-py:latest
spark.kubernetes.namespace=default-tenant
spark.pyspark.python=python3.7
spark.kubernetes.executor.podTemplateFile=/User/conf/spark/worker_pod.yaml
spark.executorEnv.HADOOP_CONF_DIR=/User/conf/hadoop
spark.kerberos.keytab=/User/conf/kerberos/krb5.keytab
```

As there's nothing specific in these lines, you can copy them as-is. No need for any modifications.

## Verify Kerberos init works

From Jupyter shell, execute the following lines:

```bash
kinit -k -t /User/conf/kerberos/krb5.keytab <user-principal>@<realm>
klist
```

If it works, then we can indeed authenticate with Kerberos using the provided keytab and the needed principal.
The same lines can be executed from a notebook, just prefix them with `!`.

## Spark configuration needed by the user

As most of the parameters are pre-configured at this stage, the user needs to do very little configuration in the actual Python notebook. Specifically the line to create a `SparkSession` should be something like:

```python
spark = SparkSession.builder.appName('<app name>') \
    .master('k8s://https://kubernetes.default.svc:443') \
    .config('spark.kerberos.principal','<principal name>') \
    .getOrCreate()
```

See the [notebook](./spark-k8s.ipynb) for a working example.

# Open issues / questions

## No `py4j` on Jupyter

Jupyter refuses to import `pyspark.sql` - brings out error:

```python
---------------------------------------------------------------------------
ModuleNotFoundError                       Traceback (most recent call last)
<ipython-input-6-384785b29356> in <module>
----> 1 from pyspark.sql import SparkSession
      2 import socket
      3 
      4 hostname = socket.gethostname()
      5 

/spark/python/pyspark/__init__.py in <module>
     49 
     50 from pyspark.conf import SparkConf
---> 51 from pyspark.context import SparkContext
     52 from pyspark.rdd import RDD, RDDBarrier
     53 from pyspark.files import SparkFiles

/spark/python/pyspark/context.py in <module>
     25 from tempfile import NamedTemporaryFile
     26 
---> 27 from py4j.protocol import Py4JError
     28 from py4j.java_gateway import is_instance_of
     29 

ModuleNotFoundError: No module named 'py4j'
```

This was solved by:

```!pip install py4j==0.10.9```

Maybe we want to pre-install it on Jupyter?

## My `core-site.xml` file missing `auth_to_local`

I had to add the following section to `core-site.xml`, or else it doesn't know what to do with the principal I'm using. In a well-configured customer environment I assume this won't be an issue, so just logging this in case someone runs into similar issues:

```xml
    <property>
        <name>hadoop.security.auth_to_local</name>
        <value>
            RULE:[2:$1](^hdfs$)s/^.*$/hdfs/g
            DEFAULT
        </value>
    </property>
```

This makes every principal `hdfs/<something>@<realm>` become local user `hdfs`. It can of course be further generalized, but for my example it was enough, and like mentioned - customers should have their configurations already done properly so I don't expect issues there.