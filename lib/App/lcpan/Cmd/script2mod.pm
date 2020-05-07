package App::lcpan::Cmd::script2mod;

# AUTHORITY
# DATE
# DIST
# VERSION

use 5.010001;
use strict;
use warnings;

require App::lcpan;

our %SPEC;

$SPEC{'handle_cmd'} = {
    v => 1.1,
    summary => 'Get module(s) of script(s)',
    description => <<'_',

This returns a module name from the same dist as the script, so one can do
something like this (install dist which contains a specified script from CPAN):

    % cpanm -n `lcpan script2mod pmdir`

_
    args => {
        %App::lcpan::common_args,
        %App::lcpan::scripts_args,
        %App::lcpan::all_args,
    },
};
sub handle_cmd {
    my %args = @_;

    my $state = App::lcpan::_init(\%args, 'ro');
    my $dbh = $state->{dbh};

    my $scripts = $args{scripts};

    my $scripts_s = join(",", map {$dbh->quote($_)} @$scripts);

    my $sth = $dbh->prepare("
SELECT
  script.name script,
  (SELECT name FROM module WHERE file_id=file.id LIMIT 1) module
FROM script
LEFT JOIN file   ON script.file_id=file.id
WHERE script.name IN ($scripts_s)
");

    my @res;
    my %mem;
    $sth->execute;
    while (my $row = $sth->fetchrow_hashref) {
        unless ($args{all}) {
            next if $mem{$row->{script}}++;
        }
        push @res, $row;
    }

    if (@$scripts == 1) {
        @res = map { $_->{module} } @res;
        if (!@res) {
            return [404, "No such script"];
        } elsif (@res == 1) {
            return [200, "OK", $res[0]];
        } else {
            return [200, "OK", \@res];
        }
    }

    [200, "OK", \@res, {'table.fields'=>[qw/script module/]}];
}

1;
# ABSTRACT:
