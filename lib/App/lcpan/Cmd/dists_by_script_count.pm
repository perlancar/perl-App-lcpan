package App::lcpan::Cmd::dists_by_script_count;

# AUTHORITY
# DATE
# DIST
# VERSION

use 5.010;
use strict;
use warnings;

require App::lcpan;

our %SPEC;

$SPEC{'handle_cmd'} = {
    v => 1.1,
    summary => 'List distributions ranked by number of included scripts',
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
  COUNT(DISTINCT script.id) AS script_count
FROM file
LEFT JOIN script ON file.id=script.file_id
WHERE ".join(" AND ", @where)."
GROUP BY file.id
ORDER BY script_count DESC
".($args{n} ? "LIMIT ".(0+$args{n}) : "");

    my @res;
    my $sth = $dbh->prepare($sql);
    $sth->execute(@binds);
    while (my $row = $sth->fetchrow_hashref) {
        push @res, $row;
    }
    my $resmeta = {};
    $resmeta->{'table.fields'} = [qw/dist author script_count/];
    [200, "OK", \@res, $resmeta];
}

1;
# ABSTRACT:
