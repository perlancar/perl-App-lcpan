package App::lcpan::Cmd::subnames_by_count;

use 5.010;
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
    summary => 'List subroutine names ranked by number of occurrences',
    description => <<'_',

_
    args => {
        %App::lcpan::common_args,
        # XXX include_method
        # XXX include_static_method
        # XXX include_function
        #packages => {
        #    'x.name.is_plural' => 1,
        #    summary => 'Filter by package name(s)',
        #    schema => ['array*', of=>'str*', min_len=>1],
        #    element_completion => \&App::lcpan::_complete_mod,
        #    tags => ['category:filtering'],
        #},
        #authors => {
        #    'x.name.is_plural' => 1,
        #    summary => 'Filter by author(s) of module',
        #    schema => ['array*', of=>'str*', min_len=>1],
        #    element_completion => \&App::lcpan::_complete_cpanid,
        #    tags => ['category:filtering'],
        #},
    },
};
sub handle_cmd {
    my %args = @_;

    my $state = App::lcpan::_init(\%args, 'ro');
    my $dbh = $state->{dbh};

    my $sql = "SELECT
  name sub,
  COUNT(name) count
FROM sub
GROUP BY name
ORDER BY COUNT(name) DESC";

    my @res;
    my $sth = $dbh->prepare($sql);
    $sth->execute;
    while (my $row = $sth->fetchrow_hashref) {
        push @res, $row;
    }

    require Data::TableData::Rank;
    Data::TableData::Rank::add_rank_column_to_table(table => \@res, data_columns => ['count']);

    my $resmeta = {};
    $resmeta->{'table.fields'} = [qw/rank sub count/];

    [200, "OK", \@res, $resmeta];
}

1;
# ABSTRACT:
