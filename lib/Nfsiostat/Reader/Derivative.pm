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
