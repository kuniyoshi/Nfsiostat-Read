use strict;
use warnings;
package Nfsiostat::Reader;
use Readonly;

# ABSTRACT: read from /proc/self/mountstats into perl data

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

1;
