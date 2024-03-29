package App::lcpan::Cmd::mods_by_rdep_author_count;

use 5.010;
use strict;
use warnings;

use Function::Fallback::CoreOrPP qw(clone_list);

require App::lcpan;

# AUTHORITY
# DATE
# DIST
# VERSION

our %SPEC;

$SPEC{'handle_cmd'} = {
    v => 1.1,
    summary => 'List modules depended "by most number of authors" (modules ranked by number of authors that have dists that depend on the module)',
    args => {
        %App::lcpan::common_args,
        clone_list(%App::lcpan::deps_phase_args),
        clone_list(%App::lcpan::deps_rel_args),
        n => {
            summary => 'Return at most this number of results',
            schema => 'posint*',
        },
    },
};
delete $SPEC{'handle_cmd'}{args}{phase}{default};
delete $SPEC{'handle_cmd'}{args}{rel}{default};
sub handle_cmd {
    my %args = @_;

    my $state = App::lcpan::_init(\%args, 'ro');
    my $dbh = $state->{dbh};

    my @where;
    my @binds;
    if ($args{phase} && $args{phase} ne 'ALL') {
        push @where, "(phase=?)";
        push @binds, $args{phase};
    }
    if ($args{rel} && $args{rel} ne 'ALL') {
        push @where, "(rel=?)";
        push @binds, $args{rel};
    }
    @where = (1) if !@where;

    my $sql = "SELECT
  m.name module,
  m.cpanid author,
  COUNT(DISTINCT f.cpanid) AS rdep_author_count
FROM module m
JOIN dep dp ON dp.module_id=m.id
LEFT JOIN file f ON dp.file_id=f.id
WHERE ".join(" AND ", @where)."
GROUP BY m.name
ORDER BY rdep_author_count DESC
".($args{n} ? " LIMIT ".(0+$args{n}) : "");

    my @res;
    my $sth = $dbh->prepare($sql);
    $sth->execute(@binds);
    while (my $row = $sth->fetchrow_hashref) {
        push @res, $row;
    }

    require Data::TableData::Rank;
    Data::TableData::Rank::add_rank_column_to_table(table => \@res, data_columns => ['rdep_author_count']);

    my $resmeta = {};
    $resmeta->{'table.fields'} = [qw/rank module author rdep_author_count/];
    [200, "OK", \@res, $resmeta];
}

1;
# ABSTRACT:
