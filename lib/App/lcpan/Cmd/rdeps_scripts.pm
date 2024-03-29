package App::lcpan::Cmd::rdeps_scripts;

use 5.010001;
use strict;
use warnings;

require App::lcpan;

# AUTHORITY
# DATE
# DIST
# VERSION

our %SPEC;

$SPEC{'handle_cmd'} = {
    v => 1.1,
    summary => 'List scripts that depend on specified modules',
    description => <<'_',

This is currently implemented as rdeps + dist_scripts (find distributions that
depend on specified modules, and list all scripts in those distributions):

    % lcpan rdeps Some::Module | td select dist | xargs lcpan dist-scripts Some::Module

so not really accurate.

_
    args => {
        %App::lcpan::common_args,
        %App::lcpan::mods_args,
        %App::lcpan::rdeps_rel_args,
        %App::lcpan::rdeps_phase_args,
        %App::lcpan::rdeps_level_args,
        %App::lcpan::fauthor_args,
    },
};
sub handle_cmd {
    require App::lcpan::Cmd::mod2dist;

    my %args = @_;

    my $state = App::lcpan::_init(\%args, 'ro');
    my $dbh = $state->{dbh};

    my $res;

    my @dists;
    $res = App::lcpan::Cmd::mod2dist::handle_cmd(%args); # XXX subset
    return [500, "Can't mod2dist: $res->[0] - $res->[1]"]
        unless $res->[0] == 200;
    if (ref $res->[2] eq 'HASH') {
        push @dists, values %{ $res->[2] };
    } else {
        push @dists, $res->[2] if defined $res->[2];
    }
    return [404, "No dists found for the module(s) specified"] unless @dists;

    $res = App::lcpan::rdeps(%args, flatten=>1);
    return [500, "Can't mod2dist: $res->[0] - $res->[1]"]
        unless $res->[0] == 200;
    push @dists, $_->{dist} for @{ $res->[2] };

    my @where;
    push @where, "file.dist_name IN (".
        join(",", map { $dbh->quote($_) } @dists).")";
    push @where, "file.cpanid=".$dbh->quote($args{author})
        if defined $args{author};
    my $sql = "SELECT
  script.name name,
  file.dist_name dist,
  script.cpanid author,
  script.abstract abstract
FROM script
LEFT JOIN file ON script.file_id=file.id
WHERE ".join(" AND ", @where)."
";

    my @res;
    my $sth = $dbh->prepare($sql);
    $sth->execute();
    while (my $row = $sth->fetchrow_hashref) {
        push @res, $row;
    }
    my $resmeta = {};
    $resmeta->{'table.fields'} = [qw/name dist author abstract/];
    [200, "OK", \@res, $resmeta];
}

1;
# ABSTRACT:
