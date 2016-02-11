package App::lcpan::Cmd::mods_by_mention_count;

# DATE
# VERSION

use 5.010;
use strict;
use warnings;

require App::lcpan;

our %SPEC;

$SPEC{'handle_cmd'} = {
    v => 1.1,
    summary => 'List modules ranked by number of mentions',
    description => <<'_',

This shows the list of most mentioned modules, that is, modules who are
linked/referred to the most in PODs.

Unknown modules (modules not indexed) are not included. Note that mentions can
refer to unknown modules.

By default, each source module/script that mentions a module is counted as one
mention (`--count-per content`). Use `--count-per dist` to only count mentions
by modules/scripts from the same dist as one mention (so a module only gets a
maximum of 1 vote per dist). Use `--count-per author` to only count mentions by
modules/scripts from the same author as one mention (so a module only gets a
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
    },
};
sub handle_cmd {
    my %args = @_;

    my $state = App::lcpan::_init(\%args, 'ro');
    my $dbh = $state->{dbh};

    my $count_per = $args{count_per} // 'content';

    my @where = ("mention.module_id IS NOT NULL");

    push @where, "targetfile.cpanid <> srcfile.cpanid"
        unless $args{include_self_mentions};

    my $count = '*';
    if ($count_per eq 'dist') {
        $count = 'DISTINCT srcfile.id';
    } elsif ($count_per eq 'author') {
        $count = 'DISTINCT srcfile.cpanid';
    }

    my $sql = "SELECT
  module.name module,
  COUNT($count) AS mention_count,
  module.cpanid author,
  module.abstract abstract
FROM mention
LEFT JOIN file srcfile ON mention.source_file_id=srcfile.id
LEFT JOIN module ON mention.module_id=module.id
LEFT JOIN file targetfile ON module.file_id=targetfile.id
WHERE ".join(" AND ", @where)."
GROUP BY module.name
ORDER BY mention_count DESC
";

    my @res;
    my $sth = $dbh->prepare($sql);
    $sth->execute();
    while (my $row = $sth->fetchrow_hashref) {
        push @res, $row;
    }
    my $resmeta = {};
    $resmeta->{'table.fields'} = [qw/module mention_count author abstract/];
    [200, "OK", \@res, $resmeta];
}

1;
# ABSTRACT:
