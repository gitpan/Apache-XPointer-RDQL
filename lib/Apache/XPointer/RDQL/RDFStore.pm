# $Id: RDFStore.pm,v 1.8 2004/11/15 14:42:10 asc Exp $
use strict;

package Apache::XPointer::RDQL::RDFStore;
use base qw (Apache::XPointer::RDQL);

$Apache::XPointer::RDQL::RDFStore::VERSION = '1.0';

=head1 NAME

Apache::XPointer::RDQL::RDFStore - mod_perl handler to address XML fragments using the RDF Data Query Language.

=head1 SYNOPSIS

 <Directory /foo/bar>

  <FilesMatch "\.rdf$">
   SetHandler	perl-script
   PerlHandler	Apache::XPointer::RDQL::RDFStore

   PerlSetVar   XPointerSendRangeAs  "XML"
  </FilesMatch>

 </Directory>

 #

 my $ua  = LWP::UserAgent->new();
 my $req = HTTP::Request->new(GET => "http://example.com/foo/bar/baz.rdf");

 $req->header("Range" => qq(SELECT ?title, ?link
                            WHERE
                            (?item, <rdf:type>, <rss:item>),
                            (?item, <rss::title>, ?title),
                            (?item, <rss::link>, ?link)
                            USING
                            rdf for <http://www.w3.org/1999/02/22-rdf-syntax-ns#>,
                            rss for <http://purl.org/rss/1.0/>));

 my $res = $ua->request($req);

=head1 DESCRIPTION

Apache::XPointer is a mod_perl handler to address XML fragments using
the HTTP 1.1 I<Range> header and the RDF Data Query Language (RDQL), 
as described in the paper : I<A Semantic Web Resource Protocol: XPointer
and HTTP>.

Additionally, the handler may also be configured to recognize a conventional
CGI parameter as a valid range identifier.

If no 'range' property is found, then the original document is
sent unaltered.

=head1 OPTIONS

=head2 XPointerAllowCGIRange

If set to B<On> then the handler will check the CGI parameters sent with the
request for an argument defining an XPath range.

CGI parameters are checked only if no HTTP Range header is present.

Case insensitive.

=head2 XPointerCGIRangeParam

The name of the CGI parameter to check for an XPath range.

Default is B<range>

=head2 XPointerSendRangeAs

=over 4

=item * B<multi-part>

Returns matches as type I<multipart/mixed> :

 --match
 Content-type: text/xml; charset=UTF-8

 <rdf:RDF
      xmlns:rdf='http://www.w3.org/1999/02/22-rdf-syntax-ns#'
      xmlns:rdfstore='http://rdfstore.sourceforge.net/contexts/'
      xmlns:voc0='http://purl.org/rss/1.0/'>
  <rdf:Description rdf:about='rdf:resource:rdfstore123'>
   <voc0:title>The Daily Cartoon for November 15</voc0:title>
   <voc0:link>http://feeds.feedburner.com/BenHammersleysDangerousPrecedent?m=1</voc0:link>
  </rdf:Description>
 </rdf:RDF>

 --match
 Content-type: text/xml; charset=UTF-8

 <rdf:RDF
      xmlns:rdf='http://www.w3.org/1999/02/22-rdf-syntax-ns#'
      xmlns:rdfstore='http://rdfstore.sourceforge.net/contexts/'
      xmlns:voc0='http://purl.org/rss/1.0/'>
  <rdf:Description rdf:about='rdf:resource:rdfstore456'>
   <voc0:title>Releasing RadioPod</voc0:title>
   <voc0:link>http://feeds.feedburner.com/BenHammersleysDangerousPrecedent?m=178</voc0:link>
  </rdf:Description>
 </rdf:RDF>

 --match--

=item * B<XML>

Return matches as type I<application/rdf+xml> :

 <rdf:RDF
      xmlns:rdf='http://www.w3.org/1999/02/22-rdf-syntax-ns#'
      xmlns:rdfstore='http://rdfstore.sourceforge.net/contexts/'
      xmlns:voc0='http://purl.org/rss/1.0/'>

  <rdf:Description rdf:about='rdf:resource:rdfstoreS789'>
   <rdf:type rdf:resource='http://www.w3.org/1999/02/22-rdf-syntax-ns#Seq' />
   <rdf:type rdf:resource='x-urn:cpan:ascope:apache-xpointer-rdql:range'/ >
   <rdf:li rdf:resource='http://www.w3.org/1999/02/22-rdf-syntax-ns#_1' />
   <rdf:li rdf:resource='http://www.w3.org/1999/02/22-rdf-syntax-ns#_2' />
  </rdf:Description>

  <rdf:Description rdf:about='http://www.w3.org/1999/02/22-rdf-syntax-ns#_1'>
   <voc0:title>The Daily Cartoon for November 15</voc0:title>
   <voc0:link>http://feeds.feedburner.com/BenHammersleysDangerousPrecedent?m=1</voc0:link>
  </rdf:Description>

  <rdf:Description rdf:about='http://www.w3.org/1999/02/22-rdf-syntax-ns#_2'>
   <voc0:title>Releasing RadioPod</voc0:title>
   <voc0:link>http://feeds.feedburner.com/BenHammersleysDangerousPrecedent?m=178</voc0:link>
  </rdf:Description>

 </rdf:RDF>

=back

Default is B<XML>; case-insensitive.

=head1 MOD_PERL COMPATIBILITY

This handler will work with both mod_perl 1.x and mod_perl 2.x; it
works better in 1.x because it supports Apache::Request which does
a better job of parsing CGI parameters.

=cut

use DBI;
use RDFStore::Model;
use RDFStore::NodeFactory;

sub range {
    my $pkg    = shift;
    my $apache = shift;
    my $ns     = shift;
    my $query  = shift;

    my $bind = $pkg->bind($query);

    my $dbh = undef;
    my $sth = undef;

    eval {
	$dbh = DBI->connect("DBI:RDFStore:");
    };

    if ($@) {
	return $pkg->_fatal($apache,
			    "failed to create DB connection, $@");
    }

    eval {
	$sth = $dbh->prepare($query->query_string());
    };

    if ($@) {
	return $pkg->_fatal($apache,
			    "failed to prepare query statement, $@");
    }

    $sth->execute();

    if ($dbh->err()) {
	return $pkg->_fatal($apache,
			    $dbh->errstr());
    }

    $sth->bind_columns(map { \$_->{value} } @$bind);

    #

    return {success => 1,
	    bind    => $bind,
	    result  => $sth};
}

sub send_results {
    my $pkg    = shift;
    my $apache = shift;
    my $res    = shift;
    
    if ($apache->dir_config("XPointerSendRangeAs") =~ /^multi-?part$/i) {
	$pkg->send_multipart($apache,$res);
    }
    
    else {
	$pkg->send_xml($apache,$res);
    }

    return 1;
}

sub send_multipart {
    my $pkg    = shift;
    my $apache = shift;
    my $res    = shift;

    $apache->content_type(qq(multipart/mixed; boundary="match"));

    if (! $pkg->_mp2()) {
	$apache->send_http_header();
    }

    #

    my $factory = RDFStore::NodeFactory->new();
    
    while ($res->{'result'}->fetch()) {

	my $model   = RDFStore::Model->new();
	my $subject = $factory->createUniqueResource();

	map { 
	    
	    my $property = $factory->createResource($_->{namespaceuri},$_->{localname});
	    my $object   = $_->{value};

	    $model->add($factory->createStatement($subject,$property,$object));
	} @{$res->{'bind'}};

	$apache->print(qq(--match\n));
	$apache->print(sprintf("Content-type: text/xml; charset=%s\n\n","UTF-8"));

	$apache->print(sprintf("%s\n",$model->serialize()));
    }

    $apache->print(qq(--match--\n));
    return 1;
}

sub send_xml {
    my $pkg    = shift;
    my $apache = shift;
    my $res    = shift;

    #

    my $ns_rdf   = "http://www.w3.org/1999/02/22-rdf-syntax-ns#";   
    my $ns_xp    = "x-urn:cpan:ascope:apache-xpointer-rdql:";

    my $factory  = RDFStore::NodeFactory->new();
    my $model    = RDFStore::Model->new();

    my $range    = $factory->createResource($ns_xp,"range");
    my $type     = $factory->createResource($ns_rdf,"type");
    my $sequence = $factory->createResource($ns_rdf,"Seq");
    my $li       = $factory->createResource($ns_rdf,"li");

    my $seq = $factory->createUniqueResource();

    $model->add($factory->createStatement($seq,$type,$range));
    $model->add($factory->createStatement($seq,$type,$sequence));

    for (my $i = 0; $res->{'result'}->fetch(); $i++) {

	my $result = $factory->createOrdinal($i+1);

	map { 
	    
	    my $property = $factory->createResource($_->{namespaceuri} . $_->{localname});
	    my $object   = $_->{value};

	    $model->add($factory->createStatement($result,$property,$object));

	} @{$res->{'bind'}};

	$model->add($factory->createStatement($seq,$li,$result));
    }

    $pkg->_header_out($apache,"Content-Encoding","UTF-8");
    $apache->content_type(qq(application/rdf+xml));

    if (! $pkg->_mp2()) {
	$apache->send_http_header();
    }

    #

    $apache->print($model->serialize());
    return 1;
}

sub _fatal {
    my $pkg    = shift;
    my $apache = shift;
    my $err    = shift;

    $apache->log()->error($err);
    
    return {success  => 0,
	    response => $pkg->_server_error()};
}

=head1 VERSION

1.0

=head1 DATE

$Date: 2004/11/15 14:42:10 $

=head1 AUTHOR

Aaron Straup Cope E<lt>ascope@cpan.orgE<gt>

=head1 SEE ALSO

L<Apache::XPointer>

=head1 LICENSE

Copyright (c) 2004 Aaron Straup Cope. All rights reserved.

This is free software, you may use it and distribute it under
the same terms as Perl itself.

=cut 

return 1;
