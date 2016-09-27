package App::lcpan::Cmd::stats_last_index_time;

# DATE
# VERSION

use 5.010;
use strict;
use warnings;

require App::lcpan;

our %SPEC;

$SPEC{handle_cmd} = {
    v => 1.1,
    summary => 'Return last index time of mirror',
    description => <<'_',

This is mostly to support <pm:App::lcpan::Call>. See also `stats` subcommand
which gives a more complete statistics, but can be much slower.

_
    args => {
        %App::lcpan::common_args,
    },
};
sub handle_cmd {
    my %args = @_;

    my $state = App::lcpan::_init(\%args, 'ro');
    my $dbh = $state->{dbh};

    my $stat = {};

    {
        my ($time) = $dbh->selectrow_array("SELECT value FROM meta WHERE name='last_index_time'");
        $stat->{raw_last_index_time} = $time;
        $stat->{last_index_time} = App::lcpan::_fmt_time($time);
    }

    [200, "OK", $stat];
}

1;
# ABSTRACT:
