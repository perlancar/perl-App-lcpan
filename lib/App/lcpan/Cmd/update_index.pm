package App::lcpan::Cmd::update_index;

# DATE
# VERSION

use 5.010;
use strict;
use warnings;

require App::lcpan;

our %SPEC;

$SPEC{':package'} = {
    v => 1.1,
    summary => "'update-index' command",
};

$SPEC{handle_cmd} = $App::lcpan::SPEC{update_index};
*handle_cmd = \&App::lcpan::update_index;

1;
# ABSTRACT:
