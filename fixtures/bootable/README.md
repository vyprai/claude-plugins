# bootable

A path traversal that VyQL reports and that a request can prove. Boots cold with
no credentials and no seeded database, which is what makes it a fixture rather
than a demo.

```
GET /download?name=readme.txt          a public file
GET /download?name=../../etc/passwd    root:x:0:0:root:/root:/bin/bash
```

`vyql scan` reports `VYQL-PATH-001` and `VYQL-INJ-004` here.

Two details are load-bearing. `/var/data` is created at boot, because without the
directory the traversal fails on the missing intermediate path instead of
escaping. And the healthcheck exists because `up --wait` returns as soon as the
container runs, which is long before `npm install` finishes.
