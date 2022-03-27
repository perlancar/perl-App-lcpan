package App::lcpan::Cmd::dist_rdeps;

use 5.010;
use strict;
use warnings;
use Log::ger;

use App::lcpan ();
use App::lcpan::Cmd::dist_mods;
use Hash::Subset qw(hash_subset hash_subset_without);

# AUTHORITY
# DATE
# DIST
# VERSION

our %SPEC;

$SPEC{'handle_cmd'} = {
    v => 1.1,
    summary => 'List which distributions depend on specified distribution',
    description => <<'_',

This subcommand lists all modules of your specified distribution, then run
'deps' on all of those modules. So basically, this subcommand shows which
distributions depend on your specified distribution.

_
    args => {
        %App::lcpan::common_args,
        %App::lcpan::dist_args,
        %App::lcpan::rdeps_rel_args,
        %App::lcpan::rdeps_phase_args,
        %App::lcpan::rdeps_level_args,
    },
};
sub handle_cmd {
    my %args = @_;

    my $state = App::lcpan::_init(\%args, 'ro');
    my $dbh = $state->{dbh};

    my $res =  App::lcpan::Cmd::dist_mods::handle_cmd(
        hash_subset(\%args, \%App::lcpan::common_args),
        dist => $args{dist},
    );
    return [500, "Can't list modules of dist '$args{dist}': $res->[0] - $res->[1]"]
        unless $res->[0] == 200;

    App::lcpan::rdeps(
        hash_subset(\%args, \%App::lcpan::common_args),
        modules => $res->[2],
        hash_subset(\%args, \%App::lcpan::rdeps_rel_args),
        hash_subset(\%args, \%App::lcpan::rdeps_phase_args),
        hash_subset(\%args, \%App::lcpan::rdeps_level_args),
    );
}

1;
# ABSTRACT:
