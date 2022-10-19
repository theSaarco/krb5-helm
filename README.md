# Helm chart for deploying Kerberos (and some clients)

This repository contains the following parts:

1. [Docker files](./docker) and scripts needed to create docker containers with kerberos components in them (and some other stuff) - there are 2 containers created: a basic Kubernetes-supporting container, and the sidecar needed for client containers
2. [Kerberos server Helm chart](./kuberos) - which deploys a pod with two containers: `kdc` and `kadmin`
   - This is based on the work in <https://github.com/jeffgrunewald/kuberos>
3. [Kerberos client Helm chart](./krb-client) - this deploys a pod with two containers:
   - A basic container that does nothing (but has the Kerberos needed configurations in it)
   - A sidecar that is responsible for running `kinit` periodically, and obtaining Kerberos `TGT` for initial access. It stores the tickets in a memory-mapped volume that is accessible by the 1st container, thus allowing it to transparently authenticate with Kerberos.  
   - This is based on the work in <https://github.com/edseymour/kinit-sidecar>

## Deploying Kerberos server

This section assumes that you're deploying on an Iguazio system, but it should work the same for any k8s cluster that you may have lying around. The main point about deploying on Iguazio is that the Docker container needs to be created on the `app cluster`, but the Helm charts are installed from the `data cluster`. Other than that, there should be no issue.
The steps are as follows (assuming you are starting from the root directory, right here):

1. Create the server Docker image. Run the following command on the `app cluster`

    ```bash
    cd docker/server
    docker build -f Dockerfile -t kuberos:latest ./
    ```

    (You can use a different container tag, but then you need to modify the information in the `values.yaml` file accordingly)
2. Go the the `kuberos` Helm chart directory, and examine the values in `values.yaml`. By default you don't need to change anything. Some things you may want to change:
   - If you tagged the container differently, then you need to change the `containers.image` and `containers.tag` values to the correct tag you selected
   - If you're feeling brave, you can have the Kerberos DB stored in a PVC, to do that you need to modify the values in `kdc.persistence`. I haven't really checked it yet
3. Once you're satisfied, deploy the Helm chart:

    ```bash
    cd kuberos
    helm -n default-tenant install kuberos ./
    ```

    Assuming this worked, you should get a nice message explaining a lot of stuff. At this point you can check that the pods were created:

    ```bash
    $ kubectl -n default-tenant get pods
    NAME                                              READY   STATUS    RESTARTS   AGE
    kuberos-kuberos-kdc-0                             2/2     Running   0          52s
    ```

    (Of course, other containers will be there...)
4. Login to the `kadmin` container to configure stuff:

    ```bash
    kubectl -n default-tenant exec -ti kuberos-kuberos-kdc-0 --container kadmin -- /bin/bash
    ```

    Now, run `kadmin.local` and perform the following commands (it's an interactive shell):

    ```bash
    [root@kuberos-kuberos-kdc-0 bin]# kadmin.local
    Authenticating as principal root/admin@GODEVELOPER.NET with password.
    addprinc -pw testpasswd iguazio
    WARNING: no policy specified for iguazio@GODEVELOPER.NET; defaulting to no policy
    Principal "iguazio@GODEVELOPER.NET" created.
    kadmin.local:
    kadmin.local:  addprinc -pw testpasswd krbtest
    WARNING: no policy specified for krbtest@GODEVELOPER.NET; defaulting to no policy
    Principal "krbtest@GODEVELOPER.NET" created.
    kadmin.local:
    kadmin.local: addprinc -randkey host/kuberos-kuberos-kdc-0.kuberos-kuberos-kdc.kerberos.svc.cluster.local
    WARNING: no policy specified for host/kuberos-kuberos-kdc-0.kuberos-kuberos-kdc.kerberos.svc.cluster.local@GODEVELOPER.NET; defaulting to no policy
    Principal "host/kuberos-kuberos-kdc-0.kuberos-kuberos-kdc.kerberos.svc.cluster.local@GODEVELOPER.NET" created.
    kadmin.local: ktadd iguazio host/kuberos-kuberos-kdc-0.kuberos-kuberos-kdc.kerberos.svc.cluster.local
    Entry for principal iguazio with kvno 2, encryption type aes256-cts-hmac-sha1-96 added to keytab FILE:/etc/krb5.keytab.
    Entry for principal iguazio with kvno 2, encryption type aes128-cts-hmac-sha1-96 added to keytab FILE:/etc/krb5.keytab.
    Entry for principal host/kuberos-kuberos-kdc-0.kuberos-kuberos-kdc.kerberos.svc.cluster.local with kvno 2, encryption type aes256-cts-hmac-sha1-96 added to keytab FILE:/etc/krb5.keytab.
    Entry for principal host/kuberos-kuberos-kdc-0.kuberos-kuberos-kdc.kerberos.svc.cluster.local with kvno 2, encryption type aes128-cts-hmac-sha1-96 added to keytab FILE:/etc/krb5.keytab.
    kadmin.local:
    kadmin.local:  exit
    ```

    List Principals

    ```bash
    kadmin.local:  list_principals
    K/M@GODEVELOPER.NET
    host/kuberos-kuberos-kdc-0.kuberos-kuberos-kdc.kerberos.svc.cluster.local@GODEVELOPER.NET
    iguazio@GODEVELOPER.NET
    kadmin/admin@GODEVELOPER.NET
    kadmin/changepw@GODEVELOPER.NET
    kadmin/kuberos-kuberos-kdc-0.kuberos-kuberos-kdc.kerberos.svc.cluster.local@GODEVELOPER.NET
    kiprop/kuberos-kuberos-kdc-0.kuberos-kuberos-kdc.kerberos.svc.cluster.local@GODEVELOPER.NET
    krbtest@GODEVELOPER.NET
    krbtgt/GODEVELOPER.NET@GODEVELOPER.NET
    kadmin.local:  exit
    ```

    What these commands do is create 3 principals - 2 users (`iguazio` and `krbtest`), and a single host which corresponds to the server pod (assuming you didn't change the pod's name by messing around with the Helm parameters). Then it uses `ktadd` to save passwords for the `iguazio` user and the server host to the `/etc/krb5.keytab` file - this file will be used to authenticate without password later
5. Create another keytab called `/etc/hdfs.keytab` - for now you can just copy the `krb5.keytab` file - it's needed because the `generate_keytab_secret` expects this to also exist (it is used later for HDFS configuration)
6. Save the `krb5.keytab` file to a k8s secret (will be consumed by the client pod):

    ```bash
    source generate_keytab_secret
    ```

    This will save the keytab to a local file and generate a k8s secret from it, called `secret/krb5-keytab`

    Test Persistence

    ```bash
    kubectl get statefulset -n kerberos
    NAME                  READY   AGE
    kuberos-kuberos-kdc   1/1     22m
    ```

    ```bash
    kubectl get pods -n kerberos
    NAME                    READY   STATUS    RESTARTS   AGE
    kuberos-kuberos-kdc-0   2/2     Running   0          2m5s

    kubectl delete pod kuberos-kuberos-kdc-0 -n kerberos
    pod "kuberos-kuberos-kdc-0" deleted

    kubectl get pods -n kerberos
    NAME                    READY   STATUS            RESTARTS   AGE
    kuberos-kuberos-kdc-0   0/2     PodInitializing   0          12s

    kubectl get pods -n kerberos
    NAME                    READY   STATUS    RESTARTS   AGE
    kuberos-kuberos-kdc-0   2/2     Running   0          24s
    ```

    ```bash
    kubectl -n kerberos exec -ti kuberos-kuberos-kdc-0 --container kadmin -- /bin/bash
    [root@kuberos-kuberos-kdc-0 /]# kadmin.local
    Authenticating as principal root/admin@GODEVELOPER.NET with password.
    kadmin.local:  list_principals
    K/M@GODEVELOPER.NET
    host/kuberos-kuberos-kdc-0.kuberos-kuberos-kdc.kerberos.svc.cluster.local@GODEVELOPER.NET
    iguazio@GODEVELOPER.NET
    kadmin/admin@GODEVELOPER.NET
    kadmin/changepw@GODEVELOPER.NET
    kadmin/kuberos-kuberos-kdc-0.kuberos-kuberos-kdc.kerberos.svc.cluster.local@GODEVELOPER.NET
    kiprop/kuberos-kuberos-kdc-0.kuberos-kuberos-kdc.kerberos.svc.cluster.local@GODEVELOPER.NET
    krbtest@GODEVELOPER.NET
    krbtgt/GODEVELOPER.NET@GODEVELOPER.NET
    kadmin.local:
    ```

## Deploying a client

Now that you have a server running, you need to deploy a client pod that will make proper use of it. The steps to do that are as follows:

1. Create the sidecar Docker image (must be run on the `app-server`):

    ```bash
    cd docker/sidecar
    docker build -f Dockerfile -t krb_sidecar:latest ./
    ```

2. Go to the `krb-client` directory, and examine the values in the `values.yaml` file. Again, you shouldn't need to touch anything unless you modified things in the Docker creation or anything else
3. Deploy the `krb-client` Helm chart:

    ```bash
    helm -n default-tenant install krb-client ./
    ```

    This should generate a pod with 2 containers in it (client and sidecar)
    > Important: you must perform this operation after creating the k8s secret (in step 5 of server deployment), otherwise the keytab will not be mounted to the client and Kerberos authentication will fail
4. To verify that the sidecar is able to initiate work with Kerberos, look at its logs:

    ```bash
    $ kubectl -n default-tenant logs -f krb-client-krb-client-client -c sidecar
    *** kinit at +2020-12-02
    Using default cache: /tmp/ccache/krb5kdc_ccache
    Using principal: iguazio@EXAMPLE.COM
    Authenticated to Kerberos v5
    Ticket cache: FILE:/tmp/ccache/krb5kdc_ccache
    Default principal: iguazio@EXAMPLE.COM

    Valid starting     Expires            Service principal
    12/02/20 13:29:57  12/03/20 13:29:56  krbtgt/EXAMPLE.COM@EXAMPLE.COM
    *** Waiting for 3600 seconds
    ```

    If a ticket is displayed (to `krbtgt/EXAMPLE.COM@EXAMPLE.COM`), then authentication was successful and you're good to go

## Test Kerberos authentication

Now the last step is to verify Kerberos works. We verify it by doing `ssh` to the `kadmin` container, using user `iguazio` whose password we saved to the `keytab` file.
The steps are:

1. Login to the `krbclient` container in the client pod

    ```bash
    kubectl -n default-tenant exec -ti krb-client-krb-client-client -c krbclient -- /bin/bash
    ```

2. Verify that the sidecar indeed was able to share the ticket cache properly with this container:

    ```bash
    $ klist
    Ticket cache: FILE:/tmp/ccache/krb5kdc_ccache
    Default principal: iguazio@EXAMPLE.COM

    Valid starting     Expires            Service principal
    12/02/20 13:29:57  12/03/20 13:29:56  krbtgt/EXAMPLE.COM@EXAMPLE.COM
    ```

3. Perform `ssh` to the server:

    ```bash
    ssh iguazio@kuberos-kuberos-kdc-0.kuberos-kuberos-kdc.default-tenant.svc.cluster.local
    ```

    This should work without you specifying any password - if you need password, then something went totally wrong. To compare, try to login as user `krbtest`, which is a Kerberos principal but one whose password is not in the `keytab`:

    ```bash
    $ ssh krbtest@kuberos-kuberos-kdc-0.kuberos-kuberos-kdc.default-tenant.svc.cluster.local
    krbtest@kuberos-kuberos-kdc-0.kuberos-kuberos-kdc.default-tenant.svc.cluster.local's password:
    ```

    It will ask for a password, which is expected.
4. If you now exit the `ssh` connection, and look at the Kerberos tickets on the client side, you'll see a new ticket for the server host besides the `TGT` that was there earlier:

    ```bash
    $ klist
    Ticket cache: FILE:/tmp/ccache/krb5kdc_ccache
    Default principal: iguazio@EXAMPLE.COM

    Valid starting     Expires            Service principal
    12/02/20 13:29:57  12/03/20 13:29:56  krbtgt/EXAMPLE.COM@EXAMPLE.COM
    12/02/20 13:35:16  12/03/20 13:29:56  host/kuberos-kuberos-kdc-0.kuberos-kuberos-kdc.default-tenant.svc.cluster.local@EXAMPLE.COM
    ```

That's it! We have Kerberos working now. Much rejoice.
