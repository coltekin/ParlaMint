#!/usr/bin/perl
# Make ParlaMint corpora ready for distribution:
# 1. Finalize input corpora (version, date, handle, extent)
# 2. Validate corpora
# 3. Produce derived formats
# For help on parameters do
# $ parlamint2distro.pl -h
# 
use warnings;
use utf8;
use open ':utf8';
use FindBin qw($Bin);
use File::Temp qw/ tempfile tempdir /;  #creation of tmp files and directory
my $tempdirroot = "$Bin/tmp";
my $tmpDir = tempdir(DIR => $tempdirroot, CLEANUP => 0);

binmode(STDIN, ':utf8');
binmode(STDOUT, ':utf8');
binmode(STDERR, ':utf8');

# Prefix and extension of registry files
$regiPrefix = 'parlamint30_';
$regiExt    = 'regi';

sub usage {
    print STDERR ("Usage:\n");
    print STDERR ("$0 -help\n");
    print STDERR ("$0 [<procFlags>] -codes '<Codes>' -version <Version> -teihandle <TeiHandle> -anahandle <AnaHandle>");
    print STDERR (" -schema [<Schema>] -docs [<Docs>] -in <Input> -out <Output>\n");
    print STDERR ("    Prepares ParlaMint corpora for distribution.\n");
    print STDERR ("    <Codes> is the list of country codes of the corpora to be processed.\n");
    print STDERR ("    <Schema> is the directory where ParlaMint RNG schemas are.\n");
    print STDERR ("    <Docs> is the directory where ParlaMint README files are.\n");
    print STDERR ("    <TeiHandle> is the handle of the plain text corpus.\n");
    print STDERR ("    <AnaHandle> is the handle of the linguistically annotated (.ana) corpus.\n");
    print STDERR ("    <Input> is the directory where ParlaMint-XX.TEI/ and ParlaMint-XX.TEI.ana/ are.\n");
    print STDERR ("    <Output> is the directory where output directories are written.\n");
    
    print STDERR ("    <procFlags> are process flags that set which operations are carried out:\n");
    print STDERR ("    * -ana: finalizes the TEI.ana directory\n");
    print STDERR ("    * -tei: finalizes the TEI directory (needs TEI.ana output)\n");
    print STDERR ("    * -sample: produces samples (from TEI.ana and TEI output)\n");
    print STDERR ("    * -valid: validates TEI, TEI.ana and samples\n");
    print STDERR ("    * -vert: produces vertical files (from TEI.ana output)\n");
    print STDERR ("    * -txt: produces plain text files with metadata files (from TEI output)\n");
    print STDERR ("    * -conll: produces conllu files with metadata files (from TEI.ana output)\n");
    print STDERR ("    * -all: do all of the above.\n");
    print STDERR ("    The flags can be also negated, e.g. \"-all -novalid\".\n");
    print STDERR ("    Example: \n");
    print STDERR ("    ./parlamint2distro.pl -all -novalid -codes 'BE ES' \\\n");
    print STDERR ("      -schema ../Schema -docs My/Docs/ -in Originals/ -out Final/  \\\n");
    print STDERR ("      2> ParlaMint.ana.log\n");
}

use Getopt::Long;
use FindBin qw($Bin);
use File::Spec;
use File::Copy;
use File::Copy::Recursive qw(dircopy);

my $procAll    = 0;
my $procAna    = 2;
my $procTei    = 2;
my $procSample = 2;
my $procValid  = 2;
my $procTxt    = 2;
my $procConll  = 2;
my $procVert   = 2;

GetOptions
    (
     'help'       => \$help,
     'codes=s'    => \$countryCodes,
     'schema=s'   => \$schemaDir,
     'docs=s'     => \$docsDir,
     'version=s'  => \$Version,
     'teihandle=s'=> \$handleTEI,
     'anahandle=s'=> \$handleAna,
     'in=s'       => \$inDir,
     'out=s'      => \$outDir,
     'all'        => \$procAll,
     'ana!'       => \$procAna,
     'tei!'       => \$procTei,
     'sample!'    => \$procSample,
     'valid!'     => \$procValid,
     'txt!'       => \$procTxt,
     'conll!'     => \$procConll,
     'vert!'      => \$procVert,
);

if ($help) {
    &usage;
    exit;
}

$schemaDir = File::Spec->rel2abs($schemaDir) if $schemaDir;
$docsDir = File::Spec->rel2abs($docsDir) if $docsDir;
$inDir = File::Spec->rel2abs($inDir) if $inDir;
$outDir = File::Spec->rel2abs($outDir) if $outDir;

#Execution
#$Parallel = "parallel --gnu --halt 2 --jobs 15";
$Saxon   = "java -jar /usr/share/java/saxon.jar";
# Problem with Out of heap space with TR, NL, GB for ana
$SaxonX  = "java -Xmx240g -jar /usr/share/java/saxon.jar";

# We are assuming taxonomies are relative to Scripts/ (i.e. $Bin/) directory
$taxonomyDir = "$Bin/../Data/Taxonomies";
# Currently we do it only for subcorpus
$taxonomy{'ParlaMint-taxonomy-subcorpus'}            = "$taxonomyDir/ParlaMint-taxonomy-subcorpus.xml";
#$taxonomy{'ParlaMint-taxonomy-parla.legislature'}    = "$taxonomyDir/ParlaMint-taxonomy-parla.legislature.xml";
#$taxonomy{'ParlaMint-taxonomy-speaker_types'}        = "$taxonomyDir/ParlaMint-taxonomy-speaker_types.xml";
#$taxonomy{'ParlaMint-taxonomy-politicalOrientation'} = "$taxonomyDir/ParlaMint-taxonomy-politicalOrientation.xml";
#$taxonomy_ana{'ParlaMint-taxonomy-NER.ana'}          = "$taxonomyDir/ParlaMint-taxonomy-NER.ana.xml";
#$taxonomy_ana{'ParlaMint-taxonomy-UD-SYN.ana'}       = "$taxonomyDir/ParlaMint-taxonomy-UD-SYN.ana.xml";
  
$scriptRelease = "$Bin/parlamint2release.xsl";
$scriptCommon  = "$Bin/parlamint-add-common-content.xsl";
$scriptPolish  = "$Bin/polish-xml.pl";
$scriptValid   = "$Bin/validate-parlamint.pl";
$scriptSample  = "$Bin/corpus2sample.xsl";
$scriptTexts   = "$Bin/parlamintp-tei2text.pl";
$scriptVerts   = "$Bin/parlamintp-tei2vert.pl";
$scriptConls   = "$Bin/parlamintp2conllu.pl";

$XX_template = "ParlaMint-XX";

unless ($countryCodes) {
    print STDERR "Need some country codes.\n";
    print STDERR "For help: parlamint2distro.pl -h\n";
    exit
}
foreach my $countryCode (split(/[, ]+/, $countryCodes)) {
    print STDERR "INFO: *****Converting $countryCode\n";

    # Is this an MTed corpus?
    if ($countryCode =~ m/-([a-z]{2,3})$/) {$MT = $1}
    else {$MT = 0}

    my $XX = $XX_template;
    $XX =~ s|XX|$countryCode|g;

    my $teiDir  = "$XX.TEI";
    my $anaDir = "$XX.TEI.ana";
    
    my $teiRoot = "$teiDir/$XX.xml";
    my $anaRoot = "$anaDir/$XX.ana.xml";

    my $inTeiDir = "$inDir/$teiDir";
    my $inAnaDir = "$inDir/$anaDir";

    my $listOrg    = "$XX-listOrg.xml";
    my $listPerson = "$XX-listPerson.xml";
    my $taxonomies = "*-taxonomy-*.xml";
    
    my $inTeiRoot = "$inDir/$teiRoot";
    my $inAnaRoot = "$inDir/$anaRoot";
    #In case input dir is for samples
    unless (-e $inTeiRoot) {$inTeiRoot =~ s/\.TEI//}
    unless (-e $inAnaRoot) {$inAnaRoot =~ s/\.TEI\.ana//}

    my $outTeiDir  = "$outDir/$teiDir";
    my $outTeiRoot = "$outDir/$teiRoot";
    my $outAnaDir  = "$outDir/$anaDir";
    my $outAnaRoot = "$outDir/$anaRoot";
    my $outSmpDir  = "$outDir/Sample-$XX";
    my $outTxtDir  = "$outDir/$XX.txt";
    my $outConlDir = "$outDir/$XX.conllu";
    my $outVertDir = "$outDir/$XX.vert";
    my $vertRegi   = $regiPrefix . lc $countryCode . '.' . $regiExt;
    $vertRegi =~ s/-/_/g;  #e.g. parlamint30_es-ct.regi to parlamint30_es_ct.regi
	
    if (($procAll and $procAna) or (!$procAll and $procAna == 1)) {
	print STDERR "INFO: ***Finalizing $countryCode TEI.ana\n";
	die "FATAL: Need version\n" unless $Version;
	die "FATAL: Can't find input ana root $inAnaRoot\n" unless -e $inAnaRoot;
	die "FATAL: No handle given for ana distribution\n" unless $handleAna;
	`rm -fr $outAnaDir; mkdir $outAnaDir`;
	if ($MT) {$inReadme = "$docsDir/README-$MT.TEI.ana.txt"}
	else {$inReadme = "$docsDir/README.TEI.ana.txt"}
	die "FATAL: No handle given for TEI.ana distribution\n" unless $handleAna;
	&cp_readme($countryCode, $handleAna, $Version, $inReadme, "$outAnaDir/00README.txt");
	die "FATAL: Can't find schema directory\n" unless $schemaDir and -e $schemaDir;
	dircopy($schemaDir, "$outAnaDir/Schema");
	`rm -f $outAnaDir/Schema/.gitignore`;
	`rm -f $outAnaDir/Schema/nohup.*`;
	my $tmpOutDir = "$tmpDir/release.ana";
	my $tmpOutAnaDir = "$tmpDir/$anaDir";
	my $tmpAnaRoot = "$tmpOutDir/$anaRoot";
	print STDERR "INFO: ***Fixing TEI.ana corpus for release\n";
	`$SaxonX outDir=$tmpOutDir -xsl:$scriptRelease $inAnaRoot`;
	print STDERR "INFO: ***Adding common content to TEI.ana corpus\n";
	`$SaxonX version=$Version handle-ana=$handleAna anaDir=$outAnaDir outDir=$outDir -xsl:$scriptCommon $tmpAnaRoot`;
	&commonTaxonomies($outAnaDir);
    	&polish($outAnaDir);
    }
    if (($procAll and $procTei) or (!$procAll and $procTei == 1)) {
	print STDERR "INFO: ***Finalizing $countryCode TEI\n";
	die "FATAL: Need version\n" unless $Version;
	die "FATAL: Can't find input tei root $inTeiRoot\n" unless -e $inTeiRoot; 
	die "FATAL: No handle given for TEI distribution\n" unless $handleTEI;
	`rm -fr $outTeiDir; mkdir $outTeiDir`;
	if ($MT) {$inReadme = "$docsDir/README-$MT.TEI.txt"}
	else {$inReadme = "$docsDir/README.TEI.ana.txt"}
	&cp_readme($countryCode, $handleTEI, $Version, $inReadme, "$outTeiDir/00README.txt");
	die "FATAL: Can't find schema directory\n" unless $schemaDir and -e $schemaDir;
	dircopy($schemaDir, "$outTeiDir/Schema");
	`rm -f $outTeiDir/Schema/.gitignore`;
	`rm -f $outTeiDir/Schema/nohup.*`;
	my $tmpOutDir = "$tmpDir/release.tei";
	my $tmpOutTeiDir = "$tmpDir/$teiDir";
	my $tmpTeiRoot = "$tmpOutDir/$teiRoot";
	print STDERR "INFO: ***Fixing TEI corpus for release\n";
	`$SaxonX anaDir=$outAnaDir outDir=$tmpOutDir -xsl:$scriptRelease $inTeiRoot`;
	print STDERR "INFO: ***Adding common content to TEI corpus\n";
	`$SaxonX version=$Version handle-txt=$handleTEI anaDir=$outAnaDir outDir=$outDir -xsl:$scriptCommon $tmpTeiRoot`;
	&commonTaxonomies($outTeiDir);
	&polish($outTeiDir);
    }
    if (($procAll and $procSample) or (!$procAll and $procSample == 1)) {
	print STDERR "INFO: ***Making $countryCode samples\n";
	if (-e $outTeiRoot) {
	    `rm -fr $outSmpDir`;
	    `$Saxon outDir=$outSmpDir -xsl:$scriptSample $outTeiRoot`;
	}
	else {print STDERR "WARN: No TEI files for $countryCode samples (needed root file is $outTeiRoot)\n"}
	if (-e $outTeiRoot) {
	    `$scriptTexts $outSmpDir $outSmpDir`;
	}
	if (-e $outAnaRoot) {
	    `$Saxon outDir=$outSmpDir -xsl:$scriptSample $outAnaRoot`;
	    #Make also derived files
	    `$scriptTexts $outSmpDir $outSmpDir` unless $outTeiRoot;
	    `$scriptVerts $outSmpDir $outSmpDir`;
	    `$scriptConls $outSmpDir $outSmpDir`
	}
	else {print STDERR "ERROR: No .ana files for $countryCode samples (needed root file is $outAnaRoot)\n"}
    }
    if (($procAll and $procValid) or (!$procAll and $procValid == 1)) {
	print STDERR "INFO: ***Validating $countryCode TEI\n";
	die "FATAL: Can't find schema directory\n" unless $schemaDir and -e $schemaDir;
	`$scriptValid $schemaDir $outSmpDir` if -e $outSmpDir; 
	`$scriptValid $schemaDir $outTeiDir` if -e $outTeiDir;
	`$scriptValid $schemaDir $outAnaDir` if -e $outAnaDir;
    }
    if (($procAll and $procTxt) or (!$procAll and $procTxt == 1)) {
	print STDERR "INFO: ***Making $countryCode text\n";
	if    ($handleTEI) {$handleTxt = $handleTEI}
	elsif ($handleAna) {$handleTxt = $handleAna}
	else {die "FATAL: No handle given for TEI or .ana distribution\n"}
	`rm -fr $outTxtDir; mkdir $outTxtDir`;
	if ($MT) {$inReadme = "$docsDir/README-$MT.txt.txt"}
	else {$inReadme = "$docsDir/README.txt.txt"}
	# We have an oportunistic handle!
	&cp_readme($countryCode, $handleTxt, $Version, $inReadme, "$outTxtDir/00README.txt");
	if    (-e $outTeiDir) {`$scriptTexts $outTeiDir $outTxtDir`}
	elsif (-e $outAnaDir) {`$scriptTexts $outAnaDir $outTxtDir`}
	else {die "FATAL: Neither $outTeiDir nor $outAnaDir exits\n"}
	&dirify($outTxtDir);
    }
    if (($procAll and $procConll) or (!$procAll and $procConll == 1)) {
	print STDERR "INFO: ***Making $countryCode CoNLL-U\n";
	die "FATAL: Can't find input ana dir $outAnaDir\n" unless -e $outAnaDir; 
	die "FATAL: No handle given for ana distribution\n" unless $handleAna;
	`rm -fr $outConlDir; mkdir $outConlDir`;
	if ($MT) {$inReadme = "$docsDir/README-$MT.conll.txt"}
	else {$inReadme = "$docsDir/README.conll.txt"}
	&cp_readme($countryCode, $handleAna, $Version, $inReadme, "$outConlDir/00README.txt");
	`$scriptConls $outAnaDir $outConlDir`;
	&dirify($outConlDir);
    }
    if (($procAll and $procVert) or (!$procAll and $procVert == 1)) {
	print STDERR "INFO: ***Making $countryCode vert\n";
	die "FATAL: Can't find input ana dir $outAnaDir\n" unless -e $outAnaDir; 
	die "FATAL: No handle given for ana distribution\n" unless $handleAna;
	`rm -fr $outVertDir; mkdir $outVertDir`;
	if ($MT) {$inReadme = "$docsDir/README-$MT.vert.txt"}
	else {$inReadme = "$docsDir/README.vert.txt"}
	&cp_readme($countryCode, $handleAna, $Version, $inReadme, "$outVertDir/00README.txt");
	if (-e "$docsDir/$vertRegi") {`cp "$docsDir/$vertRegi" $outVertDir`}
	else {print STDERR "WARN: registry file $vertRegi not found\n"}
	`$scriptVerts $outAnaDir $outVertDir`;
	&dirify($outVertDir);
    }
}

# Substitute local with common taxonomies
sub commonTaxonomies {
    my $Dir = shift;
    foreach my $taxonomy (sort keys %taxonomy) {
	`cp $taxonomy{$taxonomy} $Dir/$taxonomy.xml`
    }
    return 1;
}

#Format XML file to be a bit nicer & smaller
sub polish {
    my $dir = shift;
    foreach my $file (glob("$dir/*.xml $dir/*/*.xml")) {
	`$scriptPolish < $file > $file.tmp`;
	rename("$file.tmp", $file); 
    }
}

#If a directory has more than $MAX files, store them in year directories
sub dirify {
    my $MAX = 1;  #In ParlaMint II we always put them in year directories
    my $inDir = shift;
    my @files = glob("$inDir/*");
    if (scalar @files > $MAX) {
	foreach my $file (@files) {
	    if (my ($year) = $file =~ m|ParlaMint-.+?_(\d\d\d\d)|) {
		my $newDir = "$inDir/$year";
		mkdir($newDir) unless -d $newDir;
		move($file, $newDir);
	    }
	}
    }
}

#Read in the appropriate $inFile README, change XX in it to country code, and output it $outFile
sub cp_readme {
    my $country = shift;
    my $handle  = shift;
    my $version = shift;
    my $inFile  = shift;
    my $outFile = shift;
    die "FATAL: No country for cp_readme\n" unless $country;
    die "FATAL: No handle for cp_readme\n" unless $handle;
    die "FATAL: No version for cp_readme\n" unless $version;
    open IN, '<:utf8', $inFile or die "FATAL: Can't open input README $inFile\n";
    open OUT,'>:utf8', $outFile or die "FATAL: Can't open output README $outFile\n";
    while (<IN>) {
	s/XX/$country/g;
	s/YY/$handle/g;
	s/ZZ/$version/g;
	print OUT
    }
    close IN;
    close OUT;
}
