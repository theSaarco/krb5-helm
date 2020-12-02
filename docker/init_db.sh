#!/usr/bin/expect -f

set realm [lindex $argv 0]
set master_password [lindex $argv 1]

set timeout -1

if {![ file exists /var/lib/krb5kdc/principal]} {
    set timeout -1

    spawn /usr/sbin/kdb5_util -r "${realm}" create -s

    expect "Enter KDC database master key:"
    send -- "${master_password}\r"

    expect "Re-enter KDC database master key to verify:"
    send -- "${master_password}\r"

    expect eof
} else {
    exit 0
}
