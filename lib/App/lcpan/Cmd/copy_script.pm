package App::lcpan::Cmd::copy_script;

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
    summary => "Copy a script's latest release file to current directory",
    args => {
        %App::lcpan::common_args,
        %App::lcpan::script_args,
        %App::lcpan::overwrite_args,
        %App::lcpan::all_args,
    },
    tags => ['write-to-fs'],
};
sub handle_cmd {
    require File::Copy;

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

    my @srcpaths;
    my @targetpaths;
    my %mem;
    while (my $row = $sth->fetchrow_hashref) {
        unless ($args{all}) {
            next if $mem{$row->{script}}++;
        }
        push @srcpaths, App::lcpan::_fullpath(
            $row->{release}, $state->{cpan}, $row->{author});
        push @targetpaths, $row->{release};
    }

    return [404, "No release for script '$script'"] unless @srcpaths;

    my $envres = envresmulti();
    for my $i (0..$#srcpaths) {
        my $srcpath = $srcpaths[$i];
        my $targetpath = $targetpaths[$i];
        (-f $srcpath) or do {
            $envres->add_result(
                404, "File not found: $srcpath",
                {item_id => $srcpath},
            );
            next;
        };
        if ((-f $targetpath) && !$args{overwrite}) {
            $envres->add_result(
                412, "Refusing to overwrite existing file '$targetpath'",
                {item_id => $srcpath},
            );
            next;
        }
        File::Copy::syscopy($srcpath, $targetpath) or do {
            $envres->add_result(
                500, "Can't copy '$srcpath' to '$targetpath': $!",
                {item_id => $srcpath},
            );
            next;
        };
        $envres->add_result(
            200, "OK",
            {item_id => $srcpath},
        );
    }
    $envres->as_struct;
}

1;
# ABSTRACT:
