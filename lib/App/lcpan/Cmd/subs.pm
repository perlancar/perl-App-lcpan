package App::lcpan::Cmd::subs;

# DATE
# VERSION

use 5.010;
use strict;
use warnings;
use Log::ger;

require App::lcpan;

our %SPEC;

$SPEC{'handle_cmd'} = {
    v => 1.1,
    summary => 'List subroutines',
    description => <<'_',

This subcommand lists subroutines/methods/static methods.

_
    args => {
        %App::lcpan::common_args,
        %App::lcpan::query_multi_args,
        query_type => {
            schema => ['str*', in=>[qw/any name exact-name/]],
            default => 'any',
        },
        # XXX include_method
        # XXX include_static_method
        # XXX include_function
        packages => {
            'x.name.is_plural' => 1,
            summary => 'Filter by package name(s)',
            schema => ['array*', of=>'str*', min_len=>1],
            element_completion => \&App::lcpan::_complete_mod,
            tags => ['category:filtering'],
        },
        authors => {
            'x.name.is_plural' => 1,
            summary => 'Filter by author(s) of module',
            schema => ['array*', of=>'str*', min_len=>1],
            element_completion => \&App::lcpan::_complete_cpanid,
            tags => ['category:filtering'],
        },
        %App::lcpan::sort_args_for_subs,
    },
};
sub handle_cmd {
    my %args = @_;

    my $state = App::lcpan::_init(\%args, 'ro');
    my $dbh = $state->{dbh};

    my @bind;
    my @where;
    #my @having;

    my $packages = $args{packages} // [];
    my $authors  = $args{authors} // [];
    my $qt = $args{query_type} // 'any';
    my $sort = $args{sort} // ['sub'];

    {
        my @q_where;
        for my $q0 (@{ $args{query} // [] }) {
            if ($qt eq 'any') {
                my $q = $q0 =~ /%/ ? $q0 : '%'.$q0.'%';
                push @q_where, "(sub.name LIKE ? OR content.package LIKE ?)";
                push @bind, $q, $q;
            } elsif ($qt eq 'name') {
                my $q = $q0 =~ /%/ ? $q0 : '%'.$q0.'%';
                push @q_where, "(sub.name LIKE ?)";
                push @bind, $q;
            } elsif ($qt eq 'exact-name') {
                push @q_where, "(sub.name=?)";
                push @bind, $q0;
            }
        }
        if (@q_where > 1) {
            push @where, "(".join(($args{or} ? " OR " : " AND "), @q_where).")";
        } elsif (@q_where == 1) {
            push @where, @q_where;
        }
    }
    if (@$packages) {
        my $packages_s = join(",", map {$dbh->quote($_)} @$packages);
        push @where, "(content.package IN ($packages_s))";
    }
    if (@$authors) {
        my $authors_s = join(",", map {$dbh->quote($_)} @$authors);
        push @where, "(file.cpanid IN ($authors_s))";
    }

    my @order;
    for (@$sort) { /\A(-?)(\w+)/ and push @order, $2 . ($1 ? " DESC" : "") }

    my $sql = "SELECT
  sub.name sub,
  content.package package,
  sub.linum linum,
  content.path content_path,
  file.name release,
  file.cpanid author
FROM sub
LEFT JOIN file ON sub.file_id=file.id
LEFT JOIN content ON sub.content_id=content.id
".
    (@where ? " WHERE ".join(" AND ", @where) : "").
    #(@having ? " HAVING ".join(" AND ", @having) : "");
    (@order ? " ORDER BY ".join(", ", @order) : "");

    my @res;
    my $sth = $dbh->prepare($sql);
    $sth->execute(@bind);
    while (my $row = $sth->fetchrow_hashref) {
        push @res, $args{detail} ? $row : $row->{sub};
    }
    my $resmeta = {};
    $resmeta->{'table.fields'} = [qw/sub package linum content_path release author/]
        if $args{detail};

    [200, "OK", \@res, $resmeta];
}

1;
# ABSTRACT:
