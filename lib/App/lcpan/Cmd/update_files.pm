package App::lcpan::Cmd::update_files;

use 5.010;
use strict;
use warnings;

require App::lcpan;

our %SPEC;

$SPEC{':package'} = {
    v => 1.1,
    summary => "'update-files' command",
};

$SPEC{handle_cmd} = $App::lcpan::SPEC{update_local_cpan_files};
*handle_cmd = \&App::lcpan::update_local_cpan_files;

1;
# ABSTRACT:
