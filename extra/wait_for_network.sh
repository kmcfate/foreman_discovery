#!/bin/sh
n=1
server=""

until [ "$server" != "" ]; do
    server=$(route -n|grep ^0.0.0.0|awk '{print $2}')
done

echo "Testing ping to $server to see if network is up..."

until ping -w 1 -c 1 "$server" &>/dev/null ;do
    sleep 1
    n=$(( n+1 ))
    [ $n -eq 180 ] && break
done

