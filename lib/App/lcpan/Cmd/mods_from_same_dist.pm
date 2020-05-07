package App::lcpan::Cmd::mods_from_same_dist;

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
    summary => 'Given a module, list all modules in the same distribution',
    args => {
        %App::lcpan::common_args,
        %App::lcpan::mods_args,
        %App::lcpan::flatest_args,
        %App::lcpan::detail_args,
    },
};
sub handle_cmd {
    my %args = @_;

    my $state = App::lcpan::_init(\%args, 'ro');
    my $dbh = $state->{dbh};

    my $detail = $args{detail};

    my $emods = join(",", map {$dbh->quote($_)} @{ $args{modules} });
    my @where;
    push @where, "f.id IN (SELECT file_id FROM module WHERE name IN ($emods))";
    if ($args{latest}) {
        push @where, "f.is_latest_dist";
    } elsif (defined $args{latest}) {
        push @where, "NOT(f.is_latest_dist)";
    }
    my $sth = $dbh->prepare("SELECT
  module.name name,
  module.version version,
  module.abstract abstract,
  f.dist_name dist,
  f.dist_version dist_version
FROM module
JOIN file f ON module.file_id=f.id
WHERE ".join(" AND ", @where)."
ORDER BY name DESC");
    $sth->execute;
    my @res;
    while (my $row = $sth->fetchrow_hashref) {
        push @res, $detail ? $row : $row->{name};
    }
    my $resmeta = {};
    $resmeta->{'table.fields'} = [qw/name version abstract dist dist_version/]
        if $detail;
    [200, "OK", \@res, $resmeta];
}

1;
# ABSTRACT:
