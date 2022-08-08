package App::lcpan::Cmd::author_mods_by_rdep_count;

use 5.010;
use strict;
use warnings;

require App::lcpan;
require App::lcpan::Cmd::mods_by_rdep_count;

# AUTHORITY
# DATE
# DIST
# VERSION

our %SPEC;

$SPEC{'handle_cmd'} = {
    v => 1.1,
    summary => 'List modules of an author sorted by their number of reverse dependencies',
    args => {
        %App::lcpan::common_args,
        %App::lcpan::author_args,
        %App::lcpan::detail_args,
    },
    tags => [],
};
sub handle_cmd {
    my %args = @_;

    App::lcpan::Cmd::mods_by_rdep_count::handle_cmd(%args);
}

1;
# ABSTRACT:
