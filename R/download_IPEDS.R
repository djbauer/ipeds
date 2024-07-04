download_ipeds <- function(year = as.integer(format(Sys.Date(), '%Y')) - 1, 
                           dir = getIPEDSDownloadDirectory(), 
                           useProvisional = TRUE,
                           force = FALSE,
                           cleanup = FALSE,
                           timeout = 300,
                           ...) {
    if(length(year) > 1) {
        status <- TRUE
        for(i in year) {
            status <- status & download_ipeds(year = i, dir = dir, useProvisional = useProvisional, force = force, cleanup = cleanup, ...)
        }
        return(invisible(status))
    }
    
    dir <- paste0(dir, '/')
    year.str <- paste0((year - 1), '-', (sprintf("%02d", year %% 100)))
    
    file <- paste0('IPEDS_', year.str, '_Final.zip')
    url <- paste0(ipeds.base.url, file)
    if(!url_exists(url, ...)) {
        message(paste0('Final data not available for ', year.str))
        file <- paste0('IPEDS_', year.str, '_Provisional.zip')
        url <- paste0(ipeds.base.url, file)
        if(!url_exists(url, ...)) {
            stop(paste0(year.str, ' IPEDS database not available at: ', ipeds.download.page))
        } else if(!useProvisional) {
            stop(paste0('Final version of the ', year.str, ' IPEDS database is not available but the provisional is. Set useProvisional=TRUE to use.'))
        }
        warning(paste0('Downloading the provisional database for ', year.str, '.'))
    }
    
    dir.create(dir, showWarnings = FALSE, recursive = TRUE)
    dest <- paste(dir, file, sep="")
    
    if(!file.exists(dest) | force) {
        options(timeout = max(timeout, getOption("timeout")))
        download.file(url, dest, mode="wb")
    } else {
        message('Zip file already downloaded. Set force=TRUE to redownload.')
    }
    
    unzip(dest, exdir = paste0(substr(dest, 1, nchar(dest) - 4), "//"))
    
    accdb.file <- c(Sys.glob(paste0(substr(dest, 1, nchar(dest) - 4), "//*.accdb")), Sys.glob(paste0(substr(dest, 1, nchar(dest) - 4), "//*//*.accdb")))[1]
    if(!file.exists(accdb.file)) {
        stop(paste0('Problem loading MS Access database file.\nDownloaded file: ', dest, '\nFile not found: ', accdb.file))
    }
    
    if(.Platform$OS.type == 'windows') {
        # Windows based import of mdb files. Uses ODBC to connect. 
        tryCatch({
            # Characters in the file path that should be escaped before calling mdbtools
            escape_characters <- c(' ', '(', ')')
            for(i in escape_characters) {
                accdb.file <- gsub(i, paste0('\\', i), accdb.file, fixed = TRUE)
            }
            # Connection string
            con <- DBI::dbConnect(odbc::odbc(), .connection_string = paste0("Driver={Microsoft Access Driver (*.mdb, *.accdb)}; Dbq=", accdb.file, ";"))
            # List all tables, and remove system tables from list
            TableList <- DBI::dbListTables(con)
            TableList <- TableList[!grepl("MSys", TableList)]
            # Import all tables, and store in a list with name of table as list object name.
            db <- list()
            for(table in TableList) {
                db[[table]] <- DBI::dbGetQuery(con, paste0("SELECT * FROM [", table, "]"))
            }
            DBI::dbDisconnect(con)
            save(db, file = paste0(dir, 'IPEDS', year.str, '.Rda'))
        }, error = function(e) {
            message('Error loading the MS Access database file.')
            message('Use odbc::odbcListDataSources() to check for MS Access Database Driver.')
            message('If Missing, install from here: https://www.microsoft.com/en-us/download/details.aspx?id=54920')
            message('Architecture must match R version (64bit vs 32bit)')
            message(e)
        })
    } else {
        # *nix based version of MDB import
        # Need to have mdtools installed. From the terminal (on Mac): 
        # ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)" < /dev/null 2> /dev/null
        # brew install mdbtools
        tryCatch({
            # Characters in the file path that should be escaped before calling mdbtools
            escape_characters <- c(' ', '(', ')')
            for(i in escape_characters) {
                accdb.file <- gsub(i, paste0('\\', i), accdb.file, fixed = TRUE)
            }
            db <- Hmisc::mdb.get(accdb.file, stringsAsFactors = FALSE)
            save(db, file = paste0(dir, 'IPEDS', year.str, '.Rda'))
        }, error = function(e) {
            message('Error loading the MS Access database file. Make sure mdtools is installed.')
            if(Sys.info()['sysname'] == 'Darwin') {
                message('The following terminal commands will install mdtools on Mac systems:')
                message('ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)" < /dev/null 2> /dev/null')
                message('brew install mdbtools')
            }
            message('Original Error:')
            message(e)
        })
    }
    
    if(cleanup) {
        unlink(dest)
        unlink(accdb.file)
    }
    
    invisible(TRUE)
}
