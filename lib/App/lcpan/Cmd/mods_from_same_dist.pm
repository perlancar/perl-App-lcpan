package App::lcpan::Cmd::mods_from_same_dist;

# DATE
# VERSION

use 5.010;
use strict;
use warnings;

require App::lcpan;

our %SPEC;

$SPEC{':package'} = {
    v => 1.1,
    summary => "'mods_from_same_dist' command",
};

$SPEC{'handle_cmd'} = {
    v => 1.1,
    summary => 'Given a module, list all modules in the same distribution',
    args => {
        %App::lcpan::common_args,
        %App::lcpan::mods_args,
        detail => {
            schema => 'bool',
        },
    },
};
sub handle_cmd {
    my %args = @_;

    App::lcpan::_set_args_default(\%args);
    my $cpan = $args{cpan};
    my $index_name = $args{index_name};

    my $detail = $args{detail};

    my $dbh = App::lcpan::_connect_db('ro', $cpan, $index_name);

    my $emods = join(",", map {$dbh->quote($_)} @{ $args{modules} });
    my $sth = $dbh->prepare("SELECT
  module.name name,
  module.version version,
  dist.name dist,
  dist.version dist_version
FROM module
JOIN dist ON module.file_id=dist.file_id
WHERE dist.name IN (SELECT name FROM dist WHERE file_id IN (SELECT file_id FROM module WHERE name IN ($emods)))
ORDER BY name DESC");
    $sth->execute;
    my @res;
    while (my $row = $sth->fetchrow_hashref) {
        push @res, $detail ? $row : $row->{name};
    }
    my $resmeta = {};
    $resmeta->{format_options} = {any=>{table_column_orders=>[[qw/name version dist dist_version/]]}}
        if $detail;
    [200, "OK", \@res, $resmeta];
}

1;
# ABSTRACT:
