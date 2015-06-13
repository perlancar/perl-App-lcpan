package App::lcpan::Cmd::extract_rel;

# DATE
# VERSION

use 5.010;
use strict;
use warnings;

require App::lcpan;

our %SPEC;

$SPEC{'handle_cmd'} = {
    v => 1.1,
    summary => "Extract a release to current directory",
    args => {
        %App::lcpan::common_args,
        %App::lcpan::rel_args,
    },
};
sub handle_cmd {
    require Archive::Extract;

    my %args = @_;

    App::lcpan::_set_args_default(\%args);
    my $cpan = $args{cpan};
    my $index_name = $args{index_name};
    my $rel = $args{release};

    my $dbh = App::lcpan::_connect_db('ro', $cpan, $index_name);

    my $row = $dbh->selectrow_hashref("SELECT
  cpanid,
  name
FROM file
WHERE name=?
", {}, $rel);

    return [404, "No such release"] unless $row;

    my $path = App::lcpan::_relpath($row->{name}, $cpan, $row->{cpanid});

    my $ae = Archive::Extract->new(archive => $path);
    $ae->extract or return [500, "Can't extract: " . $ae->error];

    [200, "OK", undef, {'func.release_path'=>$path}];
}

1;
# ABSTRACT:
