package App::lcpan::Cmd::authors_by_mod_count;

use 5.010;
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
    summary => 'List authors ranked by number of modules',
    args => {
        %App::lcpan::common_args,
    },
};
sub handle_cmd {
    my %args = @_;

    my $state = App::lcpan::_init(\%args, 'ro');
    my $dbh = $state->{dbh};

    my $sql = "SELECT
  cpanid author,
  COUNT(*) AS mod_count,
  ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM module), 4) mod_count_pct
FROM module m
GROUP BY cpanid
ORDER BY mod_count DESC
";

    my @res;
    my $sth = $dbh->prepare($sql);
    $sth->execute();
    while (my $row = $sth->fetchrow_hashref) {
        push @res, $row;
    }
    my $resmeta = {};
    $resmeta->{'table.fields'} = [qw/author mod_count mod_count_pct/];
    [200, "OK", \@res, $resmeta];
}

1;
# ABSTRACT:
