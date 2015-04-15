package App::lcpan::Cmd::authorrdeps;

# DATE
# VERSION

use 5.010;
use strict;
use warnings;

require App::lcpan;

our %SPEC;

$SPEC{':package'} = {
    v => 1.1,
    summary => "'authorrdeps' command",
};

$SPEC{'handle_cmd'} = {
    v => 1.1,
    summary => "Find all other authors' distributions that use one of author's modules",
    args => {
        %App::lcpan::common_args,
        %App::lcpan::author_args,
        #detail => {
        #    schema => 'bool',
        #},
    },
};
sub handle_cmd {
    my %args = @_;

    my $author = $args{author};

    my $res = App::lcpan::modules(%args, author=>$author);
    return $res if $res->[0] != 200;

    my $mods = $res->[2];
    delete $args{author};
    $res = App::lcpan::rdeps(%args, author_isnt=>[$author], modules=>$mods);
    return $res if $res->[0] != 200;

    $res;
}

1;
# ABSTRACT:
