package App::lcpan::Cmd::extract_rel;

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
    summary => "Extract a release to current directory",
    args => {
        %App::lcpan::common_args,
        %App::lcpan::rel_args,
    },
    tags => ['write-to-fs'],
};
sub handle_cmd {
    require Archive::Extract;

    my %args = @_;

    my $state = App::lcpan::_init(\%args, 'ro');
    my $dbh = $state->{dbh};

    my $rel = $args{release};

    my $row = $dbh->selectrow_hashref("SELECT
  cpanid,
  name
FROM file
WHERE name=?
", {}, $rel);

    return [404, "No such release"] unless $row;

    my $path = App::lcpan::_fullpath(
        $row->{name}, $state->{cpan}, $row->{cpanid});

    (-f $path) or return [404, "File not found: $path"];

    my $ae = Archive::Extract->new(archive => $path);
    $ae->extract or return [500, "Can't extract: " . $ae->error];

    [200, "OK", undef, {'func.release_path'=>$path}];
}

1;
# ABSTRACT:
