package App::lcpan::Cmd::stats;

use 5.010;
use strict;
use warnings;

require App::lcpan;

our %SPEC;

$SPEC{':package'} = {
    v => 1.1,
    summary => "'stats' command",
};

$SPEC{handle_cmd} = $App::lcpan::SPEC{stat_local_cpan};
*handle_cmd = \&App::lcpan::stat_local_cpan;

1;
# ABSTRACT:
