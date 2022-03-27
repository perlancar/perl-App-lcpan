package App::lcpan::Cmd::db_path;

use 5.010001;
use strict;
use warnings;

require App::lcpan;

# AUTHORITY
# DATE
# DIST
# VERSION

our %SPEC;

$SPEC{'handle_cmd'} = {
    v => 1.1,
    summary => 'Return database path that is used',
    description => <<'_',

This is a convenience subcommand for use in, e.g. command-line oneliners.

_
    args => {
        %App::lcpan::common_args,
    },
    tags => [],
};
sub handle_cmd {
    my %args = @_;

    my $state = App::lcpan::_init(\%args, 'ro');
    [200, "OK", App::lcpan::_db_path($state->{cpan}, $state->{index_name})];
}

1;
# ABSTRACT:
