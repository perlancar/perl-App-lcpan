package App::lcpan::Cmd::update_files;

# DATE
# VERSION

use 5.010;
use strict;
use warnings;

require App::lcpan;

our %SPEC;

$SPEC{':package'} = {
    v => 1.1,
    summary => "'update-files' command",
};

$SPEC{handle_cmd} = $App::lcpan::SPEC{update_files};
*handle_cmd = \&App::lcpan::update_files;

1;
# ABSTRACT:
