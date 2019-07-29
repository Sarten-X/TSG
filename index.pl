#!/usr/bin/perl -T

use lib "/home/sartenx/perl5/lib/perl5/x86_64-linux-gnu-thread-multi";
use lib "/home/sartenx/perl5/lib/perl5/";
use lib "/home/sartenx/Web/tsg/";

# The following modules are required, and can be acquired from CPAN:
use CGI::Application;
use HTML::Template;
use Text::CSV_XS;


use warnings;
use strict;
use TSG;

my $applcation = TSG->new()->run();
