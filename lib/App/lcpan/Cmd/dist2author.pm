package App::lcpan::Cmd::dist2author;

# AUTHORITY
# DATE
# DIST
# VERSION

use 5.010001;
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
  f.dist_name dist,
  f.cpanid author
FROM file f
WHERE f.dist_name IN ($dists_s)");

    my @res;
    $sth->execute;
    while (my $row = $sth->fetchrow_hashref) {
        push @res, $row;
    }

    if (@$dists == 1) {
        @res = map { $_->{author} } @res;
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
