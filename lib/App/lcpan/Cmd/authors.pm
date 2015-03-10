package App::lcpan::Cmd::authors;

# DATE
# VERSION

use 5.010;
use strict;
use warnings;

require App::lcpan;

our %SPEC;

$SPEC{':package'} = {
    v => 1.1,
    summary => "'authors' command",
};

$SPEC{handle_cmd} = $App::lcpan::SPEC{list_local_cpan_authors};
*handle_cmd = \&App::lcpan::list_local_cpan_authors;

1;
# ABSTRACT:
