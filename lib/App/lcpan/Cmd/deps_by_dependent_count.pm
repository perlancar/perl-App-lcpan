package App::lcpan::Cmd::deps_by_dependent_count;

# DATE
# VERSION

use 5.010;
use strict;
use warnings;
use Log::Any::IfLOG '$log';

require App::lcpan;

our %SPEC;

$SPEC{'handle_cmd'} = {
    v => 1.1,
    summary => 'List dependencies, sorted by number of dependents',
    description => <<'_',

This subcommand is like `deps`, except that this subcommand does not support
recursing and it sorts the result by number of dependent dists. For example,
Suppose that dist `Foo` depends on `Mod1` and `Mod2`, `Bar` depends on `Mod2`
and `Mod3`, and `Baz` depends on `Mod2` and `Mod3`, then `lcpan
deps-by-dependent-count Foo Bar Baz` will return `Mod2` (3 dependents), `Mod3`
(2 dependents), `Mod1` (1 dependent).

_
    args => {
        %App::lcpan::common_args,
        %App::lcpan::mods_args,

        %App::lcpan::deps_phase_args,
        %App::lcpan::deps_rel_args,
        %App::lcpan::finclude_core_args,
        %App::lcpan::finclude_noncore_args,
        %App::lcpan::perl_version_args,
        # XXX with_xs_or_pp
        authors => {
            'x.name.is_plural' => 1,
            'x.name.singular' => 'author',
            schema => ['array*', of=>'str*', min_len=>1],
            tags => ['category:filtering'],
            element_completion => \&App::lcpan::_complete_cpanid,
        },
        authors_arent => {
            'x.name.is_plural' => 1,
            'x.name.singular' => 'author_isnt',
            schema => ['array*', of=>'str*', min_len=>1],
            tags => ['category:filtering'],
            element_completion => \&App::lcpan::_complete_cpanid,
        },
    },
};
sub handle_cmd {
    require Module::CoreList::More;

    my %args = @_;

    my $state = App::lcpan::_init(\%args, 'ro');
    my $dbh = $state->{dbh};

    my $phase   = $args{phase} // 'runtime';
    my $rel     = $args{rel} // 'requires';
    my $include_core    = $args{include_core} // 1;
    my $include_noncore = $args{include_noncore} // 1;
    my $plver   = $args{perl_version} // "$^V";

    # first, get the dist ID's of the requested modules
    my @dist_ids;
    {
        my $mods_s = join(", ", map {$dbh->quote($_)} @{$args{modules}});
        my $sth = $dbh->prepare("SELECT id FROM dist WHERE is_latest AND file_id IN (SELECT file_id FROM module WHERE name IN ($mods_s))");
        $sth->execute;
        while (my ($id) = $sth->fetchrow_array) { push @dist_ids, $id }
        return [404, "No such module(s)"] unless @dist_ids;
    }

    my @cols = (
        # name, dbcolname/expr
        ["module", "m.name"],
        ["author", "m.cpanid"],
        ["version", "m.version"],
        ["is_core", undef],
        ["dependent_count", "COUNT(*)"],
    );

    my @wheres = (
        "m.id IS NOT NULL",
        "dep.dist_id IN (".join(",", @dist_ids).")",
    );
    my @binds;

    if ($phase ne 'ALL') {
        push @wheres, "dep.phase=?";
        push @binds, $phase;
    }
    if ($rel ne 'ALL') {
        push @wheres, "dep.rel=?";
        push @binds, $rel;
    }
    if ($args{authors}) {
        push @wheres, "(".join(" OR ", map {"author=?"} @{$args{authors}}).")";
        push @binds, map {uc $_} @{ $args{authors} };
    }
    if ($args{authors_arent}) {
        for (@{ $args{authors_arent} }) {
            push @wheres, "author<>?";
            push @binds, uc $_;
        }
    }

    my $sth = $dbh->prepare("SELECT
".join(",\n", map {"  $_->[1] AS $_->[0]"} grep {defined $_->[1]} @cols)."
FROM dep
LEFT JOIN module m ON dep.module_id=m.id
WHERE ".join(" AND ", @wheres)."
GROUP BY dep.module_id
ORDER BY COUNT(*) DESC, m.name
");
    $sth->execute(@binds);

    my @rows;
    while (my $row = $sth->fetchrow_hashref) {
        $row->{is_core} = $row->{module} eq 'perl' ||
            Module::CoreList::More->is_still_core(
                $row->{module}, $row->{version},
                version->parse($plver)->numify);
        next if !$include_core    &&  $row->{is_core};
        next if !$include_noncore && !$row->{is_core};
        push @rows, $row;
    }

    [200, "OK", \@rows, {'table.fields'=>[map {$_->[0]} @cols]}];
}

1;
# ABSTRACT:
