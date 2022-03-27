package App::lcpan::Cmd::stats;

use 5.010;
use strict;
use warnings;

require App::lcpan;

# AUTHORITY
# DATE
# DIST
# VERSION

our %SPEC;

$SPEC{handle_cmd} = $App::lcpan::SPEC{stats};
*handle_cmd = \&App::lcpan::stats;

1;
# ABSTRACT:
