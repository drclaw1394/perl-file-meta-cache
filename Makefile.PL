use 5.024000;
use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
  NAME              => 'File::Meta::Cache',
  VERSION_FROM      => 'lib/File/Meta/Cache.pm', # finds $VERSION, requires EU::MM from perl >= 5.5
  PREREQ_PM         => {}, # e.g., Module::Name => 1.1
  ABSTRACT_FROM     => 'lib/File/Meta/Cache.pm', # retrieve abstract from module
  AUTHOR            => 'Ruben Westerberg <drclaw@local>',
  LICENSE           => 'mit',
  META_ADD => {
    "meta-spec" => {
      version => 2
    },
    resources=> {
      repository =>{
        type => "git",
        url => "git://github.com/drclaw1394/perl-file-meta-cache.git",
        web => "http://github.com/drclaw1394/perl-file-meta-cache",
      }
    }
  }

);