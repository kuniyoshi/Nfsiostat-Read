#!/usr/bin/perl -s
use 5.10.0;
use utf8;
use strict;
use warnings;
use open qw( :std :utf8 );
use autodie qw( open close );
use Data::Dumper;
use File::Spec ( );

$Data::Dumper::Terse    = 1;
$Data::Dumper::Sortkeys = 1;
$Data::Dumper::Indent   = 1;

our $VERSION = "0.000";

our $from;
die usage( )
    unless defined $from;

chomp( my @files = `find lib -type f -name \\*.pm` );

my $glued_code;

for my $file ( sort { scalar( File::Spec->splitdir( $a ) ) <=> scalar( File::Spec->splitdir( $b ) ) } @files ) {
    open my $FH, "<", $file;

    my $data = do { local $/; <$FH> };
    $data =~ s{
        ^ (?: __END__ | __DATA__ ) $
        .*
    }{}msx;

    for my $used_file ( @files ) {
        ( my $module_name = $used_file ) =~ s{lib/}{};
        $module_name =~ s{ [/] }{::}gmsx;
        $module_name =~ s{ [.]pm \z}{}msx;
        $data =~ s{
            ^ use \s \Q$module_name\E .*? $
        }{}msx;
    }

    $glued_code .= $data;

    close $FH;
}

my $header = do { no strict "refs"; &{ "get_header_$from" } };
my $body   = do { no strict "refs"; &{ "get_body_$from" } };

print $header, $glued_code, "\n", $body;

exit;

sub get_body_stdin {
    return <<'END_BODY';
package main;
use Time::TAI64;
use Data::Dumper;

$Data::Dumper::Terse    = 1;
$Data::Dumper::Sortkeys = 1;
$Data::Dumper::Indent   = 0;

my $reader = Nfsiostat::Reader->new( from => "stdin" );

while ( <> ) {
    chomp( my $line = $_ );
    my( $tai64n, $nfsiostat_line ) = split m{\s}, $line, 2;

    next
        if 0 == index $nfsiostat_line, q{#};

    my %log = $reader->parse( $nfsiostat_line )
        or next;

    say Dumper \%log;
}

END_BODY
}

sub get_body_proc {
    return <<'END_BODY';
package main;
our $interval  ||= 2;
our $iteration ||= 22;

my $count;

my $reader = Nfsiostat::Reader->new( from => "proc" );

while ( $count++ < $iteration ) {
    while ( my $log = $reader->read ) {
        say $log;
    }

    sleep $interval;
}

exit;

END_BODY
}

sub get_header_stdin { &get_header_proc }

sub get_header_proc {
    return <<'END_HEADER';
#!/usr/bin/perl -s
use 5.10.0;
use strict;
use warnings;

END_HEADER
}

sub usage {
    return <<END_USAGE;
usage: $0 -from=<proc | stdin>
END_USAGE
}
