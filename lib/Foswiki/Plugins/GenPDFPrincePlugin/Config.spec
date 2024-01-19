# ---+ Extensions
# ---++ GenPDFPrincePlugin
# **PATH**
# prince executable including complete path
# downloadable from http://www.princexml.com/
$Foswiki::cfg{GenPDFPrincePlugin}{PrinceCmd} = '/usr/bin/prince --no-warn-css --media=print --verbose --input=html --baseurl %BASEURL|U% --output=%OUTFILE|F% %INFILE|F%';

1;
