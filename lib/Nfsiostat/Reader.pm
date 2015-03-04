use strict;
use warnings;
package Nfsiostat::Reader;
use Readonly;
use Carp ( );
use Nfsiostat::Reader::Proc;
use Nfsiostat::Reader::Derivative;

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

__END__
=pod

=encoding utf8

=head1 NAME

Nfsiostat::Reader

=head1 DESCRIPTION

=head1 SYNOPSIS

  my $logger = Nfsiostat::Reader->new( from => "proc" );

  while ( 1 ) {
      my $log = $logger->read;

      if ( defined $log ) {
          say $log;
      }
      else {
          sleep 3;
      }
  }

  my $reader = Nfsiostat::Reader->new( from => "stdin" );

  use Data::Dumper;

  while ( <> ) {
      chomp( my $line = $_ );
      my %log = $reader->parse( $line );
      say Dumper \%log;
  }

=head1 METHODS

=over

=item new

=item read

=back

