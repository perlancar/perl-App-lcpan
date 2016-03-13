package App::lcpan::Cmd::changes;

# DATE
# VERSION

use 5.010;
use strict;
use warnings;

use Encode qw(decode);

require App::lcpan;

our %SPEC;

$SPEC{'handle_cmd'} = {
    v => 1.1,
    summary => 'Show Changes of distribution/module',
    description => <<'_',

This command will find a file named Changes/CHANGES/ChangeLog or other similar
name in the top-level directory inside the release tarballs and show it.

_
    args => {
        %App::lcpan::common_args,
        %App::lcpan::mod_or_dist_args,
        #parse => {
        #    summary => 'Parse with CPAN::Changes',
        #    schema => 'bool',
        #}.
    },
    examples => [
        {
            summary => 'Use module name',
            argv => ['Data::CSel::Parser'],
            test => 0,
            'x.doc.show_result' => 0,
        },
        #{
        #    summary => 'Use dist name, parse',
        #    argv => ['--parse', 'App-PMUtils'],
        #    test => 0,
        #    'x.doc.show_result' => 0,
        #},
    ],
};
sub handle_cmd {
    my %args = @_;

    my $state = App::lcpan::_init(\%args, 'ro');
    my $dbh = $state->{dbh};

    my $mod_or_dist = $args{module_or_dist};
    $mod_or_dist =~ s!/!::!g; # XXX this should be done by coercer

    my @join;
    my @where;
    my @bind;

    if ($mod_or_dist =~ /-/) {
        push @where, "file.id = (SELECT file_id FROM dist WHERE name=? ORDER BY version_numified DESC LIMIT 1)";
        push @bind, $mod_or_dist;
    } else {
        push @where, "file.id = (SELECT file_id FROM module WHERE name=? LIMIT 1)";
        push @bind, $mod_or_dist;
    }

    my $sql = "SELECT
  content.path content_path,
  file.cpanid author,
  file.name release
FROM content
LEFT JOIN file ON content.file_id=file.id
".(@join  ? join(" ", @join) : "")."
".(@where ? " WHERE ".join(" AND ", @where) : "")."
ORDER BY content.path";
    my $sth = $dbh->prepare($sql);
    $sth->execute(@bind);

    my $first_row;
    while (my $row = $sth->fetchrow_hashref) {
        $first_row //= $row;
        next unless $row->{content_path} =~ m!\A
                                              (?:[^/]+/)?
                                              (changes|changelog)
                                              (?:\.(\w+))?\z!ix;
        # XXX handle YAML file
        my $path = App::lcpan::_fullpath(
            $row->{release}, $state->{cpan}, $row->{author});

        # XXX needs to be refactored into common code (see also doc subcommand)
        my $content;
        if ($path =~ /\.zip$/i) {
            require Archive::Zip;
            my $zip = Archive::Zip->new;
            $zip->read($path) == Archive::Zip::AZ_OK()
                or return [500, "Can't read zip file '$path'"];
            $content = $zip->contents($row->{content_path});
        } else {
            require Archive::Tar;
            my $tar;
            eval {
                $tar = Archive::Tar->new;
                $content = $tar->read($path); # can still die untrapped when out of mem
            };
            return [500, "Can't read tar file '$path': $@"] if $@;
            my ($obj) = $tar->get_files($row->{content_path});
            $content = $obj->get_content;
        }

        return [200, "OK", $content, {
            'func.content_path' => $row->{content_path},
            'cmdline.skip_format'=>1,
            "cmdline.page_result"=>1,
        }];
    }

    if ($first_row) {
        return [404, "No Changes file found in $first_row->{release}"];
    } else {
        return [404, "No such module or dist"];
    }
}

1;
# ABSTRACT:
