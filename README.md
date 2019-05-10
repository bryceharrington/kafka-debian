# Debianization for the Apache Kafka server

The repo contains so called DEBIAN directory with
scripts and configs needed to package the
[Apache Kafka](http://kafka.apache.org/) server
into a DEB package for the Debian Jessie distro.

The specs are adapted to pre-built Apache Kafka.

## Short DEB-packaging HowTo

1. Download the upstream tarball with pre-built Apache Kafka from the
 [Kafka site](http://kafka.apache.org/downloads.html);
 or use ``uscan`` to download automatically:

```uscan --force-download```

2. Unpack the tarball:

```tar zxf kafka-2.11-$version.tar.gz```

3. Copy the _debian_ dir into the upstream sources tree:

```cp -r /path/to/the/repo/debian ./kafka-$version/```

4. Build package

```cd kafka_2.11-$version && dpkg-buildpackage -b```
 
or (if you do not want to gpg sign on the machine you are building on):

```cd kafka_2.11-$version && debuild -b -uc -us```

5. Install package

```dpkg --install kafka-$version_all.db```

Directory layout:

* _/etc/kafka_ - configs;
* _/usr/lib/kafka/bin_ - helper scripts;
* _/var/lib/kafka_ - PID files and runtime data;
* _/var/log/kafka_ - log files.
