#!/usr/bin/perl -s
use 5.10.0;
use utf8;
use strict;
use warnings;
use open qw( :std :utf8 );
use autodie qw( open close );
use Data::Dumper;

$Data::Dumper::Terse    = 1;
$Data::Dumper::Sortkeys = 1;
$Data::Dumper::Indent   = 1;

chomp( my @files = `find lib -type f -name \\*.pm` );

my $glued_code;

for my $file ( @files ) {
    open my $FH, "<", $file;

    my $data = do { local $/; <$FH> };
    $data =~ s{
        ^ __END__ $
        .*
    }{}msx;

    for my $used_file ( @files ) {
        ( my $module_name = $used_file ) =~ s{lib/}{};
        $module_name =~ s{ [/] }{::}msx;
        $module_name =~ s{ [.]pm \z}{}msx;
        $data =~ s{
            ^ use \s \Q$module_name\E .*? $
        }{}msx;
    }

    $glued_code .= $data;

    close $FH;
}

my $header = <<'END_HEADER';
#!/usr/bin/perl -s
use 5.10.0;
use strict;
use warnings;
use Data::Dumper;

$Data::Dumper::Terse    = 1;
$Data::Dumper::Sortkeys = 1;
$Data::Dumper::Indent   = 1;

END_HEADER

my $body = <<'END_BODY';
package main;

while ( <> ) {
    chomp( my $line = $_ );
    my( $_tai64n, $line2 ) = split m{\s}, $line, 2;

    next
        if $line2 =~ m{\A [#] }msx;

    my %log = Nfsiostat::Reader::Log->parse( $line2 )
        or next;

    say Data::Dumper->new( [ \%log ] )->Indent( 0 )->Dump;
}

exit;

END_BODY

print $header, $glued_code, "\n", $body;

exit;
