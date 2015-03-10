package App::lcpan::Cmd::authormods;

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
    },
    result_naked=>1,
};
sub handle_cmd {
    my %args = @_;

    App::lcpan::list_local_cpan_modules(%args);
}

1;
# ABSTRACT:
