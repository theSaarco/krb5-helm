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
nerdctl build --platform linux/amd64 -t krb5-server:0.0.1 .
```

## List the Imgage

```
nerdctl image ls
REPOSITORY     TAG      IMAGE ID        CREATED           PLATFORM       SIZE         BLOB SIZE
krb5-server    0.0.1    a57a1f66945d    28 seconds ago    linux/amd64    431.0 MiB    143.9 MiB
```

## Tag the Image

```
nerdctl tag krb5-server:0.0.1 hachikoapp/krb5-server:0.0.1
nerdctl tag krb5-server:0.0.1 hachikoapp/krb5-server:latest
```

## Push the Image

```
nerdctl push hachikoapp/krb5-server:0.0.1
nerdctl push hachikoapp/krb5-server:latest
```
