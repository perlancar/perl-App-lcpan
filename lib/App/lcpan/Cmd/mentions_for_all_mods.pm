package App::lcpan::Cmd::mentions_for_all_mods;

# AUTHORITY
# DATE
# DIST
# VERSION

use 5.010;
use strict;
use warnings;
use Log::ger;

require App::lcpan;
require App::lcpan::Cmd::mentions_for_mod;

our %SPEC;

my $mentions_for_mod_args = $App::lcpan::Cmd::mentions_for_mod::SPEC{handle_cmd}{args};

$SPEC{'handle_cmd'} = {
    v => 1.1,
    summary => 'List PODs which mention all specified module(s)',
    description => <<'_',

This subcommand searches PODs that mention all of the specified modules. To
search for PODs that mention *any* of the specified modules, see the
`mentions-for-mods` subcommand.

_
    args => $mentions_for_mod_args,
};
sub handle_cmd {
    my %args = @_;

    my $mres = App::lcpan::Cmd::mentions_for_mod::handle_cmd(%args);
    return $mres unless $mres->[0] == 200;

    my $mods = $args{modules};

    my %counts; # key = content_path, value = hash of module name => count
    my %content_data; # key = content_path, value = data
    for my $e (@{ $mres->[2] }) {
        $counts{$e->{content_path}}{$e->{module}}++;
        $content_data{$e->{content_path}} //= {
            release          => $e->{release},
            mentioner_author => $e->{mentioner_author},
            content_path     => $e->{content_path},
        };
    }

    my $resmeta = {'table.fields' => [qw/content_path mentioner_author release/]};

    my @res;
    for my $cp (sort keys %counts) {
        next unless keys(%{ $counts{$cp} }) == @$mods;
        push @res, $content_data{$cp};
    }

    [200, "OK", \@res, $resmeta];
}

1;
# ABSTRACT:
