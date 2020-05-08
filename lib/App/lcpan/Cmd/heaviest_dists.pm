package App::lcpan::Cmd::heaviest_dists;

# AUTHORITY
# DATE
# DIST
# VERSION

use 5.010;
use strict;
use warnings;

use Function::Fallback::CoreOrPP qw(clone);

require App::lcpan::Cmd::dists_by_dep_count;

our %SPEC;

$SPEC{handle_cmd} = do {
    my $spec = clone($App::lcpan::Cmd::dists_by_dep_count::SPEC{handle_cmd});
    $spec->{summary} = "Alias for 'dists-by-dep-count', with default n=100";
    $spec->{args}{n}{default} = 100;
    $spec;
};
*handle_cmd = \&App::lcpan::Cmd::dists_by_dep_count::handle_cmd;

1;
# ABSTRACT:
