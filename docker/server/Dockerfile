FROM centos:7.5.1804

ARG dict_version=2.9.0-11.el7
ARG expect_version=5.45-14.el7_1
ARG krb5_version=1.15.1-19.el7

RUN yum -y --setopt=tsflags=nodocs update \
    && yum -y --setopt=tsflags=nodocs install \
        cracklib-dicts-${dict_version} \
        expect-${expect_version} \
        krb5-libs \
        krb5-pkinit \
        krb5-server \
        krb5-server-ldap \
    && yum clean all \
    && yum -y install \
        krb5-workstation \
        pam_krb5 \
        openssh-server \
        openssh-clients \
        less \
    && yum clean all

COPY init_db.sh /init_db
RUN chmod a+x /init_db \
    && /usr/bin/ssh-keygen -A \
    && useradd iguazio \
    && useradd krbtest
