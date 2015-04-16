package App::lcpan::Cmd::authorrdeps;

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
        #detail => {
        #    schema => 'bool',
        #},
        user_author => {
            schema => ['array*', of=>'str*'],
        },
        user_author_isnt => {
            schema => ['array*', of=>'str*'],
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
    delete $rdeps_args{author};
    delete $rdeps_args{author_isnt};
    $rdeps_args{author} = $args{user_author};
    $rdeps_args{author_isnt} = $args{user_author_isnt};
    $res = App::lcpan::rdeps(%rdeps_args);
    return $res if $res->[0] != 200;

    $res;
}

1;
# ABSTRACT:
