package App::lcpan::Cmd::authordists;

# DATE
# VERSION

use 5.010;
use strict;
use warnings;

require App::lcpan;

our %SPEC;

$SPEC{'handle_cmd'} = {
    v => 1.1,
    summary => 'List distributions of an author',
    args => {
        %App::lcpan::common_args,
        %App::lcpan::author_args,
        %App::lcpan::flatest_args,
        detail => {
            schema => 'bool',
        },
    },
};
sub handle_cmd {
    my %args = @_;

    App::lcpan::dists(%args);
}

1;
# ABSTRACT:
