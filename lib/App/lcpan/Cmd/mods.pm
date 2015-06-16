package App::lcpan::Cmd::mods;

# DATE
# VERSION

use 5.010;
use strict;
use warnings;

use Function::Fallback::CoreOrPP qw(clone);

require App::lcpan;

our %SPEC;

$SPEC{handle_cmd} = do {
    my $spec = clone($App::lcpan::SPEC{modules});
    $spec->{summary} = "Alias for 'modules'";
    $spec;
};
*handle_cmd = \&App::lcpan::modules;

1;
# ABSTRACT:
