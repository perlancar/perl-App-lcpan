package App::lcpan::Cmd::script;

use 5.010;
use strict;
use warnings;

use Hash::Subset 'hash_subset_without';
require App::lcpan;
require App::lcpan::Cmd::scripts;

# AUTHORITY
# DATE
# DIST
# VERSION

our %SPEC;

$SPEC{handle_cmd} = {
    v => 1.1,
    summary => 'Show a single script',
    args => {
        %App::lcpan::common_args,
        %App::lcpan::script_args,
    },
};
sub handle_cmd {
    my %args = @_;

    App::lcpan::Cmd::scripts::handle_cmd(
        hash_subset_without(\%args, ['script']),
        query => [$args{script}],
        query_type => 'exact-name',
        detail => 1,
    );
}

1;
# ABSTRACT:
