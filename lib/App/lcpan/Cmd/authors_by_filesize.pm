package App::lcpan::Cmd::authors_by_filesize;

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
    summary => 'List authors ranked by total size of their indexed releases',
    args => {
        %App::lcpan::common_args,
    },
};
sub handle_cmd {
    my %args = @_;

    my $state = App::lcpan::_init(\%args, 'ro');
    my $dbh = $state->{dbh};

    # doesn't work if put as subselect
    my ($total_filesize) = $dbh->selectrow_array("");

    my $sql = "SELECT
  file.cpanid author,
  SUM(size) AS filesize,
  ROUND(100.0 * SUM(size) / (SELECT SUM(size) FROM file), 4) AS filesize_pct,
  COUNT(*) rel_count
FROM file
GROUP BY file.cpanid
ORDER BY filesize DESC
";

    my @res;
    my $sth = $dbh->prepare($sql);
    $sth->execute();
    while (my $row = $sth->fetchrow_hashref) {
        push @res, $row;
    }

    require Data::TableData::Rank;
    Data::TableData::Rank::add_rank_column_to_table(table => \@res, data_columns => ['filesize']);

    my $resmeta = {};
    $resmeta->{'table.fields'} = [qw/rank author filesize rel_count filesize_pct/];
    [200, "OK", \@res, $resmeta];
}

1;
# ABSTRACT:
