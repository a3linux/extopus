package ep::Visualizer::TorrusData;

=head1 NAME

ep::Visualizer::TorrusData - pull numeric data associated with torrus data source

=head1 SYNOPSIS

use ep::Visualizer::TorrusData;
my $viz = ep::Visualizer::TorrusData->new();

=head1 DESCRIPTION

Works in conjunction with the Data frontend visualizer. Data can be
presented in tabular form and as a csv download.

This visualizer will match records that have the following attributes:

 torrus.url-prefix
 torrus.nodeid

The visualizer fetches data from torrus through the AGGREGATE_DS rpc call.

It determines further processing by evaluation additional configurable attributes

 *** VISUALIZER: data ***
 module = TorrusData
 selector = data_type
 type = PortTraffic
 name = Port Traffic
 sub_nodes = inbytes, outbytes
 col_names = Avg In, Avg  Out, Total In, Total Out, Max In, Max Out
 col_data = $D{inbytes}{AVG}, $D{inbytes}{AVG}, \
            $D{inbytes}{AVG} * $DURATION / 100 * $D{inbytes}{AVAIL}, \
            $D{outbytes}{AVG} * $DURATION / 100 * $D{outbytes}{AVAIL}, \
            $D{inbytes}{MAX}, \
            $D{outbytes}{MAX}

=cut

use strict;
use warnings;

use Mojo::Base 'ep::Visualizer::base';
use Mojo::Util qw(hmac_md5_sum url_unescape);
use Mojo::URL;
use Mojo::JSON::Any;
use Mojo::UserAgent;
use Mojo::Template;
use Time::Local qw(timelocal_nocheck);

use ep::Exception qw(mkerror);
use POSIX qw(strftime);

has 'hostauth';
has view => 'embedded';
has json        => sub {Mojo::JSON::Any->new};
has 'root';

sub new {
    my $self = shift->SUPER::new(@_);
    $self->root('/torrusCSV_'.$self->instance);
    # parse some config data
    for my $prop (qw(selector name type sub_nodes col_names col_data)){
        die mkerror(9273, "mandatory property $prop for visualizer module TorrusData is not defined")
            if not defined $self->cfg->{$prop};
    }
    $self->cfg->{col_names} = [ split /\s*,\s*/, $self->cfg->{col_names} ];
    $self->cfg->{sub_nodes} = [ split /\s*,\s*/, $self->cfg->{sub_nodes} ];
    my $sub = eval 'sub { my $DURATION = shift; my %D = (%{$_[0]}); return [ '.$self->cfg->{col_data} . ' ] }';
    if ($@){
        die mkerror(38734,"Failed to compile $self->cfg->{col_data}"); 
    }
    $self->cfg->{col_data} = $sub;
    $self->addProxyRoute();    
    return $self;
}


=head2 rrd2float(hash)

turn hash values that look liike floats into floats

=cut

sub rrd2float {
    my $hash = shift;
    my %out;
    my $nan = 0.0+"NaN";
    for my $key (keys %$hash){
        my $val =  $hash->{$key};
        if ( defined $val and $val ne ""){
            if ( $val =~ /[-+]?[0-9]*\.?[0-9]+(?:[eE][-+]?[0-9]+)?/ ){
                $out{$key} = 1.0 * $val;
            }            
            elsif ( $val =~ /nan/i ){
                # perl turns this into a real NaN it seems
                $out{$key} = $nan; 
            }
            else {
                $out{$key} = $val;
            }
        }
        else {
            $out{$key} = undef;
        }
    }    
    return \%out;
}

=head2 denan(array)

turn nan values into undef since json implementations have issues with nan ... 

=cut

sub denan {
    my $in = shift;
    my $nan = 0.0+"NaN";
    return [
        map { defined $nan <=> $_ ? $_ : undef } @$in
    ]    
}

=head2 matchRecord(rec)

can we handle this type of record

=cut

sub matchRecord {
    my $self = shift;
    my $rec = shift;
    for (qw(torrus.nodeid torrus.tree-url)){
        return undef unless defined $rec->{$_};
    }

    return undef 
        if $rec->{$self->cfg->{selector}} ne $self->cfg->{type};

    return {
        visualizer => 'data',
        title => $self->cfg->{name},
        arguments => {
            instance => $self->instance,
            columns => $self->cfg->{col_names},
            intervals => [
                { key => 'day', name => 'Daily' },
                { key => 'week', name => 'Weekly' },
                { key => 'month', name => 'Monthly' },
                { key => 'year', name => 'Yearly' },
            ],
            treeUrl => $rec->{'torrus.tree-url'},
            nodeId => $rec->{'torrus.nodeid'},
            hash => $self->calcHash( $rec->{'torrus.tree-url'}, $rec->{'torrus.nodeid'})
        }
    };
}

=head2 getData(tree_url,nodeid,end,interval,count)

use the AGGREGATE_DS rpc call to pull some statistics from the server.

=cut

sub getData {
    my $self = shift;
    my $treeUrl = shift;
    my $nodeId = shift;
    my $end = shift;
    my $interval = shift;
    my $count = shift;
    my $url = Mojo::URL->new($treeUrl);
    my @return;
    for (my $step=0;$step < $count;$step++){
        my $stepStart;
        my $stepEnd;
        my $stepLabel;
        my %E;
        my %S;
        for ($interval){
            /day/ && do { 
                @S{qw{sec min hour mday mon year wday yday isdst}} = localtime($end-$step*24*3600);
                $stepStart = timelocal_nocheck(0,0,0,$S{mday},@S{qw(mon year)});
                @E{qw{sec min hour mday mon year wday yday isdst}} = localtime($stepStart+25*3600);
                $stepEnd = timelocal_nocheck(0,0,0,$E{mday},@E{qw(mon year)});
                $stepLabel = strftime("%F",localtime($stepStart+12*3600));
                next;
            };
            /week/ && do {
                @S{qw{sec min hour mday mon year wday yday isdst}} = localtime($end-$step*7*24*3600);
                $stepStart = timelocal_nocheck(0,0,0,$S{mday} - $S{wday},@S{qw(mon year)});
                @E{qw{sec min hour mday mon year wday yday isdst}} = localtime($stepStart+7.1*24*3600);
                $stepEnd = timelocal_nocheck(0,0,0,$E{mday},@E{qw(mon year)});
                $stepLabel = strftime("%Y.%02V",localtime($stepStart+3.5*24*3600));
                next;
            };
            /month/ && do {
                @S{qw{sec min hour mday mon year wday yday isdst}} = localtime($end - 15 - $step * 365.25*24*3600/12);
                my $midMonStart = timelocal_nocheck(0,0,0,15,$S{mon},$S{year});
                @S{qw{sec min hour mday mon year wday yday isdst}} = localtime($midMonStart);
                @E{qw{sec min hour mday mon year wday yday isdst}} = localtime($midMonStart+365.25*24*3600/12);
                $stepStart = timelocal_nocheck(0,0,0,1,$S{mon},$S{year});
                $stepEnd = timelocal_nocheck(0,0,0,1,$E{mon},$E{year})-1;
                $stepLabel = strftime("%Y-%02m",localtime($stepStart));
                next;
            };
            /year/ && do {
                @E{qw{sec min hour mday mon year wday yday isdst}} = localtime($end - $step*365.25*24*3600);
                $stepStart = timelocal_nocheck(0,0,0,1,0,$E{year}-$step);
                $stepEnd = timelocal_nocheck(23,59,59,31,11,$E{year}-$step+1);
                $stepLabel = strftime("%Y",localtime($stepStart+180*24*3600));
                next;
            };
        }
        my %data;    
        for my $subNode (@{$self->cfg->{sub_nodes}}){
            $url->query(
                view=> 'rpc',
                RPCCALL => 'AGGREGATE_DS',
                Gstart => $stepStart,
                Gend => $stepEnd,
                nodeid=>"$nodeId//$subNode"
            );
            $self->log->debug("getting ".$url->to_string);
            my $tx = Mojo::UserAgent->new->get($url);
            my $data;
            if (my $res=$tx->success) {
                if ($res->headers->content_type =~ m'application/json'i){
                    my $ret = $self->json->decode($res->body);
                    if ($ret->{success}){
                        my $key = (keys %{$ret->{data}})[0];
                        $data{$subNode} = rrd2float($ret->{data}{$key});
                    } else {
                        $self->log->error("Fetching ".$url->to_string." returns ".$data->{error});
                        die mkerror(89384,"Torrus is not happy with our request: ".$data->{error});
                    }
                }
                else {
                    $self->log->error("Fetching ".$url->to_string." returns ".$res->headers->content_type);
                    die mkerror("unexpected content/type (".$res->headers->content_type."): ".$res->body);
                }
            }
            else {
                my ($msg,$error) = $tx->error;
                $self->log->error("Fetching ".$url->to_string." returns $msg ".($error ||''));
                die mkerror(48877,"fetching Leaves for $nodeId from torrus server: $msg ".($error ||''));        
            }
        };
        my $row = denan($self->cfg->{col_data}($stepEnd - $stepStart,\%data));
       
        push @return, [ $stepLabel, @{$row} ];
    }

    return {
        status => 1,
        data => \@return,
    };
}

=head2 rpcService 

provide rpc data access

=cut

sub rpcService {
    my $self = shift;
    my $arg = shift;
    die mkerror(9844,"hash is not matching url and nodeid")
        unless $self->calcHash($arg->{treeUrl},$arg->{nodeId}) eq $arg->{hash};
    return $self->getData($arg->{treeUrl},$arg->{nodeId},$arg->{endDate},$arg->{interval},$arg->{count});
}

=head2 addProxyRoute()

create a proxy route with the given properties of the object

=cut

sub addProxyRoute {
    my $self = shift;
    my $routes = $self->routes;

    $routes->get($self->prefix.$self->root, sub {
        my $ctrl = shift;
        my $req = $ctrl->req;
        my $hash =  $req->param('hash');
        my $nodeid = $req->param('nodeid');
        my $url = $req->param('url');
        my $end = $req->param('end');
        my $interval = $req->param('interval');
        my $count = $req->param('count');
        my $newHash = $self->calcHash($url,$nodeid);
        if ($hash ne $newHash){
            $ctrl->render(
                 status => 401,
                 text => "Supplied hash ($hash) does not match our expectations",
            );
            $self->log->warn("Request for $url?nodeid=$nodeid denied ($hash ne $newHash)");
            return;
        }
        my $data =  $self->getData($url,$nodeid,$end,$interval,$count);
        if (not $data->{status}){
            $ctrl->render(
                 status => 401,
                 text => $data->{error},
            );
            $self->log->error("faild getting data $data->{error}");
            return;
        }
        
        my $rp = Mojo::Message::Response->new;
        $rp->code(200);
        $rp->headers->content_type('application/csv');
        my $name = $nodeid;
        $name =~ s/[^-_0-9a-z]+/_/ig;
        $name .= '-'.strftime('%Y-%m-%d',localtime($end));               
        $rp->headers->add('Content-Disposition',"attachement; filename=$name.csv");
        my $body = join(",",map {qq{"$_"}} '',@{$self->cfg->{col_names}})."\r\n";
        for my $row (@{$data->{data}}){
            $body .= join(",",map { /[^.0-9]/ ? qq{"$_"} : $_ } @$row)."\r\n";
        }
        $rp->body($body);
        $ctrl->tx->res($rp);
        $ctrl->rendered;
    });
}

=head2 calcHash(ref)

Returns a hash for authenticating access to the ref

=cut

sub calcHash {
    my $self = shift;
    $self->log->debug('HASH '.join(',',@_));    
    my $hash = hmac_md5_sum(join('::',@_),$self->secret);
    return $hash;
}

1;

__END__

=back

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

=head1 COPYRIGHT

Copyright (c) 2011 by OETIKER+PARTNER AG. All rights reserved.

=head1 AUTHOR

S<Tobias Oetiker E<lt>tobi@oetiker.chE<gt>>

=head1 HISTORY

 2010-11-04 to 1.0 first version

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
