# nginx-anti-ddos
A simple cron script to mitigate ddos attacks

## The idea
is to monitor access_log for IPs doing too many requests, maintain deny_ip list and apply it if needed.

## nginx "specs"
- [How powerful your nginx server is](https://www.nginx.com/blog/testing-the-performance-of-nginx-and-nginx-plus-web-servers/)

- How fast can you restart nginx:
```
$ time service nginx restart
real	0m0.113s
user	0m0.011s
sys	0m0.012s
```

## The logic (`egrep '^#' nad.sh`)
```
#!/bin/env bash
############################## define report function
############################## list blocked
# skip if cooldown is over
############################## list new requests
# count log lines
# skip if lower than NAD_MAX_REQUESTS
# skip if aready blocked
############################## update deny_ip file
# comment whitelisted
############################## reload nginx, try first
```


## deny_ip file convention

```
$ cat /etc/nginx/conf.d/nad_deny_ip.conf
location / {
    error_page 403 http://example.com/forbidden.html;
    deny 1.2.3.4; # DENY_TIMESTAMP
}
```
