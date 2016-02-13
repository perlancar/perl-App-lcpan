package App::lcpan::Cmd::author_rels;

# DATE
# VERSION

use 5.010;
use strict;
use warnings;

require App::lcpan;

our %SPEC;

$SPEC{'handle_cmd'} = {
    v => 1.1,
    summary => 'List releases of an author',
    args => {
        %App::lcpan::common_args,
        %App::lcpan::author_args,
        %App::lcpan::flatest_args,
        %App::lcpan::full_path_args,
        %App::lcpan::detail_args,
        %App::lcpan::sort_args_for_rels,
    },
};
sub handle_cmd {
    my %args = @_;

    $args{no_path} = 1 unless $args{full_path};
    App::lcpan::releases(%args);
}

1;
# ABSTRACT:
