package ep::Config;
use strict;

=head1 NAME

ep::Config - The Extopus File

=head1 SYNOPSIS

 use ep::Config;

 my $parser = ep::Config->new(file=>'/etc/extopus/system.cfg');

 my $cfg = $parser->parse_config();
 my $pod = $parser->make_pod();

=head1 DESCRIPTION

Configuration reader for Extopus

=cut

use vars qw($VERSION);
$VERSION   = '0.01';
use Carp;
use Config::Grammar;
use Mojo::Base -base;

has 'file';
    

=head1 METHODS

All methods inherited from L<Mojo::Base>. As well as the following:

=cut

=head2 $x->B<parse_config>(I<path_to_config_file>)

Read the configuration file and die if there is a problem.

=cut

sub parse_config {
    my $self = shift;
    my $cfg_file = shift;
    my $parser = $self->_make_parser();
    my $cfg = $parser->parse($self->file) or croak($parser->{err});
    return $cfg;
}

=head2 $x->B<make_config_pod>()

Create a pod documentation file based on the information from all config actions.

=cut

sub make_pod {
    my $self = shift;
    my $parser = $self->_make_parser();
    my $E = '=';
    my $footer = <<"FOOTER";

${E}head1 COPYRIGHT

Copyright (c) 2011 by OETIKER+PARTNER AG. All rights reserved.

${E}head1 LICENSE

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.

${E}head1 AUTHOR

S<Tobias Oetiker E<lt>tobi\@oetiker.chE<gt>>

${E}head1 HISTORY

 2011-04-19 to 1.0 first version

FOOTER
    my $header = $self->_make_pod_header();    
    return $header.$parser->makepod().$footer;
}



=item $x->B<_make_pod_header>()

Returns the header of the cfg pod file.

=cut

sub _make_pod_header {
    my $self = shift;
    my $E = '=';
    return <<"HEADER";
${E}head1 NAME

extopus.cfg - The Extopus configuration file

${E}head1 SYNOPSIS

 *** GENERAL ***
 cache_dir = /scratch/extopus
 mojo_secret = Secret Cookie
 log_file = /tmp/dbtoria.log
 
 *** ATTRIBUTES ***
 prod = Product
 country = Country
 city = City
 street = Street
 number = No
 cust = Customer
 svc_type = Service
 data = Data
 data_type = Type
 port = Port
 inv_id = InvId

 *** TREE ***
 Location = country,city,street,no
 Service = svc_type, data_type, inv_id

 *** TABLES ***
 search = prod, country, city, street, number, cust, svc_type, data, data_type, port, inv_id
 tree = prod, country, city, street, number, cust, svc_type, data, data_type, port, inv_id

 *** INVENTORY: siam1 ***
 module=SIAM
 yaml_cfg=/path_to/siam.yaml
 +MAP
 siam.svc.product_name = prod
 xyc.svc.loc.country = country
 xyc.svc.loc.city = city
 xyc.svc.loc.address = street
 xyc.svc.loc.building_number = number
 siam.contract.customer_name = cust
 siam.svc.type = svc_type
 siam.svcdata.name = data
 siam.svcdata.type = data_type
 cablecom.port.shortname = port
 siam.svc.inventory_id = inv_id

 *** VISUALIZER: siam1 ***
 module = TorrusIframe

${E}head1 DESCRIPTION

Configuration overview

${E}head1 CONFIGURATION

HEADER

}

=item $x->B<_make_parser>()

Create a config parser for DbToRia.

=cut

sub _make_parser {
    my $self = shift;
    my $E = '=';
    my $grammar = {
        _sections => [ qw{GENERAL /INVENTORY:\s+\S+/ /VISUALIZER:\s+\S+/ ATTRIBUTES TREE TABLES }],
        _mandatory => [qw(GENERAL ATTRIBUTES TREE TABLES)],
        GENERAL => {
            _doc => 'Global configuration settings for Extopus',
            _vars => [ qw(cache_dir mojo_secret log_file log_level) ],
            _mandatory => [ qw(cache_dir mojo_secret log_file) ],
            cache_dir => { _doc => 'directory to cache information gathered via the inventory plugins' },
            mojo_secret => { _doc => 'secret for signing mojo cookies' },
            log_file => { _doc => 'write a log file to this location (unless in development mode)'},
            log_level => { _doc => 'what to write to the logfile'},
        },
        ATTRIBUTES => {
            _vars => [ '/[-_a-z0-9]+/' ],
            '/[-_a-z0-9]+/' => {
                _doc => 'List of known attributes with friendly names.',
                _examples => 'city = City'
            },            
        },
        TREE => {
            _vars => [ '/[A-Za-z0-9]+/' ],
            '/[A-Za-z0-9]+/' => {
                _doc => 'Tree building attributes',
                _examples => 'Location = country,city,street,no'
            },
            
        },
        TABLES => {
            _vars => [ qw(search tree) ],
            _mandatory => [ qw(search tree) ],
            search => {
                _doc => 'list of attributes for search results table',
                _examples => 'search = prod, country, city, street, number'
            },            
            tree => {
                _doc => 'list of attributes for tree nodes table',
                _examples => 'tree = prod, country, city, street, number'
            },            
        },

        '/INVENTORY:\s+\S+/' => {
            _order => 1,
            _doc => 'Instanciate an inventory object',
            _vars => [ qw(module /[a-z]\S+/) ],
            _mandatory => [ 'module' ],
            module => {
                _doc => 'The inventory module to load'
            },
            _sections => [ '/[A-Z]\S+/' ],
            '/[a-z]\S+/' => {
                _doc => 'Any key value settings appropriate for the instance at hand'
            },
            '/[A-Z]\S+/' => {
                _doc => 'Grouped configuraiton options for complex inventory driver configurations',
                _vars => [ '/[a-z]\S+/' ],
                '/[a-z]\S+/' => {             
                    _doc => 'Any key value settings appropriate for the instance at hand'
                }        
            },
        },
        '/VISUALIZER:\s+\S+/' => {
            _order => 1,
            _doc => 'Instanciate a visualizer object',
            _vars => [ qw(module /[a-z]\S+/) ],
            _mandatory => [ 'module' ],
            _sections => [ '/[A-Z]\S+/' ],
            module => {
                _doc => 'The visualization module to load'
            },
            '/[a-z]\S+/' => {
                _doc => 'Any key value settings appropriate for the instance at hand'
            },
            '/[A-Z]\S+/' => {
                _doc => 'Grouped configuraiton for complex visualization modules',
                _vars => [ '/[a-z]\S+/' ],
                '/[a-z]\S+/' => {             
                    _doc => 'Any key value settings appropriate for the instance at hand'
                }        
            },
        },

    };
    my $parser =  Config::Grammar->new ($grammar);
    return $parser;
}

1;
__END__

=back

=head1 COPYRIGHT

Copyright (c) 2011 by OETIKER+PARTNER AG. All rights reserved.

=head1 LICENSE

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.

=head1 AUTHOR

S<Tobias Oetiker E<lt>tobi@oetiker.chE<gt>>

=head1 HISTORY

 2011-02-19 to 1.0 first version

=cut

# Emacs Configuration
#
# Local Variables:
# mode: cperl
# eval: (cperl-set-style "PerlStyle")
# mode: flyspell
# mode: flyspell-prog
# End:
#
# vi: sw=4 et

