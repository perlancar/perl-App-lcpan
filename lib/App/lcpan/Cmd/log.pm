package App::lcpan::Cmd::log;

use 5.010;
use strict;
use warnings;

require App::lcpan;

# AUTHORITY
# DATE
# DIST
# VERSION

our %SPEC;

$SPEC{handle_cmd} = $App::lcpan::SPEC{log};
*handle_cmd = \&App::lcpan::log;

1;
# ABSTRACT:
