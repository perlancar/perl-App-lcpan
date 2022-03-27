package App::lcpan::Cmd::authors_by_mod_mention_count;

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
    summary => 'List authors ranked by number of module mentions',
    description => <<'_',

This shows the list of most mentioned authors, that is, authors whose modules
are linked/referred to the most in PODs.

By default, each source module/script that mentions a module from author is
counted as one mention (`--count-per content`). Use `--count-per dist` to only
count mentions by modules/scripts from the same dist as one mention (so an
author only gets a maximum of 1 vote per dist). Use `--count-per author` to only
count mentions by modules/scripts from the same author as one mention (so an
author only gets a maximum of 1 vote per mentioning author).

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
    },
};
sub handle_cmd {
    my %args = @_;

    my $state = App::lcpan::_init(\%args, 'ro');
    my $dbh = $state->{dbh};

    my $count_per = $args{count_per} // 'content';

    my @where = ("author IS NOT NULL");

    push @where, "file.cpanid <> author"
        unless $args{include_self_mentions};

    my $count = '*';
    if ($count_per eq 'dist') {
        $count = 'DISTINCT file.id';
    } elsif ($count_per eq 'author') {
        $count = 'DISTINCT file.cpanid';
    }

    my $sql = "SELECT
  module.cpanid author,
  COUNT($count) AS mod_mention_count
FROM mention
LEFT JOIN file ON mention.source_file_id=file.id
LEFT JOIN module ON module.id=mention.module_id
WHERE ".join(" AND ", @where)."
GROUP BY module.cpanid
ORDER BY mod_mention_count DESC
";

    my @res;
    my $sth = $dbh->prepare($sql);
    $sth->execute();
    while (my $row = $sth->fetchrow_hashref) {
        push @res, $row;
    }
    my $resmeta = {};
    $resmeta->{'table.fields'} = [qw/author mod_mention_count/];
    [200, "OK", \@res, $resmeta];
}

1;
# ABSTRACT:
