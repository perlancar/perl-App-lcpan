package App::lcpan::Cmd::mentions;

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
    summary => 'List mentions',
    description => <<'_',

This subcommand lists mentions (references to modules/scripts in POD files
inside releases).

Only mentions to modules/scripts in another release are indexed (i.e. mentions
to modules/scripts in the same dist/release are not indexed). Only mentions to
known scripts are indexed, but mentions to unknown modules are also indexed.

_
    args => {
        %App::lcpan::common_args,
        type => {
            schema => ['str*', in=>['any', 'script', 'module', 'unknown-module', 'known-module']],
            default => 'any',
            tags => ['category:filtering'],
        },
        mentioned_module => {
            summary => 'Filter by module name being mentioned',
            schema => 'str*',
            completion => \&App::lcpan::_complete_mod,
            tags => ['category:filtering'],
        },
        mentioned_script => {
            summary => 'Filter by script name being mentioned',
            schema => 'str*',
            completion => \&App::lcpan::_complete_script,
            tags => ['category:filtering'],
        },
        mentioned_author => {
            summary => 'Filter by author of module/script being mentioned',
            schema => 'str*',
            tags => ['category:filtering'],
        },
        mentioner_author => {
            summary => 'Filter by author of module/script being mentioned',
            schema => 'str*',
            tags => ['category:filtering'],
        },
        #mentioner_authors_arent => {
        mentioner_author_isnt => {
            #'x.name.is_plural' => 1,
            #'x.name.singular' => 'mentioner_author_isnt',
            schema => ['array*', of=>'str*'],
            tags => ['category:filtering'],
        },
        #%App::lcpan::fauthor_args,
    },
};
sub handle_cmd {
    my %args = @_;

    my $state = App::lcpan::_init(\%args, 'ro');
    my $dbh = $state->{dbh};

    my $type = $args{type} // 'any';
    my $mentioned_module = $args{mentioned_module};
    my $mentioned_script = $args{mentioned_script};
    my $mentioned_author = $args{mentioned_author};
    my $mentioner_author = $args{mentioner_author};
    my $mentioner_authors_arent = $args{mentioner_author_isnt}; #$args{mentioner_authors_arent};

    my @bind;
    my @where;
    #my @having;

    if ($type eq 'script') {
        push @where, "mention.script_name IS NOT NULL";
    } elsif ($type eq 'module') {
        push @where, "(mention.module_id IS NOT NULL OR mention.module_name IS NOT NULL)";
    } elsif ($type eq 'known-module') {
        push @where, "mention.module_id IS NOT NULL";
    } elsif ($type eq 'unknown-module') {
        push @where, "mention.module_name IS NOT NULL";
    }

    if (defined $mentioned_module) {
        push @where, "(module.name=? OR mention.module_name=?)";
        push @bind, $mentioned_module, $mentioned_module;
    }

    if (defined $mentioned_script) {
        push @where, "mention.script_name=?";
        push @bind, $mentioned_script;
    }

    if (defined $mentioned_author) {
        $mentioned_author = uc($mentioned_author); # just to be sure
        push @where, "(module_author=? OR script_author=?)";
        push @bind, $mentioned_author, $mentioned_author;
    }

    if (defined $mentioner_author) {
        $mentioner_author = uc($mentioner_author); # just to be sure
        push @where, "mentioner_author=?";
        push @bind, $mentioner_author;
    }

    if (defined($mentioner_authors_arent) && @$mentioner_authors_arent) {
        for my $author (@$mentioner_authors_arent) {
            $author = uc($author); # just to be sure
            push @where, "mentioner_author <> ?";
            push @bind, $author;
        }
    }

    my $sql = "SELECT
  file.name release,
  content.path content_path,
  CASE WHEN module.name IS NOT NULL THEN module.name ELSE mention.module_name END AS module,
  module.cpanid module_author,
  mention.script_name script,
  (SELECT cpanid FROM script WHERE name=mention.script_name LIMIT 1) script_author,
  file.cpanid mentioner_author
FROM mention
LEFT JOIN file ON file.id=mention.source_file_id
LEFT JOIN content ON content.id=mention.source_content_id
LEFT JOIN module ON module.id=mention.module_id".
    (@where ? " WHERE ".join(" AND ", @where) : "");#.
    #(@having ? " HAVING ".join(" AND ", @having) : "");

    my @res;
    my $sth = $dbh->prepare($sql);
    $sth->execute(@bind);
    while (my $row = $sth->fetchrow_hashref) {
        if (defined($mentioned_module) || $type =~ /module/) {
            delete $row->{script};
            delete $row->{script_author};
        }
        if (defined($mentioned_script) || $type eq 'script') {
            delete $row->{module};
            delete $row->{module_author};
        }
        push @res, $row;
    }
    my $resmeta = {};
    $resmeta->{'table.fields'} = [qw/module script content_path release mentioner_author/];

    if (defined($mentioned_module) || $type =~ /module/) {
        $resmeta->{'table.fields'} =
            [grep {$_ ne 'script' && $_ ne 'script_author'} @{$resmeta->{'table.fields'}}];
    }
    if (defined($mentioned_script) || $type eq 'script') {
        $resmeta->{'table.fields'} =
            [grep {$_ ne 'module' && $_ ne 'module_author'} @{$resmeta->{'table.fields'}}];
    }

    [200, "OK", \@res, $resmeta];
}

1;
# ABSTRACT:
