package App::lcpan::Cmd::mods_by_rdep_count;

# DATE
# VERSION

use 5.010;
use strict;
use warnings;

require App::lcpan;

our %SPEC;

$SPEC{':package'} = {
    v => 1.1,
    summary => "'mods-by-rdep-count' command",
};

$SPEC{'handle_cmd'} = {
    v => 1.1,
    summary => 'List modules ranked by number of reverse dependencies',
    args => {
        %App::lcpan::common_args,
        %App::lcpan::fauthor_args,
    },
};
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