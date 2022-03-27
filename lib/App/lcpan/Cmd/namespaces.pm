package App::lcpan::Cmd::namespaces;

use 5.010;
use strict;
use warnings;

require App::lcpan;

# AUTHORITY
# DATE
# DIST
# VERSION

our %SPEC;

$SPEC{handle_cmd} = $App::lcpan::SPEC{namespaces};
*handle_cmd = \&App::lcpan::namespaces;

1;
# ABSTRACT:
