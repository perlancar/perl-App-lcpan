package App::lcpan::Cmd::mentions_for_mod;

use 5.010;
use strict;
use warnings;
use Log::ger;

require App::lcpan;
require App::lcpan::Cmd::mentions;

# AUTHORITY
# DATE
# DIST
# VERSION

our %SPEC;

my $mentions_args = $App::lcpan::Cmd::mentions::SPEC{handle_cmd}{args};

$SPEC{'handle_cmd'} = {
    v => 1.1,
    summary => 'List POD mentions for module(s)',
    description => <<'_',

This subcommand is a shortcut for:

    % lcpan mentions --type known-module --mentioned-module <module1> [module2] ...

This searches PODs that mention either `module1`, `module2`, and so on. To
search for PODs that mention *all* of the modules, see the
`mentions-for-all-mods` subcommand.

_
    args => {
        %App::lcpan::common_args,
        %App::lcpan::mods_args,
        (map {$_ => $mentions_args->{$_}}
             grep {!/\A(type|mentioned_modules|mentioned_scripts)\z/}
             keys %$mentions_args),
    },
};
sub handle_cmd {
    my %args = @_;

    my %mentions_args = %args;

    delete $mentions_args{modules};
    $mentions_args{mentioned_modules} = $args{modules};

    $mentions_args{type} = 'known-module';

    App::lcpan::Cmd::mentions::handle_cmd(%mentions_args);
}

1;
# ABSTRACT:
