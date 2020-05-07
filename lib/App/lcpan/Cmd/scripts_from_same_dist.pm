package App::lcpan::Cmd::scripts_from_same_dist;

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
    summary => 'Given a script, list all scripts in the same distribution',
    args => {
        %App::lcpan::common_args,
        %App::lcpan::scripts_args,
        %App::lcpan::flatest_args,
        %App::lcpan::detail_args,
    },
};
sub handle_cmd {
    my %args = @_;

    my $state = App::lcpan::_init(\%args, 'ro');
    my $dbh = $state->{dbh};

    my $detail = $args{detail};

    my $escripts = join(",", map {$dbh->quote($_)} @{ $args{scripts} });
    my @where;
    push @where, "f1.dist_name IN (SELECT dist_name FROM file f2 WHERE id IN (SELECT file_id FROM script WHERE name IN ($escripts)))";
    if ($args{latest}) {
        push @where, "f1.is_latest_dist";
    } elsif (defined $args{latest}) {
        push @where, "NOT(f1.is_latest_dist)";
    }
    my $sth = $dbh->prepare("SELECT
  script.name name,
  f1.dist_name dist,
  f1.dist_version dist_version
FROM script
JOIN file f1 ON script.file_id=f1.id
WHERE ".join(" AND ", @where)."
ORDER BY name DESC");
    $sth->execute;
    my @res;
    while (my $row = $sth->fetchrow_hashref) {
        push @res, $detail ? $row : $row->{name};
    }
    my $resmeta = {};
    $resmeta->{'table.fields'} = [qw/name dist dist_version/]
        if $detail;
    [200, "OK", \@res, $resmeta];
}

1;
# ABSTRACT:
