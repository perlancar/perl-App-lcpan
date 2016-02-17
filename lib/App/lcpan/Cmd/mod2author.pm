package App::lcpan::Cmd::mod2author;

# DATE
# VERSION

use 5.010;
use strict;
use warnings;

require App::lcpan;

our %SPEC;

$SPEC{'handle_cmd'} = {
    v => 1.1,
    summary => 'Get author of module(s)',
    args => {
        %App::lcpan::common_args,
        %App::lcpan::mods_args,
    },
};
sub handle_cmd {
    my %args = @_;

    my $state = App::lcpan::_init(\%args, 'ro');
    my $dbh = $state->{dbh};

    my $mods = $args{modules};

    my $mods_s = join(",", map {$dbh->quote($_)} @$mods);

    my $sth = $dbh->prepare("
SELECT
  module.name module,
  module.cpanid author
FROM module
WHERE module.name IN ($mods_s)");

    my @res;
    $sth->execute;
    while (my $row = $sth->fetchrow_hashref) {
        push @res, $row;
    }

    if (@$mods == 1) {
        @res = map { $_->{author} } @res;
        if (!@res) {
            return [404, "No such module"];
        } elsif (@res == 1) {
            return [200, "OK", $res[0]];
        } else {
            return [200, "OK", \@res];
        }
    }

    [200, "OK", \@res, {'table.fields'=>[qw/module author/]}];
}

1;
# ABSTRACT:
