package App::lcpan::Cmd::author_deps;

# DATE
# VERSION

use 5.010;
use strict;
use warnings;

require App::lcpan;

our %SPEC;

$SPEC{'handle_cmd'} = {
    v => 1.1,
    summary => "List dependencies for all of the dists of an author",
    args => {
        %App::lcpan::common_args,
        %App::lcpan::author_args,
        %App::lcpan::deps_args,
        module_authors => {
            summary => 'Only list depended modules published by specified author(s)',
            'x.name.is_plural' => 1,
            schema => ['array*', of=>'str*'],
            element_completion => \&App::lcpan::_complete_cpanid,
        },
        module_authors_arent => {
            summary => 'Do not list depended modules published by specified author(s)',
            'x.name.is_plural' => 1,
            'x.name.singular' => 'module_author_isnt',
            schema => ['array*', of=>'str*'],
            element_completion => \&App::lcpan::_complete_cpanid,
        },
    },
};
sub handle_cmd {
    my %args = @_;

    my $author = $args{author};

    my $res = App::lcpan::modules(%args, author=>$author);
    return $res if $res->[0] != 200;
    my $mods = $res->[2];

    my %deps_args = %args;
    $deps_args{modules} = $mods;
    delete $deps_args{authors};
    delete $deps_args{authors_arent};
    $deps_args{authors} = $args{module_authors};
    $deps_args{authors_arent} = $args{module_authors_arent};
    $deps_args{phase} = $args{phase};
    $deps_args{rel} = $args{rel};
    $res = App::lcpan::deps(%deps_args);
    return $res if $res->[0] != 200;

    $res;
}

1;
# ABSTRACT:
