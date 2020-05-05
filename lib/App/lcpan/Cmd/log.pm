package App::lcpan::Cmd::log;

# AUTHORITY
# DATE
# DIST
# VERSION

use 5.010;
use strict;
use warnings;

require App::lcpan;

our %SPEC;

$SPEC{handle_cmd} = $App::lcpan::SPEC{log};
*handle_cmd = \&App::lcpan::log;

1;
# ABSTRACT:
