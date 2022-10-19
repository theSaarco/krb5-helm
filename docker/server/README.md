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
