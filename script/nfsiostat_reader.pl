#!/usr/bin/perl -s
use 5.10.0;
use strict;
use warnings;
use Data::Dumper;

$Data::Dumper::Terse    = 1;
$Data::Dumper::Sortkeys = 1;
$Data::Dumper::Indent   = 1;

use 5.10.0;
use strict;
use warnings;
package Nfsiostat::Read;
use autodie qw( open close );
use Readonly;

our $VERSION = "0.01";

Readonly my $PROC_FILE       => "/proc/self/mountstats";
Readonly my $DEVICE_PARSE_RE => qr{
    \A
    device \s
    (?<name>[^\s]+) \s
    mounted \s on \s
    (?<mounted_on>[^\s]+) \s
    with \s fstype \s
    (?<fstype>[^\s]+)
}msx;
Readonly my $PER_OP_RE       => qr{
    \A
    \t [ ]+
    (?<action>\w+)[:] \s
    (?<operations>\d+) \s
    (?<transmissions>\d+) \s
    (?<major_timeouts>\d+) \s
    (?<bytes_sent>\d+) \s
    (?<bytes_received>\d+) \s
    (?<cumulative_queue_ms>\d+) \s
    (?<cumulative_response_ms>\d+) \s
    (?<cumulative_total_request_ms>\d+)
    \z
}msx;
Readonly our @FIELD_NAMES        => qw(
    operations
    transmissions
    major_timeouts
    bytes_sent
    bytes_received
    cumulative_queue_ms
    cumulative_response_ms
    cumulative_total_request_ms
);
Readonly our @VALID_ACTIONS      => qw(
	NULL
	GETATTR
	SETATTR
	LOOKUP
	ACCESS
	READLINK
	READ
	WRITE
	CREATE
	MKDIR
	SYMLINK
	MKNOD
	REMOVE
	RMDIR
	RENAME
	LINK
	READDIR
	READDIRPLUS
	FSSTAT
	FSINFO
	PATHCONF
);
Readonly our @INTERESTED_ACTIONS => qw(
    GETATTR
    SETATTR
    LOOKUP
    ACCESS
    READ
    WRITE
    READDIR
    READDIRPLUS
    FSSTAT
);

sub new {
    my $class = shift;
    my %param = @_;
    my $self = bless { interested_actions => delete $param{interested_actions} }, $class;
    return $self;
}

sub load {
    my $self     = shift;
    my $filename = shift || $PROC_FILE;
    open my $FH, "<", $filename;
    chomp( my @lines = <$FH> );
    $self->{_lines} = \@lines;
    close $FH;
    return $self;
}

sub parse {
    my $self = shift;
    my %device;
    my %statistics;
    my $age;

    for my $line ( @{ $self->{_lines} } ) {

        if ( $line =~ m{$DEVICE_PARSE_RE} ){
            %device = %+;
            next;
        }

        if ( $line =~ m{\A \s+ age: \s+ (?<age>\d+) \z}msx ) {
            $age = $+{age};
        }

        if ( $line =~ m{$PER_OP_RE} ) {
            my %stat = %+;
            my $action = delete $stat{action};
            $statistics{ $device{name} }{ $action } = \%stat;
            next;
        }
    }

    $statistics{age} = $age;

    $self->{_statistics} = \%statistics;

    return $self;
}

sub interested_actions {
    my $self = shift;
    return @{ $self->{interested_actions} || [ ] } || @INTERESTED_ACTIONS;
}

sub make_logs {
    my $self = shift;
    my %statistics = %{ $self->{_statistics} };
    my $age = $statistics{age};
    my @devices = grep { $_ ne "age" } keys %statistics;
    my @logs;

    for my $device ( @devices ) {
        for my $action ( keys %{ $statistics{ $device } } ) {
            next
                if !grep { $_ eq $action } $self->interested_actions;
            push @logs, join "\t", $age, $device, $action, @{ $statistics{ $device }{ $action } }{ @FIELD_NAMES };
        }
    }

    return @logs;
}

1;

use 5.10.0;
use strict;
use warnings;
package Nfsiostat::Read::Log;
use Readonly;
use List::MoreUtils qw( mesh );


our $VERSION = "0.01";

my %PREVIOUS_STAT;

sub parse {
    my $class = shift;
    my $line  = shift;

    my( $age, $device, $action, @fields ) = split m{\t}, $line;
    my %stat = mesh( @Nfsiostat::Read::FIELD_NAMES, @fields );

  DIFF_WITH_PREVIOUS:
    for my $name ( @Nfsiostat::Read::FIELD_NAMES ) {
        if ( !exists $PREVIOUS_STAT{ $device }{ $action }{ $name }{age} ) {
            @{ $PREVIOUS_STAT{ $device }{ $action }{ $name } }{ qw( age value ) } = ( $age, $stat{ $name } );
            next;
        }

        $stat{ $name } = $PREVIOUS_STAT{ $device }{ $action }{ $name }{value}
        / ( $age - $PREVIOUS_STAT{ $device }{ $action }{ $name }{age} );
    }

    return
        if $PREVIOUS_STAT{ $device }{ $action }{operations}{age} == $age;

    $stat{avg_queue_ms}    = $stat{transmissions} / $stat{cumulative_queue_ms};
    $stat{avg_response_ms} = $stat{transmissions} / $stat{cumulative_response_ms};
    $stat{avg_request_ms}  = $stat{operations} / $stat{cumulative_total_request_ms};

  CHANGE_CURRENT_TO_PREVIOUS:
    for my $name ( @Nfsiostat::Read::FIELD_NAMES ) {
        @{ $PREVIOUS_STAT{ $device }{ $action }{ $name } }{ qw( age value ) } = ( $age, $stat{ $name} );
    }

    return ( device => $device, action => $action, stat => \%stat );
}

1;

package main;

while ( <> ) {
    chomp( my $line = $_ );
    my( $_tai64n, $line2 ) = split m{\s}, $line, 2;

    next
        if $line2 =~ m{\A [#] }msx;

    my %log = Nfsiostat::Read::Log->parse( $line2 )
        or next;

    say Data::Dumper->new( [ \%log ] )->Indent( 0 )->Dump;
}

exit;

