package App::lcpan::Cmd::related_mods;

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
        min_score => {
            schema => 'float*',
        },
        sort => {
            schema => ['array*', of=>['str*', in=>[map {($_,"-$_")} qw/score num_mentions num_mentions_together pct_mentions_together module/]], min_len=>1],
            default => ['-score', '-num_mentions'],
        },
    },
};
sub handle_cmd {
    my %args = @_;

    my $state = App::lcpan::_init(\%args, 'rw');
    my $dbh = $state->{dbh};

    my $modules = $args{modules};
    my $modules_s = join(",", map {$dbh->quote($_)} @$modules);

    # number of mentions of target modules
    my ($num_mentions) = $dbh->selectrow_array(
        "SELECT COUNT(*) FROM mention WHERE module_id IN (SELECT id FROM module m2 WHERE name IN ($modules_s))");

    return [400, "No mentions for module(s)"] if $num_mentions < 1;

    $log->debugf("num_mentions for %s: %d", $modules, $num_mentions);

    # default min_score is currently tuned manually
    my $min_score = $args{min_score} // (
        $num_mentions >= 12 ? 200 :
        $num_mentions >= 10 ? 100 :
        $num_mentions >=  4 ?  50 : 25);

    $log->debugf("min_score: %f", $min_score);

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
  m2.cpanid author
FROM mention mtn1
LEFT JOIN module m2 ON mtn1.module_id=m2.id
WHERE
  mtn1.source_content_id IN (SELECT source_content_id FROM mention mtn2 WHERE  module_id IN (SELECT id FROM module m2 WHERE name IN ($modules_s))) AND
  m2.name NOT IN ($modules_s)
GROUP BY m2.name
HAVING score >= $min_score".
    (@order ? "\nORDER BY ".join(", ", @order) : "");

    my @res;
    my $sth = $dbh->prepare($sql);
    $sth->execute();
    while (my $row = $sth->fetchrow_hashref) {
        push @res, $row;
    }
    my $resmeta = {};
    $resmeta->{'table.fields'} = [qw/module abstract num_mentions num_mentions_together pct_mentions_together score author/];

    [200, "OK", \@res, $resmeta];
}

1;
# ABSTRACT:
