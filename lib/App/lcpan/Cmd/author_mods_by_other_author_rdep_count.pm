package App::lcpan::Cmd::author_mods_by_other_author_rdep_count;

use 5.010;
use strict;
use warnings;

require App::lcpan;
require App::lcpan::Cmd::mods_by_rdep_count;

# AUTHORITY
# DATE
# DIST
# VERSION

our %SPEC;

$SPEC{'handle_cmd'} = {
    v => 1.1,
    summary => 'List modules of an author sorted by their number of reverse dependencies from other authors',
    args => {
        %App::lcpan::common_args,
        %App::lcpan::author_args,
        %App::lcpan::detail_args,
    },
    tags => [],
};
sub handle_cmd {
    my %args = @_;

    my $author = delete $args{author};
    $args{module_authors} = [$author];
    $args{dist_authors_arent} = [$author];
    App::lcpan::Cmd::mods_by_rdep_count::handle_cmd(%args);
}

1;
# ABSTRACT:
