package App::lcpan::Cmd::dists_by_dep_count;

# AUTHORITY
# DATE
# DIST
# VERSION

use 5.010;
use strict;
use warnings;

use Function::Fallback::CoreOrPP qw(clone_list);

require App::lcpan;

our %SPEC;

$SPEC{'handle_cmd'} = {
    v => 1.1,
    summary => 'List "heavy" distributions (ranked by number of dependencies)',
    args => {
        %App::lcpan::common_args,
        %App::lcpan::fauthor_args,
        clone_list(%App::lcpan::deps_phase_args),
        clone_list(%App::lcpan::deps_rel_args),
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
    if ($args{author}) {
        push @where, "(author=?)";
        push @binds, $args{author};
    }
    if ($args{phase} && $args{phase} ne 'ALL') {
        push @where, "(phase=?)";
        push @binds, $args{phase};
    }
    if ($args{rel} && $args{rel} ne 'ALL') {
        push @where, "(rel=?)";
        push @binds, $args{rel};
    }
    push @where, "f.is_latest_dist";
    @where = (1) if !@where;

    my $sql = "SELECT
  f.dist_name name,
  f.cpanid author,
  COUNT(DISTINCT dp.file_id) AS dep_count
FROM file f
JOIN dep dp ON dp.file_id=f.id
WHERE ".join(" AND ", @where)."
GROUP BY id
ORDER BY dep_count DESC
";

    my @res;
    my $sth = $dbh->prepare($sql);
    $sth->execute(@binds);
    while (my $row = $sth->fetchrow_hashref) {
        push @res, $row;
    }
    my $resmeta = {};
    $resmeta->{'table.fields'} = [qw/name author dep_count/];
    [200, "OK", \@res, $resmeta];
}

1;
# ABSTRACT:
