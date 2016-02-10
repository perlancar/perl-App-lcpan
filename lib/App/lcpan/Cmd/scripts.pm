package App::lcpan::Cmd::scripts;

# DATE
# VERSION

use 5.010;
use strict;
use warnings;

require App::lcpan;

our %SPEC;

$SPEC{'handle_cmd'} = {
    v => 1.1,
    summary => 'List scripts',
    description => <<'_',

This subcommand lists scripts. Scripts are identified heuristically from
contents of release archives matching this regex:

    #         container dir,  script dir,       script name
    \A (\./)? ([^/]+)/?       (s?bin|scripts?)/ ([^/]+) \z

A few exception are excluded, e.g. if script name begins with a dot (e.g.
`bin/.exists` which is usually a marker only).

Scripts are currently indexed by its release file and its name, so if a single
release contains both `bin/foo` and `script/foo`, only one of those will be
indexed. Normally a proper release shouldn't be like that though.

_
    args => {
        %App::lcpan::common_args,
        %App::lcpan::fauthor_args,
        %App::lcpan::fdist_args,
        %App::lcpan::query_multi_args,
        query_type => {
            schema => ['str*', in=>[qw/any name exact-name/]],
            default => 'any',
        },
        #%App::lcpan::dist_args,
        # all=>1
    },
};
sub handle_cmd {
    my %args = @_;

    my $state = App::lcpan::_init(\%args, 'ro');
    my $dbh = $state->{dbh};

    my $detail = $args{detail};
    my $author = uc($args{author} // '');
    my $dist = $args{dist};
    my $qt = $args{query_type} // 'any';

    my @bind;
    my @where;
    {
        my @q_where;
        for my $q0 (@{ $args{query} // [] }) {
            if ($qt eq 'any' || $qt eq 'name') {
                my $q = $q0 =~ /%/ ? $q0 : '%'.$q0.'%';
                push @q_where, "(script.name LIKE ?)";
                push @bind, $q;
            } elsif ($qt eq 'exact-name') {
                push @q_where, "(script.name=?)";
                push @bind, $q0;
            }
        }
        if (@q_where > 1) {
            push @where, "(".join(($args{or} ? " OR " : " AND "), @q_where).")";
        } elsif (@q_where == 1) {
            push @where, @q_where;
        }
    }
    if ($author) {
        push @where, "(script.cpanid=?)";
        push @bind, $author;
    }
    if ($dist) {
        push @where, "(script.file_id=(SELECT file_id FROM dist WHERE name=?))";
        push @bind, $dist;
    }

    my $sql = "SELECT
  file.name release,
  script.cpanid cpanid,
  script.name name
FROM script
LEFT JOIN file ON file.id=script.file_id".
    (@where ? " WHERE ".join(" AND ", @where) : "");

    my @res;
    my $sth = $dbh->prepare($sql);
    $sth->execute(@bind);
    while (my $row = $sth->fetchrow_hashref) {
        push @res, $detail ? $row : $row->{name};
    }
    my $resmeta = {};
    $resmeta->{'table.fields'} = [qw/name release cpanid/]
        if $detail;
    [200, "OK", \@res, $resmeta];
}

1;
# ABSTRACT:
