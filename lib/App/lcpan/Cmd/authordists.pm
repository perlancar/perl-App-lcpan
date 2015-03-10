package App::lcpan::Cmd::authordists;

use 5.010;
use strict;
use warnings;

require App::lcpan;

our %SPEC;

$SPEC{':package'} = {
    v => 1.1,
    summary => "'authordists' command",
};

$SPEC{'handle_cmd'} = {
    v => 1.1,
    summary => 'List distributions of an author',
    args => {
        %App::lcpan::common_args,
        %App::lcpan::author_args,
        %App::lcpan::flatest_args,
    },
    result_naked=>1,
};
sub handle_cmd {
    my %args = @_;

    App::lcpan::list_local_cpan_dists(%args);
}

1;
# ABSTRACT:
