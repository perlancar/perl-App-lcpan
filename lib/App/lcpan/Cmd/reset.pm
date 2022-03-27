package App::lcpan::Cmd::reset;

use 5.010;
use strict;
use warnings;

require App::lcpan;

# AUTHORITY
# DATE
# DIST
# VERSION

our %SPEC;

$SPEC{handle_cmd} = $App::lcpan::SPEC{reset};
*handle_cmd = \&App::lcpan::reset;

1;
# ABSTRACT:
