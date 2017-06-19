package App::lcpan::Cmd::mentions_by_mod;

# DATE
# VERSION

use 5.010;
use strict;
use warnings;
use Log::ger;

require App::lcpan;
require App::lcpan::Cmd::mentions;

our %SPEC;

my $mentions_args = $App::lcpan::Cmd::mentions::SPEC{handle_cmd}{args};

$SPEC{'handle_cmd'} = {
    v => 1.1,
    summary => 'List POD mentions by module(s)',
    description => <<'_',

This subcommand is a shortcut for:

    % lcpan mentions --mentioner-module MOD

_
    args => {
        %App::lcpan::common_args,
        %App::lcpan::mods_args,
        (map {$_ => $mentions_args->{$_}}
             grep {!/\A(mentioner_.+)\z/}
             keys %$mentions_args),
    },
};
sub handle_cmd {
    my %args = @_;

    my %mentions_args = %args;

    delete $mentions_args{modules};
    $mentions_args{mentioner_modules} = $args{modules};

    App::lcpan::Cmd::mentions::handle_cmd(%mentions_args);
}

1;
# ABSTRACT:
