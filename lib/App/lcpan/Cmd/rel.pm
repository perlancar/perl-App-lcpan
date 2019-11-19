package App::lcpan::Cmd::rel;

# DATE
# VERSION

use 5.010;
use strict;
use warnings;

use Function::Fallback::CoreOrPP qw(clone);
require App::lcpan::Cmd::release;

our %SPEC;

$SPEC{handle_cmd} = do {
    my $spec = clone($App::lcpan::Cmd::release::SPEC{handle_cmd});
    $spec->{summary} = "Alias for 'release'";
    $spec;
};
*handle_cmd = \&App::lcpan::Cmd::release::handle_cmd;

1;
# ABSTRACT:
