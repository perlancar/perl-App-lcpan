package App::lcpan::Cmd::new_dists;

# AUTHORITY
# DATE
# DIST
# VERSION

use 5.010;
use strict;
use warnings;

require App::lcpan;

our %SPEC;

# note to self: we need to create and update `file_hist` first, then change the
# query to query `file_hist` instead of `file`.

$SPEC{'handle_cmd'} = {
    v => 1.1,
    summary => 'List new distributions',
    description => <<'_',

How this works: everytime you update the index (`lcpan update`), creation time
as well as update time are recorded in rows of the `file` table in database. In
addition to that, old dist records (for files/dists no longer indexed in
`02packages`) are stored in `file_hist`. Thus, we can query for dist that are
new (never seen before) at certain timestamp. This is not ideal, but better than
nothing. It works better the more often you update your index.

_
    args => {
        %App::lcpan::common_args,
        %App::lcpan::detail_args,
        %App::lcpan::argspecopt_since,
    },
};
sub handle_cmd {
    my %args = @_;

    $args{since_last_index_update} = 1
        if !defined $args{since} &&
        !$args{since_last_index_update} &&
        !$args{since_last_n_index_updates};

    my $state = App::lcpan::_init(\%args, 'ro');
    my $dbh = $state->{dbh};

    my @where;
    push @where, "NOT EXISTS(SELECT id FROM file f2 WHERE f2.dist_name=f.dist_name AND f2.rec_ctime < f.rec_ctime)"; # the earliest release of a dist
    App::lcpan::_set_since(\%args, $dbh);
    App::lcpan::_add_since_where_clause(\%args, \@where, 'f', 'ctime');

    my $detail = $args{detail};

    my $sth = $dbh->prepare("SELECT
  f.dist_name dist,
  f.dist_version latest_version,
  f.name name,
  f.cpanid author,
  f.rec_ctime add_time
FROM file f
WHERE ".join(" AND ", @where)."
ORDER BY f.rec_ctime DESC");
    $sth->execute();
    my @res;
    while (my $row = $sth->fetchrow_hashref) {
        push @res, $detail ? $row : $row->{dist};
    }
    my $resmeta = {};
    $resmeta->{'table.fields'}        = [qw/dist latest_version file author add_time/] if $detail;
    $resmeta->{'table.field_formats'} = [undef, undef, undef, undef, 'iso8601_datetime'] if $detail;
    [200, "OK", \@res, $resmeta];
}

1;
# ABSTRACT:
