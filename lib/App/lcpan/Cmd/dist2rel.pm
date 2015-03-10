package App::lcpan::Cmd::dist2rel;

# DATE
# VERSION

use 5.010;
use strict;
use warnings;

require App::lcpan;

our %SPEC;

$SPEC{':package'} = {
    v => 1.1,
    summary => "'dist2rel' command",
};

$SPEC{'handle_cmd'} = {
    v => 1.1,
    summary => 'Get (latest) release name of a distribution',
    args => {
        %App::lcpan::common_args,
        %App::lcpan::dist_args,
        %App::lcpan::full_path_args,
        # all=>1
    },
    result_naked=>1,
};
sub handle_cmd {
    my %args = @_;

    App::lcpan::_set_args_default(\%args);
    my $cpan = $args{cpan};
    my $index_name = $args{index_name};
    my $dist = $args{dist};

    my $dbh = App::lcpan::_connect_db('ro', $cpan, $index_name);

    my $row = $dbh->selectrow_hashref("SELECT
  file.cpanid cpanid,
  file.name name
FROM dist
LEFT JOIN file ON dist.file_id=file.id
WHERE dist.name=?
ORDER BY version_numified DESC", {}, $dist);
    return undef unless $row;
    if ($args{full_path}) {
        _relpath($row->{name}, $cpan, $row->{cpanid});
    } else {
        $row->{name};
    }
}

1;
# ABSTRACT:
