package App::lcpan::Cmd::extract_mod;

# DATE
# VERSION

use 5.010;
use strict;
use warnings;

require App::lcpan;

our %SPEC;

$SPEC{'handle_cmd'} = {
    v => 1.1,
    summary => "Extract a module's latest release file to current directory",
    args => {
        %App::lcpan::common_args,
        %App::lcpan::mod_args,
    },
    tags => ['write-to-fs'],
};
sub handle_cmd {
    require Archive::Extract;

    my %args = @_;

    my $state = App::lcpan::_init(\%args, 'ro');
    my $dbh = $state->{dbh};

    my $mod = $args{module};

    my $row = $dbh->selectrow_hashref("SELECT
  file.cpanid cpanid,
  file.name name
FROM module
LEFT JOIN file ON module.file_id=file.id
WHERE module.name=?
ORDER BY version_numified DESC
", {}, $mod);

    return [404, "No release for module '$mod'"] unless $row;

    my $path = App::lcpan::_relpath(
        $row->{name}, $state->{cpan}, $row->{cpanid});

    my $ae = Archive::Extract->new(archive => $path);
    $ae->extract or return [500, "Can't extract: " . $ae->error];

    [200, "OK", undef, {'func.release_path'=>$path}];
}

1;
# ABSTRACT:
