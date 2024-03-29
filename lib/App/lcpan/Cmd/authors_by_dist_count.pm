package App::lcpan::Cmd::authors_by_dist_count;

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
    summary => 'List authors ranked by number of dists',
    args => {
        %App::lcpan::common_args,
    },
};
sub handle_cmd {
    my %args = @_;

    my $state = App::lcpan::_init(\%args, 'ro');
    my $dbh = $state->{dbh};

    my $sql = "SELECT
  cpanid author,
  COUNT(*) AS dist_count,
  ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM file), 4) dist_count_pct
FROM file f
WHERE f.dist_name IS NOT NULL AND f.is_latest_dist
GROUP BY cpanid
ORDER BY dist_count DESC
";

    my @res;
    my $sth = $dbh->prepare($sql);
    $sth->execute();
    while (my $row = $sth->fetchrow_hashref) {
        push @res, $row;
    }

    require Data::TableData::Rank;
    Data::TableData::Rank::add_rank_column_to_table(table => \@res, data_columns => ['dist_count']);

    my $resmeta = {};
    $resmeta->{'table.fields'} = [qw/rank author dist_count dist_count_pct/];
    [200, "OK", \@res, $resmeta];
}

1;
# ABSTRACT:
