package App::lcpan::Cmd::mod2dist;

# AUTHORITY
# DATE
# DIST
# VERSION

use 5.010;
use strict;
use warnings;

require App::lcpan;

our %SPEC;

$SPEC{'handle_cmd'} = {
    v => 1.1,
    summary => 'Get distribution name of module(s)',
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
  file.dist_name dist
FROM module
LEFT JOIN file ON module.file_id=file.id
WHERE module.name IN ($mods_s)");

    my $res;
    if (@$mods == 1) {
        $sth->execute;
        (undef, $res) = $sth->fetchrow_array;
    } else {
        $sth->execute;
        $res = {};
        while (my $row = $sth->fetchrow_hashref) {
            $res->{$row->{module}} = $row->{dist};
        }
    }
    [200, "OK", $res];
}

1;
# ABSTRACT:
