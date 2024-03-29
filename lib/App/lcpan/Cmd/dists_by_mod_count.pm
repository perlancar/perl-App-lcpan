package App::lcpan::Cmd::dists_by_mod_count;

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
    summary => 'List distributions ranked by number of included modules',
    args => {
        %App::lcpan::common_args,
        %App::lcpan::fauthor_args,
        n => {
            summary => 'Return at most this number of results',
            schema => 'posint*',
        },
    },
};
sub handle_cmd {
    my %args = @_;

    my $state = App::lcpan::_init(\%args, 'ro');
    my $dbh = $state->{dbh};

    my @where;
    my @binds;
    if ($args{author}) {
        push @where, "(file.author=?)";
        push @binds, $args{author};
    }
    push @where, "file.is_latest_dist";
    @where = (1) if !@where;

    my $sql = "SELECT
  file.dist_name dist,
  file.cpanid author,
  COUNT(DISTINCT module.id) AS mod_count
FROM file
LEFT JOIN module ON file.id=module.file_id
WHERE ".join(" AND ", @where)."
GROUP BY file.id
ORDER BY mod_count DESC
".($args{n} ? "LIMIT ".(0+$args{n}) : "");

    my @res;
    my $sth = $dbh->prepare($sql);
    $sth->execute(@binds);
    while (my $row = $sth->fetchrow_hashref) {
        push @res, $row;
    }

    require Data::TableData::Rank;
    Data::TableData::Rank::add_rank_column_to_table(table => \@res, data_columns => ['mod_count']);

    my $resmeta = {};
    $resmeta->{'table.fields'} = [qw/rank dist author mod_count/];
    [200, "OK", \@res, $resmeta];
}

1;
# ABSTRACT:
