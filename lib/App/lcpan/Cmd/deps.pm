package App::lcpan::Cmd::deps;

use 5.010;
use strict;
use warnings;

require App::lcpan;

# AUTHORITY
# DATE
# DIST
# VERSION

our %SPEC;

$SPEC{handle_cmd} = $App::lcpan::SPEC{deps};
*handle_cmd = \&App::lcpan::deps;

1;
# ABSTRACT:
