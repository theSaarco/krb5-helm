# Kerberos Server Image

I am using Rancher Desktop as a local environment.

## Docker Hub Authentication

```
nerdctl login -u hachikoapp
Enter Password: ENTER_TOKEN
Login Succeeded
```

## Build the Image

```
cd docker/sidecar/
nerdctl build --platform linux/amd64 -t krb_sidecar:0.0.1 .
```

## List the Imgage

```
nerdctl image ls
REPOSITORY                TAG       IMAGE ID        CREATED               PLATFORM       SIZE         BLOB SIZE
kuberos                   0.0.1     a57a1f66945d    About a minute ago    linux/amd64    431.0 MiB    143.9 MiB
krb_sidecar               0.0.1     4e9c74c25af6    27 seconds ago    linux/amd64    391.7 MiB    134.9 MiB
```

## Tag the Image

```
nerdctl tag krb_sidecar:0.0.1 hachikoapp/krb_sidecar:0.0.1
nerdctl tag krb_sidecar:0.0.1 hachikoapp/krb_sidecar:latest
```

## Push the Image

```
nerdctl push hachikoapp/krb_sidecar:0.0.1
nerdctl push hachikoapp/krb_sidecar:latest
```
