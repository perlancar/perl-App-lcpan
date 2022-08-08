package App::lcpan::Cmd::mods_by_rdep_count;

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
    summary => 'List "most depended modules" (modules ranked by number of reverse dependencies)',
    args => {
        %App::lcpan::common_args,
        clone_list(%App::lcpan::deps_phase_args),
        clone_list(%App::lcpan::deps_rel_args),
        n => {
            summary => 'Return at most this number of results',
            schema => 'posint*',
        },
        %App::lcpan::argspecsopt_module_authors,
        %App::lcpan::argspecsopt_dist_authors,
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
    if ($args{module_authors} && @{ $args{module_authors} }) {
        push @where, "(author IN (".join(", ", map {$dbh->quote($_)} @{ $args{module_authors} })."))";
    }
    if ($args{module_authors_arent} && @{ $args{module_authors_arent} }) {
        push @where, "(author NOT IN (".join(", ", map {$dbh->quote($_)} @{ $args{module_authors_arent} })."))";
    }
    if ($args{dist_authors} && @{ $args{dist_authors} }) {
        push @where, "(f.cpanid IN (".join(", ", map {$dbh->quote($_)} @{ $args{dist_authors} })."))";
    }
    if ($args{dist_authors_arent} && @{ $args{dist_authors_arent} }) {
        push @where, "(f.cpanid NOT IN (".join(", ", map {$dbh->quote($_)} @{ $args{dist_authors_arent} })."))";
    }
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
  COUNT(*) AS rdep_count
FROM module m
JOIN dep dp ON m.id=dp.module_id
LEFT JOIN file f ON dp.file_id=f.id
WHERE ".join(" AND ", @where)."
GROUP BY m.name
ORDER BY rdep_count DESC
".($args{n} ? " LIMIT ".(0+$args{n}) : "");

    my @res;
    my $sth = $dbh->prepare($sql);
    $sth->execute(@binds);
    while (my $row = $sth->fetchrow_hashref) {
        push @res, $row;
    }

    require Data::TableData::Rank;
    Data::TableData::Rank::add_rank_column_to_table(table => \@res, data_columns => ['rdep_count']);

    my $resmeta = {};
    $resmeta->{'table.fields'} = [qw/rank module author rdep_count/];
    [200, "OK", \@res, $resmeta];
}

1;
# ABSTRACT:
