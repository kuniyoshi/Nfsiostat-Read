use 5.10.0;
use strict;
use warnings;
package Nfsiostat::Read;
use autodie qw( open close );
use Readonly;

# ABSTRACT: reads /proc/self/mountstats and format it

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

__END__
device rootfs mounted on / with fstype rootfs
device nfs-server:/remote/mount/point mounted on /local/mount/point with fstype nfs statvers=1.1
	opts:	rw,vers=3,rsize=1048576,wsize=1048576,namlen=255,acregmin=3,acregmax=60,acdirmin=30,acdirmax=60,hard,nolock,proto=tcp,timeo=600,retrans=2,sec=sys,mountaddr=192.168.3.31,mountvers=3,mountport=54107,mountproto=tcp,local_lock=all
	age:	11416148
	caps:	caps=0x3fef,wtmult=4096,dtsize=4096,bsize=0,namlen=255
	sec:	flavor=1,pseudoflavor=1
	events:	1520147072 84509515934 168398 7470332 1232089477 498774437 86226925789 159898 71 38257361 159898 5219744496 35988 159897 159898 159898 0 1232055180 0 159897 159898 0 0 0 0 0 0 
	bytes:	7263950948543 1758878 0 0 1386876894225 1758878 361594403 159898 
	RPC iostats version: 1.0  p/v: 100003/3 (nfs)
	xprt:	tcp 977 1 4 0 0 2739061800 2738767649 294147 235823357669788 0 5127 2372793750 3533238452
	per-op statistics
	        NULL: 0 0 0 0 0 0 0 0
	     GETATTR: 1520086239 1520146727 24250 182420380180 170245444992 5417991317 8900250068 15167384918
	     SETATTR: 159897 159897 0 24943932 23025168 7900 175503 212408
	      LOOKUP: 546977363 546980660 811 73371177144 100623713960 269666136 1120446291 1628922817
	      ACCESS: 632786306 633022179 97281 78495072392 75934828456 20343045985 5754037778 26503692481
	    READLINK: 0 0 0 0 0 0 0 0
	        READ: 38424461 38424461 0 5072028852 1391859696128 3426588 168406259 188428818
	       WRITE: 159898 159898 0 24304496 21746128 14308 198184 283699
	      CREATE: 1 1 0 172 272 0 5 5
	       MKDIR: 0 0 0 0 0 0 0 0
	     SYMLINK: 0 0 0 0 0 0 0 0
	       MKNOD: 0 0 0 0 0 0 0 0
	      REMOVE: 0 0 0 0 0 0 0 0
	       RMDIR: 0 0 0 0 0 0 0 0
	      RENAME: 0 0 0 0 0 0 0 0
	        LINK: 0 0 0 0 0 0 0 0
	     READDIR: 17997 17997 0 2519580 74433936 63 7031 8864
	 READDIRPLUS: 45175 45175 0 6505200 137955164 285 29307 35171
	      FSSTAT: 36345 36346 0 4361492 3052980 60907 326100 414530
	      FSINFO: 2 2 0 240 160 0 0 0
	    PATHCONF: 1 1 0 120 56 0 0 0
	      COMMIT: 0 0 0 0 0 0 0 0

=pod

=head1 SYNOPSIS

  my $nfsiostat = Nfsiostat::Read->new;
  say $_
      for $nfsiostat->load->parse->make_logs;
