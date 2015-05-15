package App::lcpan::Cmd::mod2dist;

# DATE
# VERSION

use 5.010;
use strict;
use warnings;

require App::lcpan;

our %SPEC;

$SPEC{'handle_cmd'} = {
    v => 1.1,
    summary => 'Get distribution name of a module',
    args => {
        %App::lcpan::common_args,
        %App::lcpan::mods_args,
    },
};
sub handle_cmd {
    my %args = @_;

    App::lcpan::_set_args_default(\%args);
    my $cpan = $args{cpan};
    my $index_name = $args{index_name};
    my $mods = $args{modules};

    my $dbh = App::lcpan::_connect_db('ro', $cpan, $index_name);

    my $mods_s = join(",", map {$dbh->quote($_)} @$mods);

    my $sth = $dbh->prepare("
SELECT
  module.name module,
  dist.name dist
FROM module
LEFT JOIN file ON module.file_id=file.id
LEFT JOIN dist ON file.id=dist.file_id
WHERE module.name IN ($mods_s)");

    my $res;
    if (@$mods == 1) {
        $sth->execute;
        ($res) = $sth->fetchrow_array;
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
