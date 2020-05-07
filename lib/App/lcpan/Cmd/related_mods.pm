package App::lcpan::Cmd::related_mods;

# AUTHORITY
# DATE
# DIST
# VERSION

use 5.010;
use strict;
use warnings;
use Log::ger;

require App::lcpan;

our %SPEC;

$SPEC{'handle_cmd'} = {
    v => 1.1,
    summary => 'List other modules related to module(s)',
    description => <<'_',

This subcommand lists other modules that might be related to the module(s) you
specify. This is done by listing modules that tend be mentioned together in POD
documentation.

The scoring/ranking still needs to be tuned.

_
    args => {
        %App::lcpan::common_args,
        %App::lcpan::mods_args,
        #%App::lcpan::detail_args,
        limit => {
            summary => 'Maximum number of modules to return',
            schema => ['int*', min=>0],
            default => 20,
        },
        with_scores => {
            summary => 'Return score-related fields',
            schema => 'bool*',
        },
        sort => {
            schema => ['array*', of=>['str*', in=>[map {($_,"-$_")} qw/score num_mentions num_mentions_together pct_mentions_together module/]], min_len=>1],
            default => ['-score', '-num_mentions'],
        },
        skip_same_dist => {
            summary => 'Skip modules from the same distribution',
            schema => 'bool*',
            tags => ['category:filtering'],
        },
    },
};
sub handle_cmd {
    my %args = @_;

    my $state = App::lcpan::_init(\%args, 'ro');
    my $dbh = $state->{dbh};

    my $modules = $args{modules};
    my $modules_s = join(",", map {$dbh->quote($_)} @$modules);

    my $limit = $args{limit};

    # number of mentions of target modules
    my ($num_mentions) = $dbh->selectrow_array(
        "SELECT COUNT(*) FROM mention WHERE module_id IN (SELECT id FROM module m2 WHERE name IN ($modules_s))");

    return [400, "No mentions for module(s)"] if $num_mentions < 1;

    log_debug("num_mentions for %s: %d", $modules, $num_mentions);

    my @join = (
        "LEFT JOIN module m2 ON mtn1.module_id=m2.id",
        "LEFT JOIN file f ON m2.file_id=f.id",
    );

    my @where = (
        "mtn1.source_content_id IN (SELECT source_content_id FROM mention mtn2 WHERE  module_id IN (SELECT id FROM module m2 WHERE name IN ($modules_s)))",
        "m2.name NOT IN ($modules_s)",
    );

    my @dist_names;
    if ($args{skip_same_dist}) {
        my $sth = $dbh->prepare(
            "SELECT DISTINCT dist_name FROM file WHERE dist_name IS NOT NULL AND id IN (SELECT file_id FROM module WHERE name IN ($modules_s))");
        $sth->execute;
        while (my ($dist_name) = $sth->fetchrow_array) {
            push @dist_names, $dist_name;
        }
        push @where, "f.dist_name NOT IN (".join(", ", map { $dbh->quote($_) } @dist_names).")";
    }

    my @order = map {/(-?)(.+)/; $2 . ($1 ? " DESC" : "")} @{$args{sort}};

    # sql parts, to make SQL statement readable
    my $sp_num_mentions = "SELECT COUNT(*) FROM mention mnt3 WHERE module_id=m2.id";
    my $sp_pct_mentions_together = "ROUND(100.0 * COUNT(*)/($sp_num_mentions), 2)";

    my $sql = "SELECT
  m2.name module,
  m2.abstract abstract,
  ($sp_num_mentions) num_mentions,
  COUNT(*) num_mentions_together,
  ($sp_pct_mentions_together) pct_mentions_together,
  (COUNT(*) * COUNT(*) * ($sp_pct_mentions_together)) score,
  f.dist_name dist,
  m2.cpanid author
FROM mention mtn1
".join("\n", @join)."
WHERE ".join(" AND ", @where)."
GROUP BY m2.name
    ".(@order ? "\nORDER BY ".join(", ", @order) : "")."
LIMIT $limit
";

    my @res;
    my $sth = $dbh->prepare($sql);
    $sth->execute();
    while (my $row = $sth->fetchrow_hashref) {
        unless ($args{with_scores}) {
            delete $row->{$_} for qw(num_mentions num_mentions_together pct_mentions_together score);
        }
        push @res, $row;
    }
    my $resmeta = {};
    $resmeta->{'table.fields'} = [qw/module abstract num_mentions num_mentions_together pct_mentions_together score dist author/];

    [200, "OK", \@res, $resmeta];
}

1;
# ABSTRACT:
