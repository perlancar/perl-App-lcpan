package App::lcpan::Cmd::author;

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
    summary => 'Show a single author',
    args => {
        %App::lcpan::common_args,
        %App::lcpan::author_args,
    },
};
sub handle_cmd {
    my %args = @_;

    App::lcpan::authors(
        hash_subset_without(\%args, ['author']),
        query => [$args{author}],
        query_type => 'exact-cpanid',
        detail => 1,
    );
}

1;
# ABSTRACT:
