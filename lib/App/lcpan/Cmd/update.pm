package App::lcpan::Cmd::update;

# DATE
# VERSION

use 5.010;
use strict;
use warnings;

require App::lcpan;

our %SPEC;

$SPEC{handle_cmd} = $App::lcpan::SPEC{update};
*handle_cmd = \&App::lcpan::update;

1;
# ABSTRACT:
