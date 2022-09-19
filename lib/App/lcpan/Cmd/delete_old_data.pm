package App::lcpan::Cmd::delete_old_data;

use 5.010001;
use strict;
use warnings;
use Log::ger;

require App::lcpan;

# AUTHORITY
# DATE
# DIST
# VERSION

our %SPEC;

$SPEC{handle_cmd} = {
    v => 1.1,
    summary => 'Delete old data (contents of old_* tables)',
    description => <<'_',

Will delete records in `old_*` tables.

_
    args => {
        %App::lcpan::common_args,
    },
    tags => ['write-to-db'],
};
sub handle_cmd {
    my %args = @_;

    my $state = App::lcpan::_init(\%args, 'rw');
    my $dbh = $state->{dbh};

    $dbh->begin_work;
    $dbh->do("DELETE FROM old_script");
    $dbh->do("DELETE FROM old_module");
    $dbh->do("DELETE FROM old_file");
    $dbh->commit;

    [200, "OK"];
}

1;
# ABSTRACT:
