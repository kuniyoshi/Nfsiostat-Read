use 5.10.0;
use strict;
use warnings;
package Nfsiostat::Read::Log;
use Readonly;
use List::MoreUtils qw( mesh );
use Nfsiostat::Read;

our $VERSION = "0.01";

my %PREVIOUS_STAT;

sub parse {
    my $class = shift;
    my $line  = shift;

    my( $age, $device, $action, @fields ) = split m{\t}, $line;
    my %stat = mesh( @Nfsiostat::Parser::FIELD_NAMES, @fields );

  DIFF_WITH_PREVIOUS:
    for my $name ( @Nfsiostat::Parser::FIELD_NAMES ) {
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
    for my $name ( @Nfsiostat::Parser::FIELD_NAMES ) {
        @{ $PREVIOUS_STAT{ $device }{ $action }{ $name } }{ qw( age value ) } = ( $age, $stat{ $name} );
    }

    return ( device => $device, action => $action, stat => \%stat );
}

1;
