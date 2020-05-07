package App::lcpan::Cmd::dist2rel;

# DATE
# VERSION

use 5.010;
use strict;
use warnings;

require App::lcpan;

our %SPEC;

$SPEC{'handle_cmd'} = {
    v => 1.1,
    summary => 'Get (latest) release name of a distribution',
    args => {
        %App::lcpan::common_args,
        %App::lcpan::dist_args,
        %App::lcpan::full_path_args,
        # all=>1
    },
};
sub handle_cmd {
    my %args = @_;

    my $state = App::lcpan::_init(\%args, 'ro');
    my $dbh = $state->{dbh};

    my $dist = $args{dist};

    my $row = $dbh->selectrow_hashref("SELECT
  cpanid cpanid,
  dist_name name
FROM file
WHERE dist_name=?
ORDER BY dist_version_numified DESC", {}, $dist);
    my $rel;

    if ($row) {
        if ($args{full_path}) {
            $rel = App::lcpan::_fullpath(
                $row->{name}, $state->{cpan}, $row->{cpanid});
        } else {
            $rel = App::lcpan::_relpath(
                $row->{name}, $row->{cpanid});
        }
    }
    [200, "OK", $rel];
}

1;
# ABSTRACT:
