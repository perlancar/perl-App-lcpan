package LWP::UserAgent::Patch::FilterLcpan;

# DATE
# VERSION

use 5.010001;
use strict;
no warnings;

use HTTP::Response;
use Module::Patch 0.12 qw();
use base qw(Module::Patch);

our %config;

my $p_mirror = sub {
    use experimental 'smartmatch';

    my $ctx  = shift;
    my $orig = $ctx->{orig};

    my ($self, $url, $file) = @_;

    state $include_author;
    state $exclude_author;

  FILTER:
    {
        if ($config{-include_author}) {
            if (!$include_author) {
                $include_author = [split /;/, $config{-include_author}];
            }
            if ($url =~ m!authors/id/./../(.+)/! && !($1 ~~ @$include_author)) {
                say "mirror($url, $file): author not included, skipping"
                    if $config{-verbose};
                return HTTP::Response->new(304);
            }
        }

        if ($config{-exclude_author}) {
            if (!$exclude_author) {
                $exclude_author = [split /;/, $config{-exclude_author}];
            }
            if ($url =~ m!authors/id/./../(.+)/! && $1 ~~ @$exclude_author) {
                say "mirror($url, $file): author excluded, skipping"
                    if $config{-verbose};
                return HTTP::Response->new(304);
            }
        }

        if (my $limit = $config{-size}) {
            my $size = (-s $file);
            if ($size && $size > $limit) {
                say "mirror($url, $file): local size ($size) > limit ($limit), skipping"
                    if $config{-verbose};
                return HTTP::Response->new(304);
            }

            # perform HEAD request to find out the size
            my $resp = $self->head($url);

            {
                last unless $resp->is_success;
                last unless defined(my $len = $resp->header("Content-Length"));
                if ($len > $limit) {
                    say "mirror($url, $file): remote size ($len) > limit ($limit), skipping"
                        if $config{-verbose};
                    return HTTP::Response->new(304);
                }
            }
        }
    }
    return $orig->(@_);
};

sub patch_data {
    return {
        v => 3,
        config => {
            -size => {
                schema => 'int*',
            },
            -exclude_author => {
                schema => 'str*',
            },
            -include_author => {
                schema => 'str*',
            },
            -verbose => {
                schema  => 'bool*',
                default => 0,
            },
        },
        patches => [
            {
                action => 'wrap',
                mod_version => qr/^6\./,
                sub_name => 'mirror',
                code => $p_mirror,
            },
        ],
    };
}

1;
# ABSTRACT: Filter mirror()

=cut
