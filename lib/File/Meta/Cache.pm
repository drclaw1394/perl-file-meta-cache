use strict;
use warnings;
package File::Meta::Cache;
our $VERSION="v0.1.0";
# Default Opening Mode
use Fcntl qw(O_NONBLOCK O_RDONLY);
use constant OPEN_MODE=>O_RDONLY|O_NONBLOCK;
use enum qw<key_ fd_ fh_ stat_ valid_ user_>;

use Object::Pad;

class File::Meta::Cache;
use feature qw<say state>;

use Log::ger;   # Logger
use Log::OK;    # Logger enabler

use POSIX();



field $_sweep_size;

field $_no_fh;
field $_enabled;
field $_sweeper;
field %_cache;
field $_opener;
field $_closer;
field $_updater;
field $_http_headers;

BUILD{
  $_sweep_size//=100;
  $_enabled=1;
}

method sweeper {
  $_sweeper//= sub {
    my $i=0;
    my $entry;
    my $closer=$self->closer;
    for(keys %_cache){
      $entry=$_cache{$_};

      # If the cached_ field reaches 1, this is the last code to use it. so close it
      # 
      $closer->($entry) if($entry->[valid_]==1);
      last if ++$i >= $_sweep_size;
    }
  }
}

# returns a sub to execute. Object::Pad method lookup is slow. so bypass it
# when we don't need it
#
method opener{
  $_opener//=
  sub {
    my ( $key_path, $mode, $force)=@_;
    my $in_fd;

    # Entry is identified by the path, however, the actual data can come from another file
    # 
    my $existing_entry=$_cache{$key_path};
    $mode//=O_RDONLY;
    if(!$existing_entry or $force){
        Log::OK::TRACE and log_trace __PACKAGE__.": Searching for: $key_path";

        my @stat=stat $key_path;
        
        # If the stat fail or is not a file return undef.
        # If this is a reopen(force), the force close the file to invalidate the cache
        #
        unless(@stat and -f _){
          $_closer->($existing_entry, 1) if $existing_entry;
          return undef;
        };

        my @entry;
        $in_fd=POSIX::open($key_path, $mode);



        if(defined $in_fd){
          
          if($existing_entry){
            # Duplicate and Close unused fd
            POSIX::dup2 $in_fd, $existing_entry->[fd_];
            POSIX::close $in_fd;

            # Copy stat into existing array 
            $existing_entry->[stat_]->@*=@stat;
          }
          else {
            open($entry[fh_], "+<&=$in_fd") unless($_no_fh);

            $entry[stat_]=\@stat;
            $entry[key_]=$key_path;
            $entry[fd_]=$in_fd;
            $entry[valid_]=1;#$count;

            $existing_entry =\@entry;
            $_cache{$key_path}=$existing_entry if($_enabled);
          }
        }
        else {
          Log::OK::ERROR and log_error __PACKAGE__." Error opening file $key_path: $!";
        }
    }

    # Increment the  counter 
    #
    $existing_entry->[valid_]++ if $existing_entry;
    $existing_entry;
  }
}


# Mark the cache as disabled. Dumps all values and closes
# all fds
#
method disable{
  $_enabled=undef;
  for(values %_cache){
    POSIX::close($_cache{$_}[0]);
  }
  %_cache=();
}

# Generates a sub to close a cached fd
# removes meta data from the cache also
#
method closer {
  $_closer//=sub {
      my $entry=$_[0];
      if(--$entry->[valid_] <=0 or $_[1]){
        my $actual=delete $_cache{$entry->[key_]};
        if($actual){
          # Attempt to close only if the entry exists
          $actual->[valid_]=0;  #Mark as invalid
          POSIX::close($actual->[fh_]);
        }
        else {
          die "Entry does not exist";
        }
      }
  }
}

method updater{
  $_updater//=sub {
    # To a stat on the entry 
    $_[0][stat_]->@*=stat $_[0][key_];
    unless($_[0][stat_]->@* and -f _){
      # This is an error force close the file
      $_closer->($_[0], 1 );
    }
  }
}

# OO Interface
#

method open {
  $self->opener->&*;
}

method close {
  $self->closer->&*;
}
method update{
  $self->updater->&*;
}

method sweep {
  $self->sweeper->&*;
}

method enable{ $_enabled=1; }

1;

=head1 NAME

File::Meta::Cache - Cache open file descriptors and meta data

=head1 SYNOPSIS

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




=head1 DESCRIPTION

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
file, appropriate calls to C<seek> (or C<pread>/C<pwrite> via C<IO::FD>) will
need to be performed to set the position for correct IO operation.


Each cached entry contains a C<user_> field, which allows the user to store
associated meta data with the entry. For example this could be used to store
pre rendered HTTP headers (content-type, content-length, etag, modification
headers, etc), which only need to be computed when the file was opened.
 

=head1 API

An OO API is provided for configuration and ease of use and a functional API
for best performance.



=head2 Cache entry

A cache entry is an anonymous array with the following fields
  
 key_ fd_ fh_ stat_ valid_ user_
  0    1   2    3     4      5

This are constants defined starting from 0 to 4, which can be used as indexes
into the array.

=head3 key_ (=0)

The key to the cache table, which is the file path used when calling the
C<open> method.

=head3 fd_ (=1)

The file descriptor of the opened file.  This can be used directly with
L<POSIX> or C<IO::FD> module for IO operations.

=head3 fh_ (=2)

The file handle of the opened file. This will undefined if the cache was
initialised with C<no_fh> parameter.


=head3 stat_ (=3)

This is the reference to an array of stat information from the C<stat> call.

=head3 valid_ (=4)

A value indicating if the cache entry is current or has been invalidated. If it
is greater than 0, the entry is still considered fresh and valid.  If it is 0,
the cache entry has be removed from the cache and the file has been closed.

=head3 user_ (=5)

A general purpose field for storing user associated data with the cache entry.
This could pre computed/rendered data based on the stat information.


=head2 OO Interface

=head3 new

  my $fmc = File::Meta::Cache->new;

Returns a new  L<File::Meta::Cache> object. Each object contains its own.


=head3 open
  
  my $entry=$fmc->open($file_path, [$mode, $force]);


Returns the cache entry matching the file path given. If the file was not found
returns C<undef>.

C<$mode> specifies the open mode flags as per the open (2) system call. If
undefined or not specified the default value of C<O_RDONLY> is used;

C<$force> will force the file to be reopened to the same file descriptor
currently used for the file. This performs the stat on the file and updates the
cache entry accordingly. The cache entry is still considered valid.


=head3 close

  $fmc->close($entry,[$force]);

Decrements the file reference count. If it is no longer referenced by any
users, the file is closed and the cache entry is invalidated and removed from
the cache.

If the C<$force> parameter is specified and true, a explicit invalidation of
the entry is performed and the file descriptor is closed.



=head3 enable

  $fmc->enable;

Enables the caching of file handles and stat meta data.

=head3 disable

  $fmc->disable;

Disables the caching of file descriptors and stat meta data. Any entries in the
cache are removed and closed.


=head3 sweep

  $fmc->sweep

Iterates through the cache closes/removes any entries that are no longer
referenced by any users. Call this periodically to keep the size of the cache
under control.

=head3 update

  $fmc->update($entry)

Attempts to perform a stat on the file referenced in the cache entry. Updates
the entry state information but does not reopen the file. If it fails, it
invalidates the cache entry.



=head2 High Performance API

These methods bypass the slow OO lookup but providing a code reference to directly open, close and sweep cache entries.

=head3 opener
  
    my $opener_sub=$object->opener;

Returns the code reference which actually performs cache lookup, file opening
required and  'reference count incrementing'.

The returned code reference takes the same arguements as the C<open> method. 

=head3 sweeper

  $object->sweeper;

Returns the code reference which actually performs cache sweep, of unused cache
entries.  The returned code reference takes the same arguments as the C<sweep>
method.

=head3 closer

  $object->closer;

Returns the code reference which actually performs 'reference count
decrementing' and closes the file if needed.


The returned code reference takes the same arguments as the C<close> method.


=head3 updater

  $object->updater

Returns the code reference which actually performs updating of a cache entry.

The returned code reference takes the same arguments as the C<update> method.


=head1 SEE ALSO

Yet another template module right? 

Do a search on CPAN for 'template' and make a cup of coffee.

=head1 REPOSITORY and BUG REPORTING

Please report any bugs and feature requests on the repo page:
L<GitHub|http://github.com/drclaw1394/perl-file-meta-cache>

=head1 AUTHOR

Ruben Westerberg, E<lt>drclaw@mac.comE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2023 by Ruben Westerberg

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, or under the MIT license

=cut
