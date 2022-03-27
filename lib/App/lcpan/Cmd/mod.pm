package App::lcpan::Cmd::mod;

use 5.010;
use strict;
use warnings;

use Function::Fallback::CoreOrPP qw(clone);
require App::lcpan::Cmd::module;

# AUTHORITY
# DATE
# DIST
# VERSION

our %SPEC;

$SPEC{handle_cmd} = do {
    my $spec = clone($App::lcpan::Cmd::module::SPEC{handle_cmd});
    $spec->{summary} = "Alias for 'module'";
    $spec;
};
*handle_cmd = \&App::lcpan::Cmd::module::handle_cmd;

1;
# ABSTRACT:
