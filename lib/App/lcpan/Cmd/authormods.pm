package App::lcpan::Cmd::authormods;

# DATE
# VERSION

use 5.010;
use strict;
use warnings;

require App::lcpan;

our %SPEC;

$SPEC{':package'} = {
    v => 1.1,
    summary => "'authormods' command",
};

$SPEC{'handle_cmd'} = {
    v => 1.1,
    summary => 'List modules of an author',
    args => {
        %App::lcpan::common_args,
        %App::lcpan::author_args,
        detail => {
            schema => 'bool',
        },
    },
};
sub handle_cmd {
    my %args = @_;

    App::lcpan::modules(%args);
}

1;
# ABSTRACT:
