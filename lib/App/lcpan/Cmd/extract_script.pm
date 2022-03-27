package App::lcpan::Cmd::extract_script;

use 5.010;
use strict;
use warnings;

require App::lcpan;

use Perinci::Object;

# AUTHORITY
# DATE
# DIST
# VERSION

our %SPEC;

$SPEC{'handle_cmd'} = {
    v => 1.1,
    summary => "Extract a script's latest release file to current directory",
    args => {
        %App::lcpan::common_args,
        %App::lcpan::script_args,
        %App::lcpan::all_args,
    },
    tags => ['write-to-fs'],
};
sub handle_cmd {
    require Archive::Extract;

    my %args = @_;

    my $state = App::lcpan::_init(\%args, 'ro');
    my $dbh = $state->{dbh};

    my $script = $args{script};

    my $sth = $dbh->prepare("SELECT
  script.name script,
  file.cpanid author,
  file.name release
FROM script
LEFT JOIN file ON script.file_id=file.id
LEFT JOIN module ON file.id=module.file_id
WHERE script.name=?
GROUP BY file.id
ORDER BY module.version_numified DESC");

    $sth->execute($script);

    my @paths;
    my %mem;
    while (my $row = $sth->fetchrow_hashref) {
        unless ($args{all}) {
            next if $mem{$row->{script}}++;
        }
        push @paths, App::lcpan::_fullpath(
            $row->{release}, $state->{cpan}, $row->{author});
    }

    return [404, "No release for script '$script'"] unless @paths;

    my $envres = envresmulti();
    for my $i (0..$#paths) {
        my $path = $paths[$i];
        (-f $path) or do {
            $envres->add_result(
                404, "File not found: $path",
                {item_id => $path},
            );
            next;
        };
        my $ae = Archive::Extract->new(archive => $path);
        $ae->extract or do {
            $envres->add_result(
                500, "Can't extract: " . $ae->error,
                {item_id => $path},
            );
            next;
        };
        $envres->add_result(
            200, "OK",
            {item_id => $path},
        );
    }
    $envres->as_struct;
}

1;
# ABSTRACT:
