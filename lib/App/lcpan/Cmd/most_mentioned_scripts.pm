package App::lcpan::Cmd::most_mentioned_scripts;

# AUTHORITY
# DATE
# DIST
# VERSION

use 5.010;
use strict;
use warnings;

use Function::Fallback::CoreOrPP qw(clone);

require App::lcpan::Cmd::scripts_by_mention_count;

our %SPEC;

$SPEC{handle_cmd} = do {
    my $spec = clone($App::lcpan::Cmd::scripts_by_mention_count::SPEC{handle_cmd});
    $spec->{summary} = "Alias for 'scripts-by-mention-count', with default n=100";
    $spec->{args}{n}{default} = 100;
    $spec;
};
*handle_cmd = \&App::lcpan::Cmd::scripts_by_mention_count::handle_cmd;

1;
# ABSTRACT:
