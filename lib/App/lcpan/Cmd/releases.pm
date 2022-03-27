package App::lcpan::Cmd::releases;

use 5.010;
use strict;
use warnings;

require App::lcpan;

# AUTHORITY
# DATE
# DIST
# VERSION

our %SPEC;

$SPEC{handle_cmd} = $App::lcpan::SPEC{releases};
*handle_cmd = \&App::lcpan::releases;

1;
# ABSTRACT:
