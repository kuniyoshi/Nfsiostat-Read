#!/usr/bin/perl -s
use 5.10.0;
use strict;
use warnings;

use strict;
use warnings;
package Nfsiostat::Reader;
use Readonly;
use Carp ( );



# ABSTRACT: read from /proc/self/mountstats into perl data

our $VERSION = "0.000";

Readonly our @FIELD_NAMES => qw(
    operations
    transmissions
    major_timeouts
    bytes_sent
    bytes_received
    cumulative_queue_ms
    cumulative_response_ms
    cumulative_total_request_ms
);
Readonly my %SUB_CLASS => (
    proc  => join( q{::}, __PACKAGE__, "Proc" ),
    stdin => join( q{::}, __PACKAGE__, "Derivative" ),
);

sub field_names { @FIELD_NAMES }

sub new {
    my $class = shift;
    my %param = @_;
    my $from = delete $param{from}
        or Carp::croak( "from required." );

    Carp::croak( "Unknown from[$from] found." )
          unless exists $SUB_CLASS{ $from };

    $class = $SUB_CLASS{ $from };
    my $self = $class->new( %param );

    return $self;
}

1;

use 5.10.0;
use strict;
use warnings;
package Nfsiostat::Reader::Proc;
use base "Nfsiostat::Reader";
use autodie qw( open close );
use Readonly;

our $VERSION = "0.000";

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
    my $loaded_at = time;
    open my $FH, "<", $filename;
    chomp( my @lines = <$FH> );
    $self->{_lines} = \@lines;
    close $FH;
    $self->{_loaded_at} = $loaded_at;
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
}

sub interested_actions {
    my $self = shift;
    return @{ $self->{interested_actions} || [ ] } || @INTERESTED_ACTIONS;
}

sub make_logs {
    my $self = shift;
    my %statistics = %{ $self->{_statistics} };
    my $age = $statistics{age};
    my $time = $self->{_loaded_at};
    my @devices = grep { $_ ne "age" } keys %statistics;
    my @logs;

    for my $device ( @devices ) {
        for my $action ( keys %{ $statistics{ $device } } ) {
            next
                if !grep { $_ eq $action } $self->interested_actions;


            push @logs, join "\t", $time, $age, $device, $action, @{ $statistics{ $device }{ $action } }{ $self->field_names };
        }
    }

    die "Could not make_logs"
        unless @logs; # safety trigger to prevent high speed read loop.

    $self->{_logs} = \@logs;
}

sub read {
    my $self = shift;

    return shift @{ $self->{_logs} }
        if @{ $self->{_logs} || [ ] };

    $self->load;
    $self->parse;
    $self->make_logs;

    return
        if $self->{_logs}; # not first time.

    return shift @{ $self->{_logs} }; # is first time.
}

1;

use 5.10.0;
use strict;
use warnings;
package Nfsiostat::Reader::Derivative;
use base "Nfsiostat::Reader";
use List::MoreUtils qw( mesh );

our $VERSION = "0.000";

sub new {
    my $class = shift;
    my %param = @_;
    my $handler = delete $param{handler} || *ARGV;
    my $self = bless { _handler => $handler }, $class;
    return $self;
}

sub handler { shift->{_handler} }

sub previous { shift->{_previous} ||= { } }

sub parse {
    my $self = shift;
    my $line = shift;

    my( $age, $device, $action, @fields ) = split m{\t}, $line;
    my @field_names = $self->field_names;
    my %stat = mesh( @field_names, @fields );
    my %stat_for_previous = %stat;
    my $previous_ref = $self->previous; # inout parameter

  DIFF_WITH_PREVIOUS:
    for my $name ( @field_names ) {
        if ( !exists $previous_ref->{ $device }{ $action }{ $name }{age} ) {
            @{ $previous_ref->{ $device }{ $action }{ $name } }{ qw( age value ) } = ( $age, $stat{ $name } );
            next;
        }

        $stat{ $name } = $previous_ref->{ $device }{ $action }{ $name }{value}
        / ( $age - $previous_ref->{ $device }{ $action }{ $name }{age} );
    }

    return
        if $previous_ref->{ $device }{ $action }{operations}{age} == $age;

    $stat{avg_queue_ms}    = $stat{transmissions} / $stat{cumulative_queue_ms};
    $stat{avg_response_ms} = $stat{transmissions} / $stat{cumulative_response_ms};
    $stat{avg_request_ms}  = $stat{operations}    / $stat{cumulative_total_request_ms};

  CHANGE_CURRENT_TO_PREVIOUS:
    for my $name ( @field_names ) {
        @{ $previous_ref->{ $device }{ $action }{ $name } }{ qw( age value ) } = ( $age, $stat_for_previous{ $name} );
    }

    return ( device => $device, action => $action, stat => \%stat );
}

1;

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

