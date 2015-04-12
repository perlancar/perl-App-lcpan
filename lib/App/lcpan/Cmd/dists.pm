package App::lcpan::Cmd::dists;

# DATE
# VERSION

use 5.010;
use strict;
use warnings;

require App::lcpan;

our %SPEC;

$SPEC{':package'} = {
    v => 1.1,
    summary => "'dists' command",
};

$SPEC{handle_cmd} = $App::lcpan::SPEC{dists};
*handle_cmd = \&App::lcpan::dists;

1;
# ABSTRACT:
