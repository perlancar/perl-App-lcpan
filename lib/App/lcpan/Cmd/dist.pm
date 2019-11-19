package App::lcpan::Cmd::dist;

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
    summary => 'Show a single distribution',
    args => {
        %App::lcpan::common_args,
        %App::lcpan::dist_args,
    },
};
sub handle_cmd {
    my %args = @_;

    App::lcpan::dists(
        hash_subset_without(\%args, ['dist']),
        query => [$args{dist}],
        query_type => 'exact-name',
        detail => 1,
    );
}

1;
# ABSTRACT:
