package App::lcpan::Cmd::src;

use 5.010;
use strict;
use warnings;

use Encode qw(decode);

require App::lcpan;
require App::lcpan::Cmd::doc;

# AUTHORITY
# DATE
# DIST
# VERSION

our %SPEC;

my $args = { %{ $App::lcpan::Cmd::doc::SPEC{'handle_cmd'}{args} } }; # shallow clone
delete $args->{format};

$SPEC{'handle_cmd'} = {
    v => 1.1,
    summary => 'Show source of module/.pod/script',
    description => <<'_',

This command is a shortcut for:

    % lcpan doc --raw MODULE_OR_POD_OR_SCRIPT

_
    args => $args,
};
sub handle_cmd {
    my %args = @_;

    App::lcpan::Cmd::doc::handle_cmd(%args, format=>'raw');
}

1;
# ABSTRACT:
