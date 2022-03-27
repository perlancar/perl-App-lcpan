package App::lcpan::Cmd::mod_contents;

use 5.010;
use strict;
use warnings;

require App::lcpan;
require App::lcpan::Cmd::contents;

# AUTHORITY
# DATE
# DIST
# VERSION

our %SPEC;

my %cmd_args = (
    %{ $App::lcpan::Cmd::contents::SPEC{handle_cmd}{args} },
    %App::lcpan::mod_args,
);
delete $cmd_args{query};
delete $cmd_args{query_type};
delete $cmd_args{dist};

$SPEC{'handle_cmd'} = {
    v => 1.1,
    summary => "List contents inside a module's distribution",
    description => <<'_',

This subcommand lists files inside a module's distribution.

    % lcpan mod-contents Foo::Bar

is basically equivalent to:

    % lcpan contents --dist `lcpan mod2dist Foo::Bar`

_
    args => \%cmd_args,
};
sub handle_cmd {
    my %args = @_;

    my $state = App::lcpan::_init(\%args, 'ro');
    my $dbh = $state->{dbh};

    my ($file_id) = $dbh->selectrow_array(
        "SELECT file_id FROM module WHERE name=?", {}, $args{module});
    $file_id or return [404, "No such module '$args{module}'"];

    delete $args{module};
    App::lcpan::Cmd::contents::handle_cmd(
        %args,
        file_id => $file_id,
    );
}

1;
# ABSTRACT:
