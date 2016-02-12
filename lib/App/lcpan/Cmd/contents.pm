package App::lcpan::Cmd::contents;

# DATE
# VERSION

use 5.010;
use strict;
use warnings;

require App::lcpan;

our %SPEC;

$SPEC{'handle_cmd'} = {
    v => 1.1,
    summary => 'List contents inside releases',
    description => <<'_',

This subcommand lists files inside release archives.

_
    args => {
        %App::lcpan::common_args,
        %App::lcpan::fauthor_args,
        %App::lcpan::fdist_args,
        "package" => {
            schema => 'str*',
            tags => ['category:filtering'],
        },
        %App::lcpan::query_multi_args,
        query_type => {
            schema => ['str*', in=>[qw/any path exact-path package
                                       exact-package/]],
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
    my $package = $args{package};
    my $qt = $args{query_type} // 'any';

    my @bind;
    my @where;
    {
        my @q_where;
        for my $q0 (@{ $args{query} // [] }) {
            if ($qt eq 'any') {
                my $q = $q0 =~ /%/ ? $q0 : '%'.$q0.'%';
                push @q_where, "(content.path LIKE ? OR package LIKE ?)";
                push @bind, $q, $q;
            } elsif ($qt eq 'path') {
                my $q = $q0 =~ /%/ ? $q0 : '%'.$q0.'%';
                push @q_where, "(content.path LIKE ?)";
                push @bind, $q;
            } elsif ($qt eq 'exact-path') {
                push @q_where, "(content.path=?)";
                push @bind, $q0;
            } elsif ($qt eq 'package') {
                my $q = $q0 =~ /%/ ? $q0 : '%'.$q0.'%';
                push @q_where, "(content.package LIKE ?)";
                push @bind, $q;
            } elsif ($qt eq 'exact-package') {
                push @q_where, "(content.package=?)";
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
        push @where, "(file.cpanid=?)";
        push @bind, $author;
    }
    if ($dist) {
        push @where, "(file.id=(SELECT file_id FROM dist WHERE name=?))";
        push @bind, $dist;
    }
    if ($package) {
        push @where, "content.package=?";
        push @bind, $package;
    }

    my $sql = "SELECT
  file.cpanid cpanid,
  file.name release,
  content.path path,
  content.mtime mtime,
  content.size size,
  content.package AS package
FROM content
LEFT JOIN file ON content.file_id=file.id
".
    (@where ? " WHERE ".join(" AND ", @where) : "");

    my @res;
    my $sth = $dbh->prepare($sql);
    $sth->execute(@bind);
    while (my $row = $sth->fetchrow_hashref) {
        push @res, $detail ? $row : $row->{path};
    }
    my $resmeta = {};
    $resmeta->{'table.fields'} = [qw/path release cpanid mtime size package/]
        if $detail;
    [200, "OK", \@res, $resmeta];
}

1;
# ABSTRACT:
