package App::lcpan::Cmd::authors;

use 5.010;
use strict;
use warnings;

require App::lcpan;

# AUTHORITY
# DATE
# DIST
# VERSION

our %SPEC;

$SPEC{handle_cmd} = $App::lcpan::SPEC{authors};
*handle_cmd = \&App::lcpan::authors;

1;
# ABSTRACT:
