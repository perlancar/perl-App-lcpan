package App::lcpan::Cmd::distmods;

# DATE
# VERSION

use 5.010;
use strict;
use warnings;

require App::lcpan;

our %SPEC;

$SPEC{'handle_cmd'} = {
    v => 1.1,
    summary => 'List modules in a distribution',
    args => {
        %App::lcpan::common_args,
        %App::lcpan::dist_args,
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
    my $dist = $args{dist};
    my $detail = $args{detail};

    my $dbh = App::lcpan::_connect_db('ro', $cpan, $index_name);

    my $sth = $dbh->prepare("SELECT
  module.name name,
  module.version version
FROM module
LEFT JOIN file ON module.file_id=file.id
LEFT JOIN dist ON file.id=dist.file_id
WHERE dist.name=?
ORDER BY name DESC");
    $sth->execute($dist);
    my @res;
    while (my $row = $sth->fetchrow_hashref) {
        push @res, $detail ? $row : $row->{name};
    }
    my $resmeta = {};
    $resmeta->{format_options} = {any=>{table_column_orders=>[[qw/name version/]]}}
        if $detail;
    [200, "OK", \@res, $resmeta];
}

1;
# ABSTRACT:
