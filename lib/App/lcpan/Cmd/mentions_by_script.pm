package App::lcpan::Cmd::mentions_by_script;

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
    summary => 'List POD mentions by script(s)',
    description => <<'_',

This subcommand is a shortcut for:

    % lcpan mentions --mentioner-script SCRIPT

_
    args => {
        %App::lcpan::common_args,
        %App::lcpan::scripts_args,
        (map {$_ => $mentions_args->{$_}}
             grep {!/\A(type|mentioner_.+)\z/}
             keys %$mentions_args),
    },
};
sub handle_cmd {
    my %args = @_;

    my %mentions_args = %args;

    delete $mentions_args{scripts};
    $mentions_args{mentioner_scripts} = $args{scripts};

    App::lcpan::Cmd::mentions::handle_cmd(%mentions_args);
}

1;
# ABSTRACT:
