package App::lcpan::Cmd::mentions_for_script;

# DATE
# VERSION

use 5.010;
use strict;
use warnings;
use Log::Any::IfLOG '$log';

require App::lcpan;
require App::lcpan::Cmd::mentions;

our %SPEC;

my $mentions_args = $App::lcpan::Cmd::mentions::SPEC{handle_cmd}{args};

$SPEC{'handle_cmd'} = {
    v => 1.1,
    summary => 'List POD mentions for script(s)',
    description => <<'_',

This subcommand is a shortcut for:

    % lcpan mentions --type script --mentioned-script SCRIPT

_
    args => {
        %App::lcpan::common_args,
        %App::lcpan::scripts_args,
        (map {$_ => $mentions_args->{$_}}
             grep {!/\A(type|mentioned_modules|mentioned_scripts)\z/}
             keys %$mentions_args),
    },
};
sub handle_cmd {
    my %args = @_;

    my %mentions_args = %args;

    delete $mentions_args{scripts};
    $mentions_args{mentioned_scripts} = $args{scripts};

    $mentions_args{type} = 'script';

    App::lcpan::Cmd::mentions::handle_cmd(%mentions_args);
}

1;
# ABSTRACT:
