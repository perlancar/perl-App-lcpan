package App::lcpan::Cmd::extract_dist;

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
    summary => "Extract a distribution's latest release file to current directory",
    args => {
        %App::lcpan::common_args,
        %App::lcpan::dist_args,
    },
    tags => ['write-to-fs'],
};
sub handle_cmd {
    require Archive::Extract;

    my %args = @_;

    my $state = App::lcpan::_init(\%args, 'ro');
    my $dbh = $state->{dbh};

    my $dist = $args{dist};

    my $row = $dbh->selectrow_hashref("SELECT
  cpanid cpanid,
  name name
FROM file
WHERE dist_name=? AND is_latest_dist=1
ORDER BY dist_version_numified DESC
", {}, $dist);

    return [404, "No release for distribution '$dist'"] unless $row;

    my $path = App::lcpan::_fullpath(
        $row->{name}, $state->{cpan}, $row->{cpanid});

    (-f $path) or return [404, "File not found: $path"];

    my $ae = Archive::Extract->new(archive => $path);
    $ae->extract or return [500, "Can't extract: " . $ae->error];

    [200, "OK", undef, {'func.release_path'=>$path}];
}

1;
# ABSTRACT:
