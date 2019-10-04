package End::PrintBytesIn;

# DATE
# VERSION

use 5.010001;
use strict;
use warnings;

use Number::Format::Metric;

END {
    printf "Total downloaded data: %sb\n",
        Number::Format::Metric::format_metric($LWP::Protocol::Patch::CountBytes::bytes_in // 0);
}

1;
# ABSTRACT: Show LWP::Protocol::Patch::CountBytesIn::bytes_in

=head1 SYNOPSIS


=head1 DESCRIPTION


=head1 SEE ALSO

L<LWP::Protocol::Patch::CountBytesIn>

=cut
