package App::lcpan::Cmd::rdeps;

# DATE
# VERSION

use 5.010;
use strict;
use warnings;

require App::lcpan;

our %SPEC;

$SPEC{handle_cmd} = $App::lcpan::SPEC{rdeps};
*handle_cmd = \&App::lcpan::rdeps;

1;
# ABSTRACT:
