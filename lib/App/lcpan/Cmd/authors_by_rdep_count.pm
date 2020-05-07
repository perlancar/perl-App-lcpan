package App::lcpan::Cmd::authors_by_rdep_count;

# DATE
# VERSION

use 5.010;
use strict;
use warnings;

use Function::Fallback::CoreOrPP qw(clone_list);

require App::lcpan;

our %SPEC;

$SPEC{'handle_cmd'} = {
    v => 1.1,
    summary => 'List authors ranked by number of distributions using one of his/her modules',
    args => {
        %App::lcpan::common_args,
        clone_list(%App::lcpan::deps_phase_args),
        clone_list(%App::lcpan::deps_rel_args),
        exclude_same_author => {
            schema => 'bool',
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
    push @where, "f.is_latest_dist";
    push @where, "f.cpanid <> m.cpanid" if $args{exclude_same_author};
    @where = (1) if !@where;

    my $sql = "SELECT
  m.cpanid id,
  a.fullname name,
  COUNT(DISTINCT f.id) AS rdep_count
FROM module m
JOIN dep dp ON dp.module_id=m.id
LEFT JOIN author a ON a.cpanid=m.cpanid
LEFT JOIN file f ON f.id=dp.file_id
WHERE ".join(" AND ", @where)."
GROUP BY m.cpanid
ORDER BY rdep_count DESC
";

    my @res;
    my $sth = $dbh->prepare($sql);
    $sth->execute(@binds);
    while (my $row = $sth->fetchrow_hashref) {
        push @res, $row;
    }
    my $resmeta = {};
    $resmeta->{'table.fields'} = [qw/id name rdep_count/];
    [200, "OK", \@res, $resmeta];
}

1;
# ABSTRACT:
