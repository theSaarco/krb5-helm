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
cd docker/server/
nerdctl build --platform linux/amd64 -t kuberos:0.0.1 .
```

## List the Imgage

```
nerdctl image ls
REPOSITORY                TAG       IMAGE ID        CREATED               PLATFORM       SIZE         BLOB SIZE
kuberos                   0.0.1     a57a1f66945d    About a minute ago    linux/amd64    431.0 MiB    143.9 MiB
```

## Tag the Image

```
nerdctl tag kuberos:0.0.1 hachikoapp/kuberos:0.0.1
nerdctl tag kuberos:0.0.1 hachikoapp/kuberos:latest
```

## Push the Image

```
nerdctl push hachikoapp/kuberos:0.0.1
nerdctl push hachikoapp/kuberos:latest
```
