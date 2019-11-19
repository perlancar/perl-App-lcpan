package App::lcpan::Cmd::release;

# DATE
# VERSION

use 5.010;
use strict;
use warnings;

use Hash::Subset 'hash_subset_without';
require App::lcpan;

our %SPEC;

$SPEC{handle_cmd} = {
    v => 1.1,
    summary => 'Show a single release',
    args => {
        %App::lcpan::common_args,
        %App::lcpan::rel_args,
    },
};
sub handle_cmd {
    my %args = @_;

    App::lcpan::releases(
        hash_subset_without(\%args, ['release']),
        query => [$args{release}],
        query_type => 'exact-name',
        detail => 1,
    );
}

1;
# ABSTRACT:
