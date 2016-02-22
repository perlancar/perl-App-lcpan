package App::lcpan::Cmd::author_rdeps;

# DATE
# VERSION

use 5.010;
use strict;
use warnings;

require App::lcpan;

our %SPEC;

$SPEC{'handle_cmd'} = {
    v => 1.1,
    summary => "Find distributions that use one of author's modules",
    args => {
        %App::lcpan::common_args,
        %App::lcpan::author_args,
        %App::lcpan::rdeps_rel_arg,
        %App::lcpan::rdeps_phase_arg,
        user_authors => {
            'x.name.is_plural' => 1,
            'x.name.singular' => 'user_author',
            schema => ['array*', of=>'str*'],
            element_completion => \&App::lcpan::_complete_cpanid,
        },
        user_authors_arent => {
            'x.name.is_plural' => 1,
            'x.name.singular' => 'user_author_isnt',
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
    my %rdeps_args = %args;
    $rdeps_args{modules} = $mods;
    delete $rdeps_args{authors};
    delete $rdeps_args{authors_arent};
    $rdeps_args{authors} = $args{user_authors};
    $rdeps_args{authors_arent} = $args{user_authors_arent};
    $rdeps_args{phase} = $args{phase};
    $rdeps_args{rel} = $args{rel};
    $res = App::lcpan::rdeps(%rdeps_args);
    return $res if $res->[0] != 200;

    $res;
}

1;
# ABSTRACT:
