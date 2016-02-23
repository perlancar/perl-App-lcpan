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
        module_authors => {
            'x.name.is_plural' => 1,
            'x.name.singular' => 'module_author',
            schema => ['array*', of=>'str*', min_len=>1],
            tags => ['category:filtering'],
            element_completion => \&App::lcpan::_complete_cpanid,
        },
        module_authors_arent => {
            'x.name.is_plural' => 1,
            'x.name.singular' => 'module_author_isnt',
            schema => ['array*', of=>'str*', min_len=>1],
            tags => ['category:filtering'],
            element_completion => \&App::lcpan::_complete_cpanid,
        },
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

    delete $deps_bdc_args{module_authors};
    $deps_bdc_args{authors} = $args{module_authors};

    delete $deps_bdc_args{module_authors_arent};
    $deps_bdc_args{authors_arent} = $args{module_authors_arent};

    App::lcpan::Cmd::deps_by_dependent_count::handle_cmd(%deps_bdc_args);
}

1;
# ABSTRACT:
