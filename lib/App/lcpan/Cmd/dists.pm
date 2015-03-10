package App::lcpan::Cmd::dists;

use 5.010;
use strict;
use warnings;

require App::lcpan;

our %SPEC;

$SPEC{':package'} = {
    v => 1.1,
    summary => "'dists' command",
};

$SPEC{handle_cmd} = $App::lcpan::SPEC{list_local_cpan_dists};
*handle_cmd = \&App::lcpan::list_local_cpan_dists;

1;
# ABSTRACT:
