package App::lcpan::Cmd::dist_contents;

# DATE
# VERSION

use 5.010;
use strict;
use warnings;

require App::lcpan;
require App::lcpan::Cmd::contents;

our %SPEC;

my %cmd_args = (
    %{ $App::lcpan::Cmd::contents::SPEC{handle_cmd}{args} },
    %App::lcpan::dist_args,
);
delete $cmd_args{query};
delete $cmd_args{query_type};

$SPEC{'handle_cmd'} = {
    v => 1.1,
    summary => 'List contents inside a distribution',
    description => <<'_',

This subcommand lists files inside a distribution.

    % lcpan dist-contents Foo-Bar

is basically equivalent to:

    % lcpan contents --dist Foo-Bar

_
    args => \%cmd_args,
};
sub handle_cmd {
    my %args = @_;

    my $state = App::lcpan::_init(\%args, 'ro');
    my $dbh = $state->{dbh};

    my ($dist_id) = $dbh->selectrow_array(
        "SELECT id FROM dist WHERE name=?", {}, $args{dist});
    $dist_id or return [404, "No such dist '$args{dist}'"];

    App::lcpan::Cmd::contents::handle_cmd(%args);
}

1;
# ABSTRACT:
