package App::lcpan::Cmd::dist2author;

# DATE
# VERSION

use 5.010;
use strict;
use warnings;

require App::lcpan;

our %SPEC;

$SPEC{'handle_cmd'} = {
    v => 1.1,
    summary => 'Get author of distribution(s)',
    args => {
        %App::lcpan::common_args,
        %App::lcpan::dists_args,
    },
};
sub handle_cmd {
    my %args = @_;

    my $state = App::lcpan::_init(\%args, 'ro');
    my $dbh = $state->{dbh};

    my $dists = $args{dists};

    my $dists_s = join(",", map {
        my $d=$_; $d =~ s/::/-/g; $dbh->quote($d);
    } @$dists);

    my $sth = $dbh->prepare("SELECT
  dist.name dist,
  dist.cpanid author
FROM dist
WHERE dist.name IN ($dists_s)");

    my @res;
    $sth->execute;
    while (my $row = $sth->fetchrow_hashref) {
        push @res, $row;
    }

    if (@$dists == 1) {
        @res = map { $_->{dist} } @res;
        if (!@res) {
            return [404, "No such dist"];
        } elsif (@res == 1) {
            return [200, "OK", $res[0]];
        } else {
            return [200, "OK", \@res];
        }
    }

    [200, "OK", \@res, {'table.fields'=>[qw/dist author/]}];
}

1;
# ABSTRACT:
