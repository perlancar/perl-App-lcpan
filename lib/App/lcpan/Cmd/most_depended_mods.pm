package App::lcpan::Cmd::most_depended_mods;

# AUTHORITY
# DATE
# DIST
# VERSION

use 5.010;
use strict;
use warnings;

use Function::Fallback::CoreOrPP qw(clone);

require App::lcpan::Cmd::mods_by_rdep_count;

our %SPEC;

$SPEC{handle_cmd} = do {
    my $spec = clone($App::lcpan::Cmd::mods_by_rdep_count::SPEC{handle_cmd});
    $spec->{summary} = "Alias for 'mods-by-rdep-count', with default n=100";
    $spec->{args}{n}{default} = 100;
    $spec;
};
*handle_cmd = \&App::lcpan::Cmd::mods_by_rdep_count::handle_cmd;

1;
# ABSTRACT:
