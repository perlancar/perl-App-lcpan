package App::lcpan::Cmd::author_mods;

use 5.010;
use strict;
use warnings;

require App::lcpan;

# AUTHORITY
# DATE
# DIST
# VERSION

our %SPEC;

$SPEC{'handle_cmd'} = {
    v => 1.1,
    summary => 'List modules of an author',
    args => {
        %App::lcpan::common_args,
        %App::lcpan::author_args,
        %App::lcpan::detail_args,
    },
    tags => [],
};
sub handle_cmd {
    my %args = @_;

    App::lcpan::modules(%args);
}

1;
# ABSTRACT:
