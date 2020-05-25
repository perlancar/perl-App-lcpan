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

our %SPEC;

$SPEC{'handle_cmd'} = {
    v => 1.1,
    summary => "Show what's added/updated recently",
    args => {
        %App::lcpan::common_args,
        %App::lcpan::ftime_args,
    },
};
sub handle_cmd {
    require Perinci::Result::Format::Lite;
    require Text::Table::Org; # just to let scan-prereqs know

    my %args = @_;

    my $state = App::lcpan::_init(\%args, 'ro');
    my $dbh = $state->{dbh};

    $args{in_last_update} = 1 if !$args{in_last_n_updates} && !$args{after};
    App::lcpan::_set_after_from_in_last_update_or_n_updates(\%args, $dbh);
    my $time = delete($args{after});
    my $ftime = scalar(gmtime $time) . " UTC";

    my ($res, $fres);
    my $org = '';

    local $ENV{FORMAT_PRETTY_TABLE_BACKEND} = 'Text::Table::Org';

    $org .= "#+INFOJS_OPT: view:info toc:nil\n";
    $org .= "* WHAT'S NEW/UPDATED AFTER $ftime\n\n";

  NEW_MODULES: {
        $res = App::lcpan::modules(added_after=>$time, detail=>1);
        unless ($res->[0] == 200) {
            $org .= "Can't list new modules: $res->[0] - $res->[1]\n\n";
            last;
        }
        my $num = @{ $res->[2] };
        $org .= "** New modules ($num)\n";
        $fres = Perinci::Result::Format::Lite::format(
            $res, 'text-pretty', 0, 0);
        $org .= $fres;
        $org .= "\n";
    }

  UPDATED_MODULES: {
        $res = App::lcpan::modules(updated_after=>$time, detail=>1);
        unless ($res->[0] == 200) {
            $org .= "Can't list updated modules: $res->[0] - $res->[1]\n\n";
            last;
        }
        my $num = @{ $res->[2] };
        $org .= "** Updated modules ($num)\n";
        $fres = Perinci::Result::Format::Lite::format(
            $res, 'text-pretty', 0, 0);
        $org .= $fres;
        $org .= "\n";
    }

  NEW_AUTHORS: {
        $res = App::lcpan::authors(added_after=>$time, detail=>1);
        unless ($res->[0] == 200) {
            $org .= "Can't list new authors: $res->[0] - $res->[1]\n\n";
            last;
        }
        my $num = @{ $res->[2] };
        $org .= "** New authors ($num)\n";
        $fres = Perinci::Result::Format::Lite::format(
            $res, 'text-pretty', 0, 0);
        $org .= $fres;
        $org .= "\n";
    }

  UPDATED_AUTHORS: {
        $res = App::lcpan::authors(updated_after=>$time, detail=>1);
        unless ($res->[0] == 200) {
            $org .= "Can't list updated authors: $res->[0] - $res->[1]\n\n";
            last;
        }
        my $num = @{ $res->[2] };
        $org .= "** Updated authors ($num)\n";
        $fres = Perinci::Result::Format::Lite::format(
            $res, 'text-pretty', 0, 0);
        $org .= $fres;
        $org .= "\n";
    }

    [200, "OK", $org, {'content_type' => 'text/x-org'}];
}

1;
# ABSTRACT:
