package LWP::UserAgent::Plugin::FilterLcpan;

use 5.010001;
use strict;
use warnings;
use experimental 'smartmatch';
use Log::ger;

use HTTP::Response;

# AUTHORITY
# DATE
# DIST
# VERSION

sub before_mirror {
    my ($self, $r) = @_;

    my ($ua, $url, $filename) = @{ $r->{argv} };

    if ($r->{config}{include_author}) {
        my $ary = ref $r->{config}{include_author} eq 'ARRAY' ?
            $r->{config}{include_author} : [split /;/, $r->{config}{include_author}];
        if ($url =~ m!authors/id/./../(.+)/! && !($1 ~~ @$ary)) {
            say "mirror($url, $filename): author not included, skipping"
                if $r->{config}{verbose};
            return HTTP::Response->new(304);
        }
    }
    if ($r->{config}{exclude_author}) {
        my $ary = ref $r->{config}{exclude_author} eq 'ARRAY' ?
            $r->{config}{exclude_author} : [split /;/, $r->{config}{exclude_author}];
        if ($url =~ m!authors/id/./../(.+)/! && ($1 ~~ @$ary)) {
            say "mirror($url, $filename): author included, skipping"
                if $r->{config}{verbose};
            return HTTP::Response->new(304);
        }
    }
    if (my $max_size = $r->{config}{max_size}) {
        my $size = (-s $filename);
        if ($size && $size > $max_size) {
            say "mirror($url, $filename): local size ($size) > max_size ($max_size), skipping"
                if $r->{config}{verbose};
            return HTTP::Response->new(304);
        }

        # perform HEAD request to find out the size
        my $resp = $ua->head($url);
        {
            last unless $resp->is_success;
            last unless defined(my $len = $resp->header("Content-Length"));
            if ($len > $max_size) {
                say "mirror($url, $filename): remote size ($len) > max_size ($max_size), skipping"
                    if $r->{config}{verbose};
                return HTTP::Response->new(304);
            }
        }
    }

    1;
}

1;
# ABSTRACT: Filter mirror() based on some criteria

=for Pod::Coverage .+

=head1 SYNOPSIS

 use LWP::UserAgent::Plugin 'FilterLcpan' => {
     max_size  => 20*1024*1024,
     #include_author => "PERLANCAR;KUERBIS",
     #exclude_author => "BBB;SPAMMER",
 };

 my $res  = LWP::UserAgent::Plugin->new->mirror("https://cpan.metacpan.org/authors/id/M/MO/MONSTAR/Mojolicious-Plugin-StrictCORS-0.01.tar.gz");


=head1 DESCRIPTION


=head1 CONFIGURATION

=head2 include_author

String (semicolon-separated) or array.

=head2 exclude_author

String (semicolon-separated) or array.

=head2 max_size

Integer.


=head1 SEE ALSO

L<LWP::UserAgent::Plugin>
