package App::lcpan::Cmd::script2rel;

# DATE
# VERSION

use 5.010;
use strict;
use warnings;

require App::lcpan;

our %SPEC;

$SPEC{'handle_cmd'} = {
    v => 1.1,
    summary => 'Get release name of a script',
    args => {
        %App::lcpan::common_args,
        %App::lcpan::script_args,
        %App::lcpan::full_path_args,
        %App::lcpan::all_args,
    },
};
sub handle_cmd {
    my %args = @_;

    my $state = App::lcpan::_init(\%args, 'ro');
    my $dbh = $state->{dbh};

    my $script = $args{script};

    my $sth = $dbh->prepare("SELECT
  file.cpanid author,
  file.name release
FROM script
LEFT JOIN file ON script.file_id=file.id
WHERE script.name=?
ORDER BY file.id DESC");
    $sth->execute($script);

    my @res;
    while (my $row = $sth->fetchrow_hashref) {
        if ($args{full_path}) {
            $row->{release} = App::lcpan::_fullpath(
                $row->{release}, $state->{cpan}, $row->{author});
        } else {
            $row->{release} = App::lcpan::_relpath(
                $row->{release}, $row->{author});
        }
        return [200, "OK", $row->{release}] unless $args{all};
        push @res, $row;
    }
    return [404, "No such script"] unless $args{all};

    [200, "OK", \@res, {'table.fields' => [qw/release author/]}];
}

1;
# ABSTRACT:
