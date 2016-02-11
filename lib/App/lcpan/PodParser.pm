package App::lcpan::PodParser;

# DATE
# VERSION

use 5.010;
use strict;
use warnings;
use Log::Any::IfLOG '$log';

use parent qw(Pod::Simple::Methody);

use List::Util qw(first);

sub handle_text {
    my $self = shift;

    # to reduce false positive with regular words, in naked text we only look
    # for modules that have namespaces, e.g. 'Foo::Bar' and not top-level
    # modules like 'strict' or 'warnings'. we also don't look for scripts
    # because script names might be regular words or proper nouns too like 'yes'
    # or 'wikipedia'.
    while ($_[0] =~ /\b([A-Za-z_][A-Za-z0-9_]*(?:::[A-Za-z0-9_]+)+)\b/g) {
        my ($module_id, $module_name);
        if ($self->{module_ids}{$1}) {

            # skip if mention target is in the same release
            next if $self->{module_file_ids}{$1} == $self->{file_id};

            $log->tracef("    found a mention in naked text to known module: %s", $1);
            $module_id = $self->{module_ids}{$1};
        } else {
            $log->tracef("    found a mention in naked text to unknown module: %s", $1);
            $module_name = $1;
        }
        $self->{sth_ins_mention}->execute(
            $self->{content_id}, $self->{file_id}, $module_id, $module_name, undef);
    }
}

sub start_L {
    my $self = shift;

    return unless $_[0]{type} eq 'pod' && $_[0]{to};
    my $to = "" . $_[0]{to};

    my ($module_id, $module_name, $script_name);
    if ($self->{module_ids}{$to}) {

        # skip if mention target is in the same release
        return if $self->{module_file_ids}{$to} == $self->{file_id};

        $log->tracef("    found a mention in POD link to known module: %s", $to);
        $module_id = $self->{module_ids}{$to};
    } elsif ($to =~ $self->{scripts_re}) {

        # skip if mention target is in the same release
        return if first { $_==$self->{file_id} } @{ $self->{script_file_ids}{$to} };

        $log->tracef("    found a mention in POD link to known script: %s", $to);
        $script_name = $to;
    } elsif ($to =~ /\A([A-Za-z_][A-Za-z0-9_]*(?:::[A-Za-z0-9_]+)*)\z/) {
        $log->tracef("    found a mention in POD link to unknown module: %s", $to);
        $module_name = $to;
    } else {
        # name doesn't look like a module name, skip
        return;
    }
    $self->{sth_ins_mention}->execute(
        $self->{content_id}, $self->{file_id}, $module_id, $module_name, $script_name);
}

1;
# ABSTRACT: Pod parser for use in App::lcpan

=for Pod::Coverage .+
