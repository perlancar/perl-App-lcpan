package App::lcpan::Cmd::distmods;

# DATE
# VERSION

use 5.010;
use strict;
use warnings;

require App::lcpan;

our %SPEC;

$SPEC{':package'} = {
    v => 1.1,
    summary => "'distmods' command",
};

$SPEC{'handle_cmd'} = {
    v => 1.1,
    summary => 'List modules in a distribution',
    args => {
        %App::lcpan::common_args,
        %App::lcpan::dist_args,
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

    my $sth = $dbh->prepare("SELECT
  module.name name,
  module.version version
FROM module
LEFT JOIN file ON module.file_id=file.id
LEFT JOIN dist ON file.id=dist.file_id
WHERE dist.name=?
ORDER BY name DESC");
    $sth->execute($dist);
    my @res;
    while (my $row = $sth->fetchrow_hashref) {
        push @res, $row->{name};
    }
    \@res;
}

1;
# ABSTRACT:
