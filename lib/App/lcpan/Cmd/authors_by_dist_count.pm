package App::lcpan::Cmd::authors_by_dist_count;

# DATE
# VERSION

use 5.010;
use strict;
use warnings;

require App::lcpan;

our %SPEC;

$SPEC{'handle_cmd'} = {
    v => 1.1,
    summary => 'List authors ranked by number of dists',
    args => {
        %App::lcpan::common_args,
    },
};
sub handle_cmd {
    my %args = @_;

    App::lcpan::_set_args_default(\%args);
    my $cpan = $args{cpan};
    my $index_name = $args{index_name};

    my $dbh = App::lcpan::_connect_db('ro', $cpan, $index_name);

    my $sql = "SELECT
  cpanid author,
  COUNT(*) AS dist_count
FROM dist d
GROUP BY cpanid
ORDER BY dist_count DESC
";

    my @res;
    my $sth = $dbh->prepare($sql);
    $sth->execute();
    while (my $row = $sth->fetchrow_hashref) {
        push @res, $row;
    }
    my $resmeta = {};
    $resmeta->{format_options} = {any=>{table_column_orders=>[[qw/author dist_count/]]}};
    [200, "OK", \@res, $resmeta];
}

1;
# ABSTRACT:
