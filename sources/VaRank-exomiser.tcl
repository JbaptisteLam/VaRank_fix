############################################################################################################
# VaRank 1.5                                                                                               #
#                                                                                                          #
# VaRank: a simple and powerful tool for ranking genetic variants                                          #
#                                                                                                          #
# Copyright (C) 2016-2021 Veronique Geoffroy (veronique.geoffroy@inserm.fr)                                #
#                         Jean Muller (jeanmuller@unistra.fr)                                              #
#                                                                                                          #
# Please cite the following article:                                                                       #
# Geoffroy V.*, Pizot C.*, Redin C., Piton A., Vasli N., Stoetzel C., Blavier A., Laporte J. and Muller J. #
# VaRank: a simple and powerful tool for ranking genetic variants.                                         #
# PeerJ. 2015 (10.7717/peerj.796)                                                                          #
#                                                                                                          #
# This is part of VaRank source code.                                                                      #
#                                                                                                          #
# This program is free software; you can redistribute it and/or                                            #
# modify it under the terms of the GNU General Public License                                              #
# as published by the Free Software Foundation; either version 3                                           #
# of the License, or (at your option) any later version.                                                   #
#                                                                                                          #
# This program is distributed in the hope that it will be useful,                                          #
# but WITHOUT ANY WARRANTY; without even the implied warranty of                                           #
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the                                            #
# GNU General Public License for more details.                                                             #
#                                                                                                          #
# You should have received a copy of the GNU General Public License                                        #
# along with this program; If not, see <http://www.gnu.org/licenses/>.                                     #
############################################################################################################


# Start the REST service for Exomiser
# OUTPUT = pid of the command (or "" if the service has not been successfully started)
proc startTheRESTservice {applicationPropertiesTmpFile port exomiserStartServiceFile} {

    global g_VaRank

    regsub "sources" $g_VaRank(sourcesDir) "jar" jarDir
    set jarFile "$jarDir/exomiser-rest-prioritiser-12.1.0.jar"

    # Run the service

    if {[catch {set idService [eval exec java -Xmx4g -jar $jarFile --server.port=$port --spring.config.location=$applicationPropertiesTmpFile >& $exomiserStartServiceFile &]} Message]} {
	puts "\nWARNING: No Exomiser annotations available."
	puts "The REST service has not been started successfully:"
	puts "java -Xmx4g -jar $jarFile --server.port=$port --spring.config.location=$applicationPropertiesTmpFile >& $exomiserStartServiceFile"
	puts "$Message"
	set g_VaRank(hpo) ""
	file delete -force $exomiserStartServiceFile
	set idService ""
    } else {
	# Wait (max 5 minutes) for the start
	set waiting 1
	set i 1
	while {$waiting} {
	    after 6000 ; # 6s
	    if {[catch {set s [socket localhost $port]} Message]} { 
		# The REST service is not started yet, we have the following error message: "couldn't open socket: connection refused"
		incr i
		if {$i eq 50} { ;# 50 x 6s = 5 min
		    set waiting 0
		}
	    } else {
		# The REST service has successfully started
		close $s
		set waiting 0
	    }
	    if {[file exists $exomiserStartServiceFile]} {
		if {[regexp "APPLICATION FAILED TO START|Application run failed" [ContentFromFile $exomiserStartServiceFile]]} {
		    # The REST service failed to start
		    set i 50
		    set waiting 0
		}
		foreach L [LinesFromFile $exomiserStartServiceFile] {
		    if {[regexp "^ERROR" $L]} {
			puts $L
			set i 50
			set waiting 0
		    }
		}
	    } 
	}
	
	if {$i eq 50} {
	    # if the REST service has not started after 10 minutes
	    puts "\nWARNING: No Exomiser annotations available."
	    puts "The REST service has not been started successfully:"
	    puts "java -Xmx4g -jar $jarFile --server.port=$port --spring.config.location=$applicationPropertiesTmpFile >& $exomiserStartServiceFile"
	    puts "(see $exomiserStartServiceFile)"
	    set g_VaRank(hpo) ""
	    set idService ""
	} else {
	    # The REST service has been successfully started
	    puts "\t...idService = $idService"
	}
    }
    return $idService
}


## - Check if the exomiser installation is ok
proc checkExomiserInstallation {L_Genes} {

    global g_VaRank
    global hpoVersion
    
    puts "...running Exomiser on [llength $L_Genes] gene names ([clock format [clock seconds] -format "%B %d %Y - %H:%M"])"

    ## Checked if the NCBIgeneID file exists
    regsub "sources" $g_VaRank(sourcesDir) "ExtAnn" extannDir
    if {![file exists "$extannDir/results.txt"]} {
	puts "\nWARNING: No Exomiser annotations available."
	puts "...$extannDir/results.txt doesn't exist"
	set g_VaRank(hpo) ""
	return
    }
    
    ## Checked if the Exomiser annotation data files exist
    ## Download it if needed
    regsub "sources" $g_VaRank(sourcesDir) "Annotations_Exomiser" exomiserDir
    if {![file exists $exomiserDir/2007]} {
	puts "...downloading Exomiser supporting data files"
	puts "   (done only once during the first Exomiser annotation)"
	if {[catch {eval exec $g_VaRank(sourcesDir)/../bash/downloadExomiserAnnotation.bash} Message]} {
	    puts $Message
	}
    }

    set L_hpoDir [glob -nocomplain $exomiserDir/*]
    set L_hpoDir_ok {}
    foreach hpoDir $L_hpoDir {
	if {[regexp "^(\[0-9\]+)$" [file tail $hpoDir] match hpoDir]} {
	    lappend L_hpoDir_ok $hpoDir
	}
    }
    if {$L_hpoDir_ok ne ""} {
	set hpoVersion [lindex [lsort -integer $L_hpoDir_ok] end]
	if {$g_VaRank(hpo) ne ""} {
	    ## HPO citation
	    puts "\tINFO: VaRank takes use of Exomiser (Smedley et al., 2015) for the phenotype-driven analysis."
	    puts "\tINFO: VaRank is using the Human Phenotype Ontology (version $hpoVersion). Find out more at http://www.human-phenotype-ontology.org"
	}
    } else {
	puts "\nWARNING: No Exomiser annotations available in $exomiserDir/\n"
	set g_VaRank(hpo) ""
    } 
    
    return
}


proc searchforGeneID {geneName} {

    global g_VaRank
    global geneID

    if {![array exists geneID]} {

	regsub "sources" $g_VaRank(sourcesDir) "ExtAnn" extannDir
	# "$extannDir/results.txt" header:
	# "Approved symbol" "NCBI gene ID"    "Previous symbol" "Alias symbol"
	# A1BG    1 
	# A1BG-AS1        503538  NCRNA00181      FLJ23569
	foreach L [LinesFromFile "$extannDir/results.txt"] {
	    set Ls [split $L "\t"]
	    if {[regexp "Approved symbol" $L]} {
		set i_approuved [lsearch -exact $Ls "Approved symbol"]
		set i_ncbi [lsearch -exact $Ls "NCBI gene ID"]
		set i_previous [lsearch -exact $Ls "Previous symbol"]
		set i_alias [lsearch -exact $Ls "Alias symbol"]
		continue
	    }
	    set Approved_symbol [lindex $Ls $i_approuved]
	    set NCBI_gene_ID [lindex $Ls $i_ncbi]
	    if {[regexp "\\\[" $NCBI_gene_ID]} { ;# some lines have bad "NCBI_gene_ID" : "CYP4F30P   4F-se9[6:7:8]   C2orf14   100132708"
		continue
	    }
	    set Previous_symbol [lindex $Ls $i_previous]
	    set Alias_symbol [lindex $Ls $i_alias]
	    
	    set geneID($Approved_symbol) $NCBI_gene_ID
	    set geneID($Previous_symbol) $NCBI_gene_ID
	    set geneID($Alias_symbol) $NCBI_gene_ID
	}
    }

    if {![info exists geneID($geneName)]} {
	set geneID($geneName) ""
    }

    return $geneID($geneName)
}


proc searchForAllGenesContainingVariants {} {

    global g_VaRank
    global g_ANNOTATION

    puts "...listing of all the genes overlapped with a variant"
    set i_gene [lsearch -regexp [split $g_ANNOTATION(#id) "\t"] "^gene"]
    if {$i_gene eq -1} {
	puts "\twarning: column name \"gene\" not found in annotations. Exit."
	exit
    }

    set L_allGenes ""
    foreach id [array names g_ANNOTATION] {
	if {$id eq "#id"} {continue}
	foreach ann "$g_ANNOTATION($id)" {
	    set gene [lindex [split $ann "\t"] $i_gene]
	    foreach g [split $gene "/"] {
		regsub -all "{|}" $g "" g
		lappend L_allGenes $g
	    }
	}
    }
    set L_allGenes [lsort -unique $L_allGenes]
    puts "\t([llength $L_allGenes] genes)"

    return $L_allGenes
}


# Creation of the g_Exomiser variable:
# g_Exomiser($geneName) = EXOMISER_GENE_PHENO_SCORE\tHUMAN_PHENO_EVIDENCE\tMOUSE_PHENO_EVIDENCE\tFISH_PHENO_EVIDENCE
# default = "\t-1.0\t\t\t"
# INPUTS:
# L_genes: e.g. "FGFR2"
# L_HPO:   e.g. "HP:0001156,HP:0001363,HP:0011304,HP:0010055"
proc runExomiser {L_Genes L_HPO} {
    
    global g_VaRank
    global hpoVersion
    global g_Exomiser

    if {$g_VaRank(hpo) eq ""} {return}

    regsub "sources" $g_VaRank(sourcesDir) "Annotations_Exomiser" exomiserDir
    regsub "sources" $g_VaRank(sourcesDir) "bash" bashDir
    regsub "sources" $g_VaRank(sourcesDir) "etc"  etcDir

    # Tcl 8.5 is required for use of the json package.
    package require http
    package require json 1.3.3
    
    # Creation of the temporary "application.properties" file
    if {[catch {set port [exec bash $bashDir/searchForAFreePortNumber.bash]} Message]} {
	puts "$Message"
	puts "WARNING: port is defined to 50000"
	set port 50000
    }
    puts "\t...on port $port"

    set applicationPropertiesTmpFile "$g_VaRank(vcfDir)/[clock format [clock seconds] -format "%Y%m%d-%H%M%S"]_exomiser_application.properties"
    set infos [ContentFromFile $etcDir/application.properties]
    regsub "XXXX" $infos "$port" infos
    regsub "YYYY" $infos "$exomiserDir/$hpoVersion" infos
    WriteTextInFile $infos $applicationPropertiesTmpFile
    # Start the REST service
    set exomiserStartServiceFile "$g_VaRank(vcfDir)/[clock format [clock seconds] -format "%Y%m%d-%H%M%S"]_exomiser.tmp"
    puts "\t...starting the REST service"
    set idService [startTheRESTservice $applicationPropertiesTmpFile $port $exomiserStartServiceFile]
    if {$idService ne ""} {
	# Requests
	foreach geneName $L_Genes {
	    
	    # Search the geneID of the geneName
	    set geneID [searchforGeneID $geneName]

	    # Check if the information exists
	    if {$geneID eq ""} {continue}
	    
	    # Exomiser request
	    set url "http://localhost:${port}/exomiser/api/prioritise/?phenotypes=${L_HPO}&prioritiser=hiphive&prioritiser-params=human,mouse,fish,ppi&genes=$geneID"

	    if {[catch {
		set token [::http::geturl $url]
		set exomiserResult [::http::data $token]
		::http::cleanup $token
		set d_all [::json::json2dict $exomiserResult]
	    } Message]} {
		puts "geneName: $geneName"
		puts "$Message\n"
		puts "$url"
		continue
	    }
	    
	    # The exomiser http request can be used for x genes -> in this case, it returns in the results a list of dictionary, 1 for each gene
	    # If the http request is only for 1 gene, the result is a list of 1 dict.
	    # => We use only the first element of the results, which is a dict (a list of key-value)
	    if {[catch {set d_results [lindex [dict get $d_all "results"] 0]} Message]} {
		continue
	    }
	    # dict for {theKey theValue} $d_results {
	    #    puts "$theKey -> $theValue\n"
	    # }	    
	    
	    if {[catch {set EXOMISER_GENE_PHENO_SCORE [dict get $d_results "score"]} Message]} {
		continue
	    }
	    set EXOMISER_GENE_PHENO_SCORE [format "%.4f" $EXOMISER_GENE_PHENO_SCORE]
	    
	    if {[catch {set d_phenotypeEvidence [dict get $d_results "phenotypeEvidence"]} Message]} {
		continue
	    }
	    # -> return a list of dictionary, 1 for each organism:
	    # puts [llength $d_phenotypeEvidence] ; # = 2 (HUMAN + MOUSE)
	    
	    #dict for {theKey theValue} [lindex $d_phenotypeEvidence 0] {
	    #    puts "$theKey -> $theValue\n"
	    #}

	    # score -> 0.8790527581872061
	    #
	    # model -> organism HUMAN entrezGeneId 2263 humanGeneSymbol FGFR2 diseaseId OMIM:101600 diseaseTerm {Craniofacial-skeletal-dermatologic dysplasia} phenotypeIds {HP:0000494 HP:0005347 HP:0000452 HP:0003041 HP:0005280 HP:0011304 HP:0000006 HP:0000303 HP:0002308 HP:0006101 HP:0000327 HP:0000586 HP:0000244 HP:0000486 HP:0003795 HP:0002780 HP:0004440 HP:0003196 HP:0003070 HP:0010055 HP:0000238 HP:0000678 HP:0006110 HP:0001249 HP:0000218 HP:0000316 HP:0000453 HP:0002676} id OMIM:101600_2263
	    #
	    # bestModelPhenotypeMatches -> {query {id HP:0001156 label Brachydactyly} match {id HP:0006101 label {Finger syndactyly}} lcs {id MP:0002110 label {}} ic 2.6619180857144342 simj 0.64 score 1.3052308511743194} {query {id HP:0001363 label Craniosynostosis} match {id HP:0004440 label {Coronal craniosynostosis}} lcs {id HP:0001363 label Craniosynostosis} ic 5.851950660605321 simj 0.9411764705882353 score 2.3468528434490747} {query {id HP:0010055 label {Broad hallux}} match {id HP:0010055 label {Broad hallux}} lcs {id HP:0010055 label {Broad hallux}} ic 7.8438437682151125 simj 1.0 score 2.800686303072001} {query {id HP:0011304 label {Broad thumb}} match {id HP:0011304 label {Broad thumb}} lcs {id HP:0011304 label {Broad thumb}} ic 6.728560751270146 simj 1.0 score 2.5939469445750323}
	    set HUMAN_PHENO_EVIDENCE {}
	    set MOUSE_PHENO_EVIDENCE {}
	    set FISH_PHENO_EVIDENCE  {}
	    foreach d_organism $d_phenotypeEvidence {
		if {[catch {set actualOrganism [dict get $d_organism model organism]} Message]} {
		    continue
		} else {
		    catch {lappend ${actualOrganism}_PHENO_EVIDENCE [dict get $d_organism model diseaseTerm]} Message
		    if {[catch {set L_best [dict get $d_organism bestModelPhenotypeMatches]} Message]} {
			continue
		    } else {
			foreach d_query $L_best {
			    catch {lappend ${actualOrganism}_PHENO_EVIDENCE  [dict get $d_query query label]} Message
			    catch {lappend ${actualOrganism}_PHENO_EVIDENCE  [dict get $d_query match label]} Message
			}
		    }
		}
	    }
	    set HUMAN_PHENO_EVIDENCE [lsort -unique $HUMAN_PHENO_EVIDENCE]; if {$HUMAN_PHENO_EVIDENCE eq ""} {set HUMAN_PHENO_EVIDENCE "NA"}
	    set MOUSE_PHENO_EVIDENCE [lsort -unique $MOUSE_PHENO_EVIDENCE]; if {$MOUSE_PHENO_EVIDENCE eq ""} {set MOUSE_PHENO_EVIDENCE "NA"}
	    set FISH_PHENO_EVIDENCE  [lsort -unique $FISH_PHENO_EVIDENCE]; if {$FISH_PHENO_EVIDENCE eq ""} {set FISH_PHENO_EVIDENCE "NA"}
	    
	    set g_Exomiser($geneName) "$EXOMISER_GENE_PHENO_SCORE\t[join $HUMAN_PHENO_EVIDENCE ";"]\t[join $MOUSE_PHENO_EVIDENCE ";"]\t[join $FISH_PHENO_EVIDENCE ";"]"

	}
	
	# End the REST service
        if {[catch {exec kill -9 $idService} Message]} {
            puts "End the REST service:"
            puts $Message
        }

	file delete -force $exomiserStartServiceFile
    }
    
    # Remove tmp files
    file delete -force $applicationPropertiesTmpFile
    
    return ""
}


# g_Exomiser($geneName) = EXOMISER_GENE_PHENO_SCORE\tHUMAN_PHENO_EVIDENCE\tMOUSE_PHENO_EVIDENCE\tFISH_PHENO_EVIDENCE
# Return either only the score or all the annotation:
# what = "score" or "all"
proc ExomiserAnnotation {GeneName what} {
    
    global g_Exomiser

    if {$what eq "all"} {
	# Return all the annotation (EXOMISER_GENE_PHENO_SCORE HUMAN_PHENO_EVIDENCE MOUSE_PHENO_EVIDENCE FISH_PHENO_EVIDENCE) => for gene annotations
	if {[info exists g_Exomiser($GeneName)]} {
	    return $g_Exomiser($GeneName)
	} else {
	    return "-1.0\tNA\tNA\tNA"
	}
    } elseif {$what eq "score"} {
	# Return only the score (EXOMISER_GENE_PHENO_SCORE) => for regulatory elements annotations
	if {[info exists g_Exomiser($GeneName)]} {
	    return [lindex [split $g_Exomiser($GeneName) "\t"] 0]
	} else {
	    return "-1.0"
	}
	
    } else {
	puts "proc ExomiserAnnotation: Bad option value for \"what\" ($what)"
    }
}
