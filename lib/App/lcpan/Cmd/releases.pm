package App::lcpan::Cmd::releases;

# DATE
# VERSION

use 5.010;
use strict;
use warnings;

require App::lcpan;

our %SPEC;

$SPEC{':package'} = {
    v => 1.1,
    summary => "'releases' command",
};

$SPEC{handle_cmd} = $App::lcpan::SPEC{list_local_cpan_releases};
*handle_cmd = \&App::lcpan::list_local_cpan_releases;

1;
# ABSTRACT:
