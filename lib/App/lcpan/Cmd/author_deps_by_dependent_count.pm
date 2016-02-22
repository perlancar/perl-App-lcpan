package App::lcpan::Cmd::author_deps_by_dependent_count;

# DATE
# VERSION

use 5.010;
use strict;
use warnings;

require App::lcpan;
require App::lcpan::Cmd::deps_by_dependent_count;

our %SPEC;

my $deps_bdc_args = $App::lcpan::Cmd::deps_by_dependent_count::SPEC{handle_cmd}{args};

$SPEC{'handle_cmd'} = {
    v => 1.1,
    summary => 'List all dependencies of dists of an author, sorted by number of dependent dists',
    args => {
        (map {$_ => $deps_bdc_args->{$_}}
             grep {$_ ne 'modules'} keys %$deps_bdc_args),
        %App::lcpan::author_args,
    },
    tags => [],
};
sub handle_cmd {
    my %args = @_;

    my $res = App::lcpan::modules(%args);
    return $res if $res->[0] != 200;

    my %deps_bdc_args = %args;
    delete $deps_bdc_args{author};
    $deps_bdc_args{modules} = $res->[2];
    App::lcpan::Cmd::deps_by_dependent_count::handle_cmd(%deps_bdc_args);
}

1;
# ABSTRACT:
