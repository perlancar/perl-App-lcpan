package App::lcpan::Cmd::modules;

# DATE
# VERSION

use 5.010;
use strict;
use warnings;

require App::lcpan;

our %SPEC;

$SPEC{':package'} = {
    v => 1.1,
    summary => "'modules' command",
};

$SPEC{handle_cmd} = $App::lcpan::SPEC{list_local_cpan_modules};
*handle_cmd = \&App::lcpan::list_local_cpan_modules;

1;
# ABSTRACT:
