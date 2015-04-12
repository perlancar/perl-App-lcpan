package App::lcpan::Cmd::deps;

# DATE
# VERSION

use 5.010;
use strict;
use warnings;

require App::lcpan;

our %SPEC;

$SPEC{':package'} = {
    v => 1.1,
    summary => "'deps' command",
};

$SPEC{handle_cmd} = $App::lcpan::SPEC{deps};
*handle_cmd = \&App::lcpan::deps;

1;
# ABSTRACT:
