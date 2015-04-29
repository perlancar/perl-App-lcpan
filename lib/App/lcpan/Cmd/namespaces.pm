package App::lcpan::Cmd::namespaces;

# DATE
# VERSION

use 5.010;
use strict;
use warnings;

require App::lcpan;

our %SPEC;

$SPEC{handle_cmd} = $App::lcpan::SPEC{namespaces};
*handle_cmd = \&App::lcpan::namespaces;

1;
# ABSTRACT:
