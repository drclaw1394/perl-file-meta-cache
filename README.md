# NAME

File::Meta::Cache - Cache open file descriptors and meta data

# SYNOPSIS

```perl
use File::Meta::Cache;
# Create a cache object
#
my $cache=File::Meta::Cache->new;


# open a file and get cache entry.
#
my $entry=$cache->open("path to file");

if($entry and $entry->[File::Meta::Cache::valid_]){
  # Work with the file
  #
  for($entry->[File::Meta::Cache::fh_]){

      sysread $_, my  $buffer, ...;
  }

  # Set user defined data in entry if no already defined
  #
  $entry->[File::Meta::Cache::user_]=//[
    "Content-Length: $entry->[File::Meta::Cache::stat_][7],
  ];
}
else {
  # Cache entry was invalid or no such file
  #
  die "Cache entry invalid" 
}
```

# DESCRIPTION

Implements a caching mechanism to reuse open file meta data when 'opening' a
file multiple times.

This is especially useful in a programs such as web servers which typically
access the same static file multiple times in response to requests. Not having
to open the file repeatedly can significantly reduce processing time. It also
reduces the number of open file descriptors required, which allows more files
to be accessed. 

Files are 'opened' and 'closed' via the cache in order to track how many
references to an entry are active. When an entry has no references, it is
eligible to be removed by 'sweeping' the cache.  This should be done a regular
interval to keep the meta data fresh, but long enough to make the cache useful.

Importantly, a entry only uses a single file descriptor per file. Multiple uses
of the same entry must track their own file position.  When doing IO on the
file, appropriate calls to `seek` (or `pread`/`pwrite` via `IO::FD`) will
need to be performed to set the position for correct IO operation.

Each cached entry contains a `user_` field, which allows the user to store
associated meta data with the entry. For example this could be used to store
pre rendered HTTP headers (content-type, content-length, etag, modification
headers, etc), which only need to be computed when the file was opened.

# API

An OO API is provided for configuration and ease of use and a functional API
for best performance.

## Cache entry

A cache entry is an anonymous array with the following fields

```perl
key_ fd_ fh_ stat_ valid_ user_
 0    1   2    3     4      5
```

This are constants defined starting from 0 to 4, which can be used as indexes
into the array.

### key\_ (=0)

The key to the cache table, which is the file path used when calling the
`open` method.

### fd\_ (=1)

The file descriptor of the opened file.  This can be used directly with
[POSIX](https://metacpan.org/pod/POSIX) or `IO::FD` module for IO operations.

### fh\_ (=2)

The file handle of the opened file. This will undefined if the cache was
initialised with `no_fh` parameter.

### stat\_ (=3)

This is the reference to an array of stat information from the `stat` call.

### valid\_ (=4)

A value indicating if the cache entry is current or has been invalidated. If it
is greater than 0, the entry is still considered fresh and valid.  If it is 0,
the cache entry has be removed from the cache and the file has been closed.

### user\_ (=5)

A general purpose field for storing user associated data with the cache entry.
This could pre computed/rendered data based on the stat information.

## OO Interface

### new

```perl
my $fmc = File::Meta::Cache->new;
```

Returns a new  [File::Meta::Cache](https://metacpan.org/pod/File%3A%3AMeta%3A%3ACache) object. Each object contains its own.

### open

```perl
my $entry=$fmc->open($file_path, [$mode, $force]);
```

Returns the cache entry matching the file path given. If the file was not found
returns `undef`.

`$mode` specifies the open mode flags as per the open (2) system call. If
undefined or not specified the default value of `O_RDONLY` is used;

`$force` will force the file to be reopened to the same file descriptor
currently used for the file. This performs the stat on the file and updates the
cache entry accordingly. The cache entry is still considered valid.

### close

```
$fmc->close($entry,[$force]);
```

Decrements the file reference count. If it is no longer referenced by any
users, the file is closed and the cache entry is invalidated and removed from
the cache.

If the `$force` parameter is specified and true, a explicit invalidation of
the entry is performed and the file descriptor is closed.

### enable

```
$fmc->enable;
```

Enables the caching of file handles and stat meta data.

### disable

```
$fmc->disable;
```

Disables the caching of file descriptors and stat meta data. Any entries in the
cache are removed and closed.

### sweep

```
$fmc->sweep
```

Iterates through the cache closes/removes any entries that are no longer
referenced by any users. Call this periodically to keep the size of the cache
under control.

### update

```
$fmc->update($entry)
```

Attempts to perform a stat on the file referenced in the cache entry. Updates
the entry state information but does not reopen the file. If it fails, it
invalidates the cache entry.

## High Performance API

These methods bypass the slow OO lookup but providing a code reference to directly open, close and sweep cache entries.

### opener

```perl
my $opener_sub=$object->opener;
```

Returns the code reference which actually performs cache lookup, file opening
required and  'reference count incrementing'.

The returned code reference takes the same arguements as the `open` method. 

### sweeper

```
$object->sweeper;
```

Returns the code reference which actually performs cache sweep, of unused cache
entries.  The returned code reference takes the same arguments as the `sweep`
method.

### closer

```
$object->closer;
```

Returns the code reference which actually performs 'reference count
decrementing' and closes the file if needed.

The returned code reference takes the same arguments as the `close` method.

### updater

```
$object->updater
```

Returns the code reference which actually performs updating of a cache entry.

The returned code reference takes the same arguments as the `update` method.

# SEE ALSO

Yet another template module right? 

Do a search on CPAN for 'template' and make a cup of coffee.

# REPOSITORY and BUG REPORTING

Please report any bugs and feature requests on the repo page:
[GitHub](http://github.com/drclaw1394/perl-file-meta-cache)

# AUTHOR

Ruben Westerberg, <drclaw@mac.com>

# COPYRIGHT AND LICENSE

Copyright (C) 2023 by Ruben Westerberg

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, or under the MIT license
