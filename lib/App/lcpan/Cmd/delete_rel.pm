package App::lcpan::Cmd::delete_rel;

# DATE
# VERSION

use 5.010001;
use strict;
use warnings;
use Log::Any::IfLOG '$log';

require App::lcpan;

our %SPEC;

$SPEC{handle_cmd} = {
    v => 1.1,
    summary => 'Delete a release record in the database',
    description => <<'_',

Will delete records associated with a release in the database (including in the
`file` table, `module`, `dist`, `dep`, and so on). If `--delete-file` option is
specified, will also remove the file from the local mirror.

But currently will not remove/update the `modules/02packages.details.txt.gz`
index.

_
    args => {
        %App::lcpan::common_args,
        %App::lcpan::rel_args,
        delete_file => {
            summary => 'Whether to delete the release file from the filesystem too',
            schema => ['bool*', is=>1],
        },
    },
    tags => ['write-to-db', 'write-to-fs'],
};
sub handle_cmd {
    my %args = @_;

    my $state = App::lcpan::_init(\%args, 'rw');
    my $dbh = $state->{dbh};

    my $row = $dbh->selectrow_hashref("SELECT id,cpanid FROM file WHERE name=?", {}, $args{release})
        or return [404, "No such release"];

    $dbh->begin_work;
    App::lcpan::_delete_releases_records($dbh, $row->{id});
    $dbh->commit;

    if ($args{delete_file}) {
        my $path = App::lcpan::_fullpath(
            $args{release}, $state->{cpan}, $row->{cpanid});
        $log->infof("Deleting file %s ...", $path);
        unlink $path;
    }

    [200, "OK"];
}

1;
# ABSTRACT:
