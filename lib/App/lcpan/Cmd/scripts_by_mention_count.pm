package App::lcpan::Cmd::scripts_by_mention_count;

use 5.010;
use strict;
use warnings;

require App::lcpan;

# AUTHORITY
# DATE
# DIST
# VERSION

our %SPEC;

$SPEC{'handle_cmd'} = {
    v => 1.1,
    summary => 'List scripts ranked by number of mentions',
    description => <<'_',

This shows the list of most mentioned scripts, that is, scripts who are
linked/referred to the most in PODs.

By default, each source module/script that mentions a script is counted as one
mention (`--count-per content`). Use `--count-per dist` to only count mentions
by modules/scripts from the same dist as one mention (so a script only gets a
maximum of 1 vote per dist). Use `--count-per author` to only count mentions by
modules/scripts from the same author as one mention (so a script only gets a
maximum of 1 vote per mentioning author).

By default, only mentions from other authors are included. Use
`--include-self-mentions` to also include mentions from the same author.

_
    args => {
        %App::lcpan::common_args,
        include_self_mentions => {
            schema => 'bool',
            default => 0,
        },
        count_per => {
            schema => ['str*', in=>['content', 'dist', 'author']],
            default => 'content',
        },
        n => {
            summary => 'Return at most this number of results',
            schema => 'posint*',
        },
    },
};
sub handle_cmd {
    my %args = @_;

    my $state = App::lcpan::_init(\%args, 'ro');
    my $dbh = $state->{dbh};

    my $count_per = $args{count_per} // 'content';

    my @where = ("mention.script_name IS NOT NULL");

    push @where, "targetfile.cpanid <> srcfile.cpanid"
        unless $args{include_self_mentions};

    my $count = '*';
    if ($count_per eq 'dist') {
        $count = 'DISTINCT srcfile.id';
    } elsif ($count_per eq 'author') {
        $count = 'DISTINCT srcfile.cpanid';
    }

    my $sql = "SELECT
  script.name script,
  targetfile.cpanid author,
  COUNT($count) AS mention_count
FROM mention
LEFT JOIN file srcfile ON mention.source_file_id=srcfile.id
LEFT JOIN script ON mention.script_name=script.name
LEFT JOIN file targetfile ON script.file_id=targetfile.id
WHERE ".join(" AND ", @where)."
GROUP BY script.name
ORDER BY mention_count DESC
".($args{n} ? "LIMIT ".(0+$args{n}) : "");

    my @res;
    my $sth = $dbh->prepare($sql);
    $sth->execute();
    while (my $row = $sth->fetchrow_hashref) {
        push @res, $row;
    }

    require Data::TableData::Rank;
    Data::TableData::Rank::add_rank_column_to_table(table => \@res, data_columns => ['mention_count']);

    my $resmeta = {};
    $resmeta->{'table.fields'} = [qw/rank script author mention_count/];
    [200, "OK", \@res, $resmeta];
}

1;
# ABSTRACT:
