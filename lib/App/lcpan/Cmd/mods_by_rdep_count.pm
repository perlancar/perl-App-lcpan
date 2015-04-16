package App::lcpan::Cmd::mods_by_rdep_count;

# DATE
# VERSION

use 5.010;
use strict;
use warnings;

require App::lcpan;

our %SPEC;

$SPEC{'handle_cmd'} = {
    v => 1.1,
    summary => 'List modules ranked by number of reverse dependencies',
    args => {
        %App::lcpan::common_args,
        %App::lcpan::fauthor_args,
        %App::lcpan::deps_phase_arg,
        %App::lcpan::deps_rel_arg,
    },
};
delete $SPEC{'handle_cmd'}{args}{phase}{default};
delete $SPEC{'handle_cmd'}{args}{rel}{default};
sub handle_cmd {
    my %args = @_;

    App::lcpan::_set_args_default(\%args);
    my $cpan = $args{cpan};
    my $index_name = $args{index_name};

    my $dbh = App::lcpan::_connect_db('ro', $cpan, $index_name);

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
    @where = (1) if !@where;

    my $sql = "SELECT
  m.name name,
  m.cpanid author,
  COUNT(*) AS rdep_count
FROM module m
JOIN dep dp ON dp.module_id=m.id
WHERE ".join(" AND ", @where)."
GROUP BY m.name
ORDER BY rdep_count DESC
";

    my @res;
    my $sth = $dbh->prepare($sql);
    $sth->execute(@binds);
    while (my $row = $sth->fetchrow_hashref) {
        push @res, $row;
    }
    my $resmeta = {};
    $resmeta->{format_options} = {any=>{table_column_orders=>[[qw/name author rdep_count/]]}};
    [200, "OK", \@res, $resmeta];
}

1;
# ABSTRACT:
