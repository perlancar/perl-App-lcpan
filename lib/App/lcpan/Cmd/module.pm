package App::lcpan::Cmd::module;

use 5.010;
use strict;
use warnings;

use Hash::Subset 'hash_subset_without';
require App::lcpan;

# AUTHORITY
# DATE
# DIST
# VERSION

our %SPEC;

$SPEC{handle_cmd} = {
    v => 1.1,
    summary => 'Show a single module',
    args => {
        %App::lcpan::common_args,
        %App::lcpan::mod_args,
    },
};
sub handle_cmd {
    my %args = @_;

    App::lcpan::modules(
        hash_subset_without(\%args, ['module']),
        query => [$args{module}],
        query_type => 'exact-name',
        detail => 1,
    );
}

1;
# ABSTRACT:
