package App::lcpan::Cmd::related_authors;

use 5.010001;
use strict;
use warnings;
use Log::ger;

require App::lcpan;

# AUTHORITY
# DATE
# DIST
# VERSION

our %SPEC;

$SPEC{'handle_cmd'} = {
    v => 1.1,
    summary => 'List other authors related to author(s)',
    description => <<'_',

This subcommand lists other authors that might be related to the author(s) you
specify. This is done in one of the ways below which you can choose.

1. (the default) by finding authors whose modules tend to be mentioned together
in POD documentation.

_
    args => {
        %App::lcpan::common_args,
        %App::lcpan::authors_args,
        #%App::lcpan::detail_args,
        limit => {
            summary => 'Maximum number of authors to return',
            schema => ['int*', min=>0],
            default => 20,
        },
        with_scores => {
            summary => 'Return score-related fields',
            schema => 'bool*',
        },
        #with_content_paths => {
        #    summary => 'Return the list of content paths where the authors\' module and the module of a related author are mentioned together',
        #    schema => 'bool*',
        #},
        sort => {
            schema => ['array*', of=>['str*', in=>[map {($_,"-$_")} qw/score num_module_mentions num_module_mentions_together pct_module_mentions_together author/]], min_len=>1],
            default => ['-score', '-num_module_mentions'],
        },
    },
};
sub handle_cmd {
    my %args = @_;

    my $state = App::lcpan::_init(\%args, 'ro');
    my $dbh = $state->{dbh};

    my $authors = $args{authors};
    my $authors_s = join(",", map {$dbh->quote(uc $_)} @$authors);

    #if ($args{with_content_paths} && @$modules > 1) {
    #    return [412, "Sorry, --with-content-paths currently works with only one specified module"];
    #}

    my $limit = $args{limit};

    # authors' modules
    my @modules;
    my $sth_authors_modules = $dbh->prepare(
        "SELECT name FROM module WHERE file_id IN (SELECT id FROM file WHERE cpanid IN ($authors_s))");
    $sth_authors_modules->execute;
    while (my @row = $sth_authors_modules->fetchrow_array) {
        push @modules, $row[0];
    }
    log_trace("num_modules released by %s: %d", $authors, scalar(@modules));
    return [400, "No modules released by author(s)"] unless @modules;
    my $modules_s = join(",", map {$dbh->quote($_)} @modules);

    # number of mentions of target modules
    my ($num_module_mentions) = $dbh->selectrow_array(
        "SELECT COUNT(*) FROM mention WHERE module_id IN (SELECT id FROM module m2 WHERE name IN ($modules_s))");

    return [400, "No module mentions for author(s)"] if $num_module_mentions < 1;

    log_debug("num_module_mentions for %s: %d", $authors, $num_module_mentions);

    my @join = (
        "LEFT JOIN module m2 ON mtn1.module_id=m2.id",
        "LEFT JOIN file f ON m2.file_id=f.id",
    );

    my @where = (
        "mtn1.source_content_id IN (SELECT source_content_id FROM mention mtn2 WHERE  module_id IN (SELECT id FROM module m2 WHERE name IN ($modules_s)))",
        "m2.cpanid NOT IN ($authors_s)",
    );

    my @order = map {/(-?)(.+)/; $2 . ($1 ? " DESC" : "")} @{$args{sort}};

    # sql parts, to make SQL statement readable
    my $sp_num_module_mentions = "SELECT COUNT(*) FROM mention mnt3 WHERE module_id=m2.id";
    my $sp_pct_module_mentions_together = "ROUND(100.0 * COUNT(*)/($sp_num_module_mentions), 2)";

    my $sql = "SELECT
  m2.cpanid author,
  ($sp_num_module_mentions) num_module_mentions,
  COUNT(*) num_module_mentions_together,
  ($sp_pct_module_mentions_together) pct_module_mentions_together,
  (COUNT(*) * COUNT(*) * ($sp_pct_module_mentions_together)) score
FROM mention mtn1
".join("\n", @join)."
WHERE ".join(" AND ", @where)."
GROUP BY m2.cpanid
    ".(@order ? "\nORDER BY ".join(", ", @order) : "")."
LIMIT $limit
";

#    my $sql_with_content_paths;
#    my $sth_with_content_paths;
#    if ($args{with_content_paths}) {
#        $sql_with_content_paths = "SELECT
#  path
#FROM content c
#WHERE
#  EXISTS(SELECT id FROM mention WHERE module_id=(SELECT id FROM module WHERE name=?) AND source_content_id=c.id) AND
#  EXISTS(SELECT id FROM mention WHERE module_id=(SELECT id FROM module WHERE name=?) AND source_content_id=c.id)
#";
#        $sth_with_content_paths = $dbh->prepare($sql_with_content_paths);#
#    }

    my @res;
    my $sth = $dbh->prepare($sql);
    $sth->execute();
    while (my $row = $sth->fetchrow_hashref) {
        unless ($args{with_scores}) {
            delete $row->{$_} for qw(num_module_mentions num_module_mentions_together pct_module_mentions_together score);
        }
        #if ($args{with_content_paths}) {
        #    my @content_paths;
        #    $sth_with_content_paths->execute($modules->[0], $row->{module});
        #    while (my $row2 = $sth_with_content_paths->fetchrow_arrayref) {
        #        push @content_paths, $row2->[0];
        #    }
        #    $sth_with_content_paths->finish;
        #    $row->{content_paths} = \@content_paths;
        #}
        push @res, $row;
    }
    my $resmeta = {};
    $resmeta->{'table.fields'} = [qw/author num_module_mentions num_module_mentions_together pct_module_mentions_together score/];

    [200, "OK", \@res, $resmeta];
}

1;
# ABSTRACT:
