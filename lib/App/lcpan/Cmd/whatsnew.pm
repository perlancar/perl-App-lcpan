package App::lcpan::Cmd::whatsnew;

# AUTHORITY
# DATE
# DIST
# VERSION

use 5.010001;
use strict;
use warnings;
use Log::ger;

require App::lcpan;
use Hash::Subset 'hash_subset';

our %SPEC;

$SPEC{'handle_cmd'} = {
    v => 1.1,
    summary => "Show what's added/updated recently",
    args => {
        %App::lcpan::common_args,
        %App::lcpan::fctime_or_mtime_args,
        my_author => {
            summary => 'My author ID',
            description => <<'_',

If specified, will show additional added/updated items for this author ID
("you"), e.g. what distributions recently added dependency to one of your
modules.

_
            schema => 'str*',
            cmdline_aliases => {a=>{}},
            completion => \&_complete_cpanid,
        },
    },
};
sub handle_cmd {
    require Perinci::Result::Format::Lite;
    require Text::Table::Org; # just to let scan-prereqs know

    my %args = @_;
    my $my_author = $args{my_author};

    my $state = App::lcpan::_init(\%args, 'ro');
    my $dbh = $state->{dbh};

    $args{added_or_updated_since_last_index_update} = 1 if !(grep {exists $App::lcpan::fctime_or_mtime_args{$_}} keys %args);
    App::lcpan::_set_since(\%args, $dbh);

    my $time = delete($args{added_or_updated_since});
    my $ftime = scalar(gmtime $time) . " UTC";

    my $org = '';

    local $ENV{FORMAT_PRETTY_TABLE_BACKEND} = 'Text::Table::Org';

    #$org .= "#+INFOJS_OPT: view:info toc:nil\n";
    $org .= "WHAT'S NEW SINCE $ftime\n\n";

  NEW_MODULES: {
        my ($res, $fres);
        $res = App::lcpan::modules(added_since=>$time, detail=>1);
        unless ($res->[0] == 200) {
            $org .= "Can't list new modules: $res->[0] - $res->[1]\n\n";
            last;
        }
        my $num = @{ $res->[2] };
        $org .= "* New modules ($num)\n";
        $fres = Perinci::Result::Format::Lite::format(
            $res, 'text-pretty', 0, 0);
        $org .= $fres;
        $org .= "\n";
    }

  UPDATED_MODULES: {
        my ($res, $fres);
        $res = App::lcpan::modules(updated_since=>$time, detail=>1);
        unless ($res->[0] == 200) {
            $org .= "Can't list updated modules: $res->[0] - $res->[1]\n\n";
            last;
        }
        my $num = @{ $res->[2] };
        $org .= "* Updated modules ($num)\n";
        $fres = Perinci::Result::Format::Lite::format(
            $res, 'text-pretty', 0, 0);
        $org .= $fres;
        $org .= "\n";
    }

  NEW_AUTHORS: {
        my ($res, $fres);
        $res = App::lcpan::authors(added_since=>$time, detail=>1);
        unless ($res->[0] == 200) {
            $org .= "Can't list new authors: $res->[0] - $res->[1]\n\n";
            last;
        }
        my $num = @{ $res->[2] };
        $org .= "* New authors ($num)\n";
        $fres = Perinci::Result::Format::Lite::format(
            $res, 'text-pretty', 0, 0);
        $org .= $fres;
        $org .= "\n";
    }

  UPDATED_AUTHORS: {
        my ($res, $fres);
        $res = App::lcpan::authors(updated_since=>$time, detail=>1);
        unless ($res->[0] == 200) {
            $org .= "Can't list updated authors: $res->[0] - $res->[1]\n\n";
            last;
        }
        my $num = @{ $res->[2] };
        $org .= "* Updated authors ($num)\n";
        $fres = Perinci::Result::Format::Lite::format(
            $res, 'text-pretty', 0, 0);
        $org .= $fres;
        $org .= "\n";
    }

  NEW_REVERSE_DEPENDENCIES: {
        last unless defined $my_author;
        my ($res, $fres);
        require App::lcpan::Cmd::author_rdeps;
        $res = App::lcpan::Cmd::author_rdeps::handle_cmd(
            author=>$my_author, user_authors_arent=>[$my_author],
            added_since=>$time,
            phase => 'ALL',
            rel => 'ALL',
        );
        unless ($res->[0] == 200) {
            $org .= "Can't list new reverse dependencies for modules of $my_author: $res->[0] - $res->[1]\n\n";
            last;
        }
        my $num = @{ $res->[2] };
        $org .= "* Distributions of other authors recently depending on one of $my_author\'s modules ($num)\n";
        $fres = Perinci::Result::Format::Lite::format(
            $res, 'text-pretty', 0, 0);
        $org .= $fres;
        $org .= "\n";
    }

  UPDATED_REVERSE_DEPENDENCIES: {
        # skip for now, usually empty. because dep records are usually not
        # updated but recreated.
        last;

        last unless defined $my_author;
        my ($res, $fres);
        require App::lcpan::Cmd::author_rdeps;
        $res = App::lcpan::Cmd::author_rdeps::handle_cmd(
            author=>$my_author, user_authors_arent=>[$my_author], updated_since=>$time,
            phase => 'ALL',
            rel => 'ALL',
        );
        unless ($res->[0] == 200) {
            $org .= "Can't list updated reverse dependencies for modules of $my_author: $res->[0] - $res->[1]\n\n";
            last;
        }
        my $num = @{ $res->[2] };
        $org .= "* Distributions of other authors which updated dependencies to one of $my_author\'s modules ($num)\n";
        $fres = Perinci::Result::Format::Lite::format(
            $res, 'text-pretty', 0, 0);
        $org .= $fres;
        $org .= "\n";
    }

    [200, "OK", $org, {'content_type' => 'text/x-org'}];
}

1;
# ABSTRACT:
