package App::lcpan::Cmd::author_deps;

# AUTHORITY
# DATE
# DIST
# VERSION

use 5.010;
use strict;
use warnings;

require App::lcpan;
use Hash::Subset qw(hash_subset);

our %SPEC;

$SPEC{'handle_cmd'} = {
    v => 1.1,
    summary => "List dependencies for all of the dists of an author",
    description => <<'_',

For a CPAN author, this subcommand is a shortcut for doing:

    % lcpan deps Your-Dist

for all of your distributions. It shows just how many modules are you currently
using in one of your distros on CPAN.

To show how many modules from other authors you are depending:

    % lcpan author-deps YOURCPANID --module-author-isnt YOURCPANID

To show how many of your own modules you are depending in your own distros:

    % lcpan author-deps YOURCPANID --module-author-is YOURCPANID

To find whether there are any prerequisites that you mention in your
distributions that are currently broken (not indexed on CPAN):

    % lcpan author-deps YOURCPANID --broken --dont-uniquify

_
    args => {
        %App::lcpan::common_args,
        %App::lcpan::author_args,
        %App::lcpan::deps_args,
        module_authors => {
            summary => 'Only list depended modules published by specified author(s)',
            'x.name.is_plural' => 1,
            schema => ['array*', of=>'str*'],
            element_completion => \&App::lcpan::_complete_cpanid,
        },
        module_authors_arent => {
            summary => 'Do not list depended modules published by specified author(s)',
            'x.name.is_plural' => 1,
            'x.name.singular' => 'module_author_isnt',
            schema => ['array*', of=>'str*'],
            element_completion => \&App::lcpan::_complete_cpanid,
        },
    },
};
sub handle_cmd {
    my %args = @_;

    my $author = $args{author};

    my $res = App::lcpan::dists(
        hash_subset(\%args, \%App::lcpan::common_args, \%App::lcpan::author_args),
    );
    return $res if $res->[0] != 200;
    my $dists = $res->[2];

    my %deps_args = %args;
    $deps_args{dists} = $dists;
    delete $deps_args{author};
    delete $deps_args{authors};
    delete $deps_args{authors_arent};
    $deps_args{authors} = delete $args{module_authors};
    $deps_args{authors_arent} = delete $args{module_authors_arent};
    $deps_args{phase} = delete $args{phase};
    $deps_args{rel} = delete $args{rel};
    $deps_args{added_since} = delete $args{added_since};
    $deps_args{updated_since} = delete $args{updated_since};
    $deps_args{added_or_updated_since} = delete $args{added_or_updated_since};
    $res = App::lcpan::deps(%deps_args);
    return $res if $res->[0] != 200;

    $res;
}

1;
# ABSTRACT:
