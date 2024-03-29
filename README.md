# NAME

File::Meta::Cache - Cache open file descriptors and stat meta data

# SYNOPSIS

```perl
use File::Meta::Cache;
# Create a cache object
#
my $cache=File::Meta::Cache->new;

  ###
  
# OO Interface for opening:
#
my $entry=$cache->open("path to file");

#         OR

# High performance API for opening
#
my $opener=$cache->opener; 
my $entry=$opener->("path to file");

  ###

if($entry and $entry->[File::Meta::Cache::VALID]){
  # Work with the file
  #
  for($entry->[File::Meta::Cache::FH]){

      sysread $_, my  $buffer, ...;
  }

  # Set user defined data in entry if no already defined
  #
  $entry->[File::Meta::Cache::USER]=//
  [
    "Content-Length: $entry->[File::Meta::Cache::STAT][7],
  ];
}
else {
  # Cache entry was invalid or no such file
  #
  die "Cache entry invalid" 
}

```

# DESCRIPTION

Implements a caching mechanism to reuse a open handle/descriptor and meta data
when 'opening' a file multiple times. 

This is especially useful in a programs such as web servers which typically
access the same static file multiple times in response to requests. Not having
to open the file repeatedly can significantly reduce processing time. It also
reduces the number of open file descriptors required, which allows more files
to be accessed without adjusting process/user resource limits. 

Files are 'opened' and 'closed' via the cache in order to track how many
references to an entry are active (not Perl reference counting BTW). When an
entry has no references, it is eligible to be removed by 'sweeping' the cache.
This should be done a regular interval to keep the meta data fresh, but long
enough to make the cache useful.  To make this module event system agnostic it
is up to the user to implement a timer that calls the `sweep` API.

Importantly, a entry only uses a single file descriptor per file. Multiple
users of the same entry must track their own file positions. When doing IO on
the file, appropriate calls to `seek` (or `pread`/`pwrite` via `IO::FD`)
will need to be performed to set the position for correct IO operation.

Each cached entry contains a `USER` field, which allows the user to store
associated meta data with the entry. For example this could be used to store
pre rendered HTTP headers (content-type, content-length, etag, modification
headers, etc), which only need to be computed when the file was opened.

Note this module is tuned for performance rather than nice programming style.
Thus fields within a cache entry are accessible by their position in an array
instead of a nice hash name or accessors methods.  

# API

An OO API is provided for configuration and ease of use and an additional
functional API for best performance for high frequency access.

## Cache entry

A cache entry is an anonymous array with the following fields:

```perl
New constant name:         KEY  FD  FH   STAT  VALID   USER
Depricated constant name:  key_ fd_ fh_  stat_ valid_  user_
                   values: 0    1   2    3     4       5
```

This are constants defined in the `File::Meta::Cache` package, which can be
used as indexes into the array.

**NOTE:** from v0.3.0, the field index contants have been renamed. The old names
are depricated and will be removed in a later version. Please use the new names.

### KEY (=0) 

The key to the cache table, which is the file path used when calling the
`open` method.

### FD (=1)

The file descriptor of the opened file.  This can be used directly with
[POSIX](https://metacpan.org/pod/POSIX) or `IO::FD` module for IO operations.

### FH (=2)

The file handle of the opened file. This will undefined if the cache was
initialised with `no_fh` parameter.

### STAT (=3)

This is the reference to an array of stat information from the `stat` call.

### VALID (=4)

A value indicating if the cache entry is current or has been invalidated. If it
is greater than 0, the entry is still considered fresh and valid.  If it is 0,
the cache entry has be removed from the cache and the file has been closed.

### USER (=5)

A general purpose field for storing user associated data with the cache entry.
This could pre computed/rendered data based on the stat information.

## OO Interface

### new

```perl
my $fmc = File::Meta::Cache->new;
```

Returns a new  [File::Meta::Cache](https://metacpan.org/pod/File%3A%3AMeta%3A%3ACache) object. Each object is a unique cache and
does not share entries with other cache objects.

### open

```perl
my $entry=$fmc->open($file_path, [$mode, $force]);
```

Attempts to find the file path in the cache and return the existing entry. If
it is found, the reference count of the cache entry is incremented and the entry returned.

If no entry was found, a stat of the given file path is performed. If
successful, creates an cache entry to store the stat information. The file is
then opened and a file handle created if required. The handle and the backing
file descriptor are added to the cache entry.

If the cache is enabled, the entry is added to the cache.

The entry (array ref) is returned on success, or `undef` is returned if the
file could not be opened.

`$mode` specifies the open mode flags as per the open (2) system call. If
undefined or not specified the default value of `O_RDONLY` is used.

`$force` will force the file to be reopened to the same file descriptor
currently used for the file. This will force another `stat` on the file and
updates the cache entry accordingly. The cache entry is still considered valid
and file the file descriptor and file handle are unchanged.

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

These methods bypass the slow OO lookup by providing a code reference to
directly open, close and sweep cache entries.

### opener

```perl
my $opener_sub=$object->opener;
```

Returns the code reference which actually performs cache lookup, file opening
required and  'reference count incrementing'.

The returned code reference takes the same arguments as the `open` method. 

```perl
eg:
  my $entry=$opener_sub->("path to file");
```

### sweeper

```perl
my $sweeper_sub=$object->sweeper;
```

Returns the code reference which actually performs cache sweep, of unused cache
entries.  The returned code reference takes the same arguments as the `sweep`
method.

```perl
eg:
  $sweeper_sub->();
```

### closer

```perl
my $closer_sub=$object->closer;
```

Returns the code reference which actually performs 'reference count
decrementing' and closes the file if needed.

The returned code reference takes the same arguments as the `close` method.

```perl
eg:
  $closer_sub->($entry);
```

### updater

```perl
my $updater_sub=$object->updater;
```

Returns the code reference which actually performs updating of a cache entry.

The returned code reference takes the same arguments as the `update` method.

```perl
eg $updater_sub->($entry);
```

# PERFORMANCE

Once a file is open, subsequent opens are only a hash lookup. No open or stat
call is issued. 

Note that unless the rest of your application is written to
handle high frequency access to the files of interest, this module will give
only modest performance improvements.

TODO - more details and an actual benchmark.

# SEE ALSO

There is a PSGI specific module [Plack::Middleware::Static::OpenFileCache](https://metacpan.org/pod/Plack%3A%3AMiddleware%3A%3AStatic%3A%3AOpenFileCache)
which provides similar functionality. The invalidating of an entry in the cache
if significantly different. Also this module allows for both read and write
access to an open file.

# REPOSITORY and BUG REPORTING

Please report any bugs and feature requests on the repo page:
[GitHub](http://github.com/drclaw1394/perl-file-meta-cache)

# AUTHOR

Ruben Westerberg, <drclaw@mac.com>

# COPYRIGHT AND LICENSE

Copyright (C) 2023 by Ruben Westerberg

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, or under the MIT license
