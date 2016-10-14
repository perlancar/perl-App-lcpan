package App::lcpan::Cmd::authors_by_script_count;

# DATE
# VERSION

use 5.010;
use strict;
use warnings;

require App::lcpan;

our %SPEC;

$SPEC{'handle_cmd'} = {
    v => 1.1,
    summary => 'List authors ranked by number of scripts',
    args => {
        %App::lcpan::common_args,
    },
};
sub handle_cmd {
    my %args = @_;

    my $state = App::lcpan::_init(\%args, 'ro');
    my $dbh = $state->{dbh};

    my $sql = "SELECT
  file.cpanid id,
  -- author.fullname name, -- too slow
  COUNT(*) AS script_count,
  ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM script), 4) script_count_pct
FROM script
-- LEFT JOIN author ON author.cpanid=file.cpanid
LEFT JOIN file ON script.file_id=file.id
GROUP BY file.cpanid
ORDER BY script_count DESC
";

    my @res;
    my $sth = $dbh->prepare($sql);
    $sth->execute();
    while (my $row = $sth->fetchrow_hashref) {
        push @res, $row;
    }
    my $resmeta = {};
    #$resmeta->{'table.fields'} = [qw/id name script_count script_count_pct/];
    $resmeta->{'table.fields'} = [qw/id script_count script_count_pct/];
    [200, "OK", \@res, $resmeta];
}

1;
# ABSTRACT:
