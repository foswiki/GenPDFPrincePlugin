# Plugin for Foswiki - The Free and Open Source Wiki, http://foswiki.org/
#
# Copyright (C) 2009-2024 Michael Daum http://michaeldaumconsulting.com
#
# This license applies to GenPDFPrincePlugin *and also to any derivatives*
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version. 
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details, published at
# http://www.gnu.org/copyleft/gpl.html

package Foswiki::Plugins::GenPDFPrincePlugin;

=begin TML

---+ package Foswiki::Plugins::GenPDFPrincePlugin

base class to hook into the foswiki core

=cut

use strict;
use warnings;

use Foswiki::Func ();
use Foswiki::Plugins ();
use Foswiki::Sandbox ();
use File::Path ();
use Encode ();
use File::Temp ();

our $VERSION = '3.00';
our $RELEASE = '%$RELEASE%';
our $SHORTDESCRIPTION = 'Generate PDF using Prince XML';
our $LICENSECODE = '%$LICENSECODE%';
our $NO_PREFS_IN_TOPIC = 1;

use constant TRACE => 0; # toggle me

=begin TML

---++ initPlugin($topic, $web, $user) -> $boolean

initialize the plugin, automatically called during the core initialization process

=cut

sub initPlugin {

  my $query = Foswiki::Func::getRequestObject();
  my $contenttype = $query->param("contenttype") || 'text/html';
  my $context = Foswiki::Func::getContext();

  if ($contenttype eq "application/pdf") {
    $context->{genpdf_doit} = 1;
    $context->{static} = 1;

    my $template = Foswiki::Func::getPreferencesValue("PRINT_TEMPLATE");
    Foswiki::Func::setPreferencesValue("VIEW_TEMPLATE", $template) if $template;

  } else {
    $context->{genpdf_doit} = 0;
  }

  return 1;
}

=begin TML

---++ ObjectMethod completePageHandler()

some minor fixes to the html before generating pdf for it

=cut

sub completePageHandler {
  #my($html, $httpHeaders) = @_;

  my $context = Foswiki::Func::getContext();
  my $session = $Foswiki::Plugins::SESSION;
  my $baseWeb = $session->{webName};
  my $baseTopic = $session->{topicName};

  return unless $context->{genpdf_doit};

  my $siteCharSet = $Foswiki::cfg{Site}{CharSet};

  my $content = $_[0];

  # remove left-overs and some basic clean-up
  $content =~ s/([\t ]?)[ \t]*<\/?(nop|noautolink)\/?>/$1/gis;
  $content =~ s/<!--.*?-->//g;
  $content =~ s/[\0-\x08\x0B\x0C\x0E-\x1F\x7F]+/ /g;
  $content =~ s/(<\/html>).*?$/$1/gs;
  $content =~ s/^\s*$//gms;

  # clean url params in anchors as prince can't generate proper xrefs otherwise;
  # hope this gets fixed in prince at some time
  $content =~ s/(href=["'])\?.*(#[^"'\s])+/$1$2/g;

  # rewrite some urls to use file://..
  $content =~ s/(<link[^>]+href=["'])([^"']+)(["'])/$1.toFileUrl($2).$3/ge;
  $content =~ s/(<img[^>]+src=["'])([^"']+)(["'])/$1.toFileUrl($2).$3/ge;

  # create temp files
  my $htmlFile = new File::Temp(SUFFIX => '.html', UNLINK => (TRACE ? 0 : 1));

  # create output filename
  my ($pdfFilePath, $pdfFile) = getFileName($baseWeb, $baseTopic);

  # convert to utf8
  $content = Encode::decode($siteCharSet, $content) unless $Foswiki::UNICODE;
  $content = Encode::encode_utf8($content);

  # creater html file
  binmode($htmlFile);
  print $htmlFile $content;
  _writeDebug("htmlFile=" . $htmlFile->filename);

  # create print command
  my $pubUrl = getPubUrl();
  my $cmd = $Foswiki::cfg{GenPDFPrincePlugin}{PrinceCmd}
    || '/usr/bin/prince --baseurl %BASEURL|U% -i html -o %OUTFILE|F% %INFILE|F%';

  _writeDebug("cmd=$cmd");
  _writeDebug("BASEURL=$pubUrl");

  # execute
  my ($output, $exit, $error) = Foswiki::Sandbox->sysCommand(
    $cmd,
    BASEURL => $pubUrl,
    OUTFILE => $pdfFilePath,
    INFILE => $htmlFile->filename,
  );

  _writeDebug("htmlFile=" . $htmlFile->filename);
  _writeDebug("error=$error");
  #_writeDebug("output=$output");

  if ($exit) {
    my $html = $content;
    my $line = 1;
    $html = '00000: ' . $html;
    $html =~ s/\n/"\n".(sprintf "\%05d", $line++).": "/ge;
    #print STDERR "$html\n" if TRACE;
    throw Error::Simple("execution of prince failed ($exit): \n\n$error\n\n$html");
  }

  my $query = Foswiki::Func::getCgiQuery();
  if (($query->param("pdfdisposition") || '') eq 'inline') {
    my $session = $Foswiki::Plugins::SESSION;
    my $pdf = readFile($pdfFilePath);
    $session->{response}->body($pdf);

    # SMELL: prevent compression
    $ENV{'HTTP_ACCEPT_ENCODING'} = ''; 
    $ENV{'HTTP2'} = ''; 

  } else {
    my $url = $Foswiki::cfg{PubUrlPath} . '/' . $baseWeb . '/' . $baseTopic . '/' . $pdfFile . '?t=' . time();
    Foswiki::Func::redirectCgiQuery($query, $url);
  }

  $_[0] = ""; # don't send back anything else
}

=begin TML

---++ ObjectMethod getFileName($web, $topic)

returns the genpdf_...pdf file for the given web.topic

=cut

sub getFileName {
  my ($web, $topic) = @_;

  my $query = Foswiki::Func::getCgiQuery();
  my $fileName = $query->param("outfile") || 'genpdf_'.$topic.'.pdf';

  $fileName =~ s{[\\/]+$}{};
  $fileName =~ s!^.*[\\/]!!;
  $fileName =~ s/$Foswiki::regex{filenameInvalidCharRegex}//go;

  $web =~ s/\./\//g;
  my $filePath = Foswiki::Func::getPubDir().'/'.$web.'/'.$topic;
  File::Path::mkpath($filePath);

  $filePath .= '/'.$fileName;

  return ($filePath, $fileName);
}

=begin TML

---++ ObjectMethod toFileUrl($url) -> $fileUrl

converts a https:// url to a matching file:// url

=cut

sub toFileUrl {
  my $url = shift;

  my $fileUrl = $url;
  my $localServerPattern = '^(?:'.$Foswiki::cfg{DefaultUrlHost}.')?'.$Foswiki::cfg{PubUrlPath}.'(.*)$';
  $localServerPattern =~ s/https?/https?/;

  if ($fileUrl =~ /$localServerPattern/) {
    $fileUrl = $1;
    $fileUrl =~ s/\?.*$//;
    $fileUrl = "file://".$Foswiki::cfg{PubDir}.$fileUrl;
  } else {
    #_writeDebug("url=$url does not point to a local asset (pattern=$localServerPattern)");
  }

  #_writeDebug("url=$url, fileUrl=$fileUrl");
  return $fileUrl;
}

=begin TML

---++ ObjectMethod modifyHeaderHandler($request)

adds content-disposition headers during pdf generation

=cut

sub modifyHeaderHandler {
  my ($hopts, $request) = @_;

  my $session = $Foswiki::Plugins::SESSION;
  my $baseWeb = $session->{webName};
  my $baseTopic = $session->{topicName};
  my $context = Foswiki::Func::getContext();

  $hopts->{'Content-Disposition'} = "inline;filename=$baseTopic.pdf" if $context->{genpdf_doit};
}

=begin TML

---++ ObjectMethod getPubUrl()

compatibility layer

=cut

sub getPubUrl {
  my $session = $Foswiki::Plugins::SESSION;

  if ($session->can("getPubUrl")) {
    # pre 2.0
    return $session->getPubUrl(1);
  } 

  # post 2.0
  return Foswiki::Func::getPubUrlPath(undef, undef, undef, absolute=>1);
}

=begin TML

---++ ObjectMethod readFile($name)

reads a pdf file from disk if delivering it inline instead of redirecting the browser to it

=cut

sub readFile {
  my $name = shift;
  my $data = '';
  my $IN_FILE;

  open($IN_FILE, '<', $name) || return '';
  binmode $IN_FILE;

  local $/ = undef;    # set to read to EOF
  $data = <$IN_FILE>;
  close($IN_FILE);

  $data = '' unless $data;    # no undefined
  return $data;
}

# static helper
sub _writeDebug {
  print STDERR "GenPDFPrincePlugin - $_[0]\n" if TRACE;
}


1;
