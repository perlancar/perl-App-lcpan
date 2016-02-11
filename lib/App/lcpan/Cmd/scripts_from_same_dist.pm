package App::lcpan::Cmd::scripts_from_same_dist;

# DATE
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
    push @where, "dist.name IN (SELECT name FROM dist WHERE file_id IN (SELECT file_id FROM script WHERE name IN ($escripts)))";
    if ($args{latest}) {
        push @where, "dist.is_latest";
    } elsif (defined $args{latest}) {
        push @where, "NOT(dist.is_latest)";
    }
    my $sth = $dbh->prepare("SELECT
  script.name name,
  dist.name dist,
  dist.version dist_version
FROM script
JOIN dist ON script.file_id=dist.file_id
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
