package App::lcpan::Cmd::mods;

use 5.010;
use strict;
use warnings;

use Function::Fallback::CoreOrPP qw(clone);

require App::lcpan;

# AUTHORITY
# DATE
# DIST
# VERSION

our %SPEC;

$SPEC{handle_cmd} = do {
    my $spec = clone($App::lcpan::SPEC{modules});
    $spec->{summary} = "Alias for 'modules'";
    $spec;
};
*handle_cmd = \&App::lcpan::modules;

1;
# ABSTRACT:
