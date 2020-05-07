package App::lcpan::Cmd::dist_scripts;

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
    summary => 'List scripts in a distribution',
    args => {
        %App::lcpan::common_args,
        %App::lcpan::dists_args,
        %App::lcpan::detail_args,
    },
};
sub handle_cmd {
    my %args = @_;

    my $state = App::lcpan::_init(\%args, 'ro');
    my $dbh = $state->{dbh};

    my @wheres;
    push @wheres, "file.dist_name IN (".join(",", map {$dbh->quote($_)} @{ $args{dists} }).")";
    my $detail = $args{detail};

    my $sth = $dbh->prepare("SELECT
  script.name name,
  file.dist_name dist,
  script.abstract abstract
FROM script
LEFT JOIN file ON script.file_id=file.id
WHERE ".join(" AND ", @wheres)."
ORDER BY name DESC");
    $sth->execute();
    my @res;
    while (my $row = $sth->fetchrow_hashref) {
        delete $row->{dist} unless @{ $args{dists} } > 1;
        push @res, $detail ? $row : $row->{name};
    }
    my $resmeta = {};
    $resmeta->{'table.fields'} = [qw/name dist abstract/]
        if $detail;
    [200, "OK", \@res, $resmeta];
}

1;
# ABSTRACT:
