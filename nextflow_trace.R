###### entry point method #########
generate_index_and_run_trace = function( root_directory, entry_point, entry_file, output_file, function_index=NA ){
  
  if ( !is.list(function_index) ) {
    cat("Generating INDEX from nextflow files in: ", root_directory, "\n")
    function_index <- generate_nf_index(root_directory)
    cat("INDEXING completed\n\n")
  } else {
    cat("Using previously created function index.\n\n")
  }
  
  cat("Running TRACE from : ", entry_point, " in ", entry_file, "\n\n")
  trace <- trace_nf_path( entry_file, entry_point, function_index=function_index)
  
  trace %<>% format_trace_for_output()
  output_file <- file(file.path(root_directory, output_filename))
  writeLines(trace, output_file)
  close(output_file)
  
  cat("\nTRACE completed, saved to ", file.path(root_directory, output_filename))
  
  return(list(function_index=function_index, trace=trace))
}

#######  supporting methods #########

#######
# trace the path from a given starting point ( workflow or process )
# through each workflow/process called
trace_nf_path <- function( init_file, init_workflow="main", function_index ){
  output_lines <- c()
  this_filename <- strsplit(init_file, "/") %>% {.[[1]][length(.[[1]])]}
  qualified_name <- paste(
    this_filename,
    init_workflow, 
    sep="__" )
  output_lines <- print_this_step( qualified_name, function_index )
  return(output_lines)
}

print_this_step <- function( qualified_name, function_index, level=1, internal_call=NA ){
  cat(rep("  ", (level-1)), 
      (strsplit(qualified_name, "__")[[1]] 
       %>% {paste(.[2], "(", .[1], ")")}), 
         "\n")
#  print(paste("checking ", qualified_name, internal_call))
  if ( !qualified_name %in% names(function_index) ) stop( "Fully qualified workflow/process ", qualified_name, " does not exist in index provided." )
  wfop_object <- function_index[[qualified_name]]
  my_callstack <- paste(wfop_object$file, wfop_object$class, ifelse( is.na(internal_call) | internal_call==wfop_object$name, " ", internal_call ), sep="\t")
  if ( level > 1 ) {
#      print(paste("1", my_callstack, sep=" :: "))
      my_callstack %<>% paste(., paste(rep(" ", level-1), collapse="\t"), sep="\t")
#      print(paste("2", my_callstack, sep=" :: "))
  }
  my_callstack %<>% paste(wfop_object$name, sep="\t")
  
  if ( length(wfop_object$calls) ){
    for( this_subcall in wfop_object$calls ){
      my_callstack %<>% c( print_this_step( this_subcall$qualified_name, function_index, level+1, this_subcall$internal_name ) )
    }
  }
  return(my_callstack)
}

format_trace_for_output <- function( trace ){
  #determine max number of columns in trace
  num_columns <- mapply(function(x){
    return(length(strsplit(x, "\t")[[1]]))
  }, trace) %>% max()
  #add appropriate empty cells to end of each line
  trace %<>% mapply( function( line ){
    line %<>% {strsplit(., split="\t")[[1]]} %>%
      {c(.,rep(" ", num_columns - length(.)))} %>%
      paste(collapse="\t")
    return(line)
  }, .)
  #add column headers
  trace %<>% c(paste("FILE", "ACTION", "INTERNAL_NAME", "BASE_METHOD", paste("LEVEL", 1:(num_columns-4), collapse="\t", sep="_"), sep="\t"), .)
  return(trace)
}

###########  
# check all .nf files in the directory sent and all subdirectories
# create index of all workflows/processes with callstacks for 
# workflows and processes invoked by each workflow
generate_nf_index <- function( my_directory ){
  
  nf_files <- dir(my_directory, pattern="*\\.nf", recursive=T, full.names=TRUE)# %>% .[grep(".nf$", .)]

  if ( length(nf_files) == 0 ) 
    stop("The directory sent doesn't have any .nf files to process.")
  
  #confirm no duplicate filenames
  names_only <- nf_files %>% gsub("^[a-zA-Z_0-9]+/", "", .)
  if ( length(names_only) != length(unique(names_only)) )
    stop("The following filenames are duplicated ... sorry, this script won't work properly::\n", nf_files[duplicated(names_only)])
  
  #generate index of all nf functions ( processes and workflows )
  
  function_list <- list()
  for ( nf_file in nf_files ){
    cat(paste("Indexing", nf_file), "\n")
    split_path <- strsplit(nf_file, "/")[[1]]
    processing_filename <- split_path[ length(split_path) ]
    namespace <- ifelse( length(split_path) > 1, split_path[length(split_path)-1], NA )
    fl <- file(nf_file)
    fl_lines <- readLines( fl )
    close(fl)
    includes <- list()
    for ( line in fl_lines ) {
      line <- trimws(line, which="left")
      
      # check for include statment
      include <- check_for_include(line)
      if ( all(include != FALSE) ) {
        includes[ include[1] ] <- include[2]
        next
      }
      # check for process or workflow
      process <- check_for_process_or_workflow(line, processing_filename)
      if ( is.list(process) ) {
        qualified_process <- paste( process$file, process$name, sep="__" )
        if( qualified_process %in% names(function_list) ){
          warning("process :: ", processing_filename, "::", process, " exists in another namespace ( from ", function_list[[qualified_process]]$file, " )")
        } else {
          function_list[[ qualified_process ]] <- process
        }
        next
      }
      
      # check for call to process or workflow, push onto call stack for the current workflow/process
      call <- check_for_call( line, includes, processing_filename )
      if ( is.list( call ) ) {
        function_list[[ length(function_list) ]]$calls %<>% append(list(call))
        next
      }
      
    }
  }
  return(function_list)
}
#now


check_for_include = function( line ){
  include <- grep("^include", line, value=TRUE)
  if ( length(include) ) {
    name <- gsub("^include[ ]*\\{[ ]*", "", include) %>% gsub("[ ]*\\}.*$", "", .)
    #may need to handle "AS" here
    name_qualifier <- strsplit(name, "[ ]+(AS|as)[ ]+")[[1]]
    actual_name <- name_qualifier[1]
    internal_name <- ifelse(length(name_qualifier) > 1, name_qualifier[2], actual_name)
    include_filename <- strsplit(include, "/") %>% {.[[1]][length(.[[1]])]} %>% gsub("('|\")", "", .)
    return( c(internal_name, paste(include_filename, actual_name, sep="__") ) )
  } else {
    return(FALSE)
  }
}

check_for_process_or_workflow = function( line, processing_filename ){
  process <- grep("^(process|workflow) [a-zA-Z0-9_]*[ ]?\\{", line, value=TRUE)
  if ( length(process) ) {
    f_class <- ifelse( grepl("^process", process), "process", "workflow" )
    process %<>% gsub("^(process|workflow)[ ]+", "", .) %>% 
      gsub("[ ]*\\{.*", "", .)
    if( process == "" ) process = "main"
    return(list(class=f_class, name=process, file=processing_filename, calls=list()))
  }
  return(FALSE)
}

check_for_call = function( line, includes, processing_filename ){
  call <- grep("^[A-Za-z0-9_]+[ ]*\\(", line, value=TRUE)
  if ( length(call) ) {
    call_name <- gsub( "[ ]*\\(.*$", "", call )
    #there are a few calls that we might catch which aren't actually calls - exclude them here ...
    if( call_name %in% c("path", "val", "tuple", "if") ) return(FALSE)
    # find this call in includes, or if not there, append current filename since we know it must be in this namespace
    qualified_name <- ifelse( call_name %in% names(includes), includes[[ call_name ]], paste( processing_filename, call_name, sep="__") )
    return( list( internal_name=call_name, qualified_name=qualified_name ) )
  }
  return(FALSE)
}


########### functional code - at the end so it can be run from command line and have all methods pre-created #########
library(magrittr)

####### init variables #########

root_directory <- getwd()
entry_file <- "lens.nf"
entry_point <- "manifest_to_lens" #use main to enter in the "default" or unnamed workflow in entry_file, otherwise use name of workflow
nf_index <- NA
run_stats <- FALSE

####### override defaults with command line arguments if any were sent ########
args = commandArgs(trailingOnly=TRUE)

if (length(args) > 0) {
  root_directory <- args[1]
  #check directory exists
  if ( !dir.exists(root_directory) ) {
    stop( "The directory sent does not appear to exist." )
  }
  if (length(args) >= 3) {
    entry_file <- args[2]
    entry_point <- args[3]
  }
}

output_filename <- paste("trace",paste0(entry_point, ".tsv"), sep="_" )

index_rds_path <- file.path(root_directory, "nf_index.RDS")

if ( file.exists( index_rds_path ) ) nf_index <- readRDS(index_rds_path)

fi <- generate_index_and_run_trace( root_directory, entry_point, entry_file, output_file, function_index = nf_index )

# optionally save index to disk
saveRDS(fi$function_index, index_rds_path)

# optionally run stats on the trace results
if ( run_stats ) {
  trace_df <- read.table(file.path(root_directory, output_filename), sep="\t", header = TRUE)
  length(unique(trace_df$LEVEL_1))
  length(trace_df$LEVEL_1[trace_df$LEVEL_1 != " "])
}

