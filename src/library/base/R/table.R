#  File src/library/base/R/table.R
#  Part of the R package, https://www.R-project.org
#
#  Copyright (C) 1995-2023 The R Core Team
#
#  This program is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  (at your option) any later version.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  A copy of the GNU General Public License is available at
#  https://www.R-project.org/Licenses/

table <- function (..., exclude = if (useNA=="no") c(NA, NaN),
                   useNA = c("no", "ifany", "always"),
		   dnn = list.names(...), deparse.level = 1)
{
    list.names <- function(...) {
	l <- as.list(substitute(list(...)))[-1L]
	if (length(l) == 1L && is.list(..1) && !is.null(nm <- names(..1)))
	    return(nm)
	nm <- names(l)
	fixup <- if (is.null(nm)) seq_along(l) else nm == ""
	dep <- vapply(l[fixup], function(x)
		      switch(deparse.level + 1,
			     "", ## 0
			     if (is.symbol(x)) as.character(x) else "", ## 1
			     deparse(x, nlines=1)[1L] ## 2
			     ),
		      "")
	if (is.null(nm))
	    dep
	else {
	    nm[fixup] <- dep
	    nm
	}
    }
    miss.use <- missing(useNA)
    miss.exc <- missing(exclude)
    ## useNA <- if (!miss.exc && is.null(exclude)) "always" (2.8.0 <= R <= 3.3.1)
    useNA <- if (miss.use && !miss.exc &&
		 !match(NA, exclude, nomatch=0L)) "ifany"
	     else match.arg(useNA)
    doNA <- useNA != "no"
    if(!miss.use && !miss.exc && doNA && match(NA, exclude, nomatch=0L))
	warning("'exclude' containing NA and 'useNA' != \"no\"' are a bit contradicting")
    args <- list(...)
    if (length(args) == 1L && is.list(args[[1L]])) { ## e.g. a data.frame
	args <- args[[1L]]
	if (length(dnn) != length(args))
	    dnn <- paste(dnn[1L], seq_along(args), sep = ".")
    }
    if (!length(args))
	stop("nothing to tabulate")
    # 0L, 1L, etc: keep 'bin' and 'pd' integer - as long as tabulate() requires it
    bin <- 0L
    lens <- NULL
    dims <- integer()
    pd <- 1L
    dn <- NULL
    for (a in args) { ## a is args[[ length(dims)+1 ]]
	if (is.null(lens)) lens <- length(a)
	else if (length(a) != lens)
	    stop("all arguments must have the same length")
        fact.a <- is.factor(a)
        ## The logic here is tricky in order to be sensible if
        ## both 'exclude' and 'useNA' are set.
        ##
	if(doNA) aNA <- anyNA(a) # *before* the following
        if(!fact.a) { ## factor(*, exclude=*) may generate NA levels where there were none!
            a0 <- a
            ## A non-null setting of 'exclude' sets the
            ## excluded levels to missing, which is different
            ## from the <NA> factor level, but these
            ## excluded levels must NOT EVER be tabulated.
            op <- options(warn = 2) ## prevent nonsensical factor() creation: turn warnings into errors
            on.exit(options(op))
            a <- # NB: this excludes first, unlike the is.factor() case
                factor(a, exclude = exclude)
            options(op)
        }

	## if(doNA)
        ##     a <- addNA(a, ifany = (useNA == "ifany"))
        ## Instead, do the addNA() manually and remember *if* we did :
        add.na <- doNA
        if(add.na) {
	    ifany <- (useNA == "ifany") # FALSE when "always"
	    anNAc <- anyNA(a) # sometimes, but not always == aNA above
	    add.na <- if (!ifany || anNAc) {
			  ll <- levels(a)
			  if(add.ll <- !anyNA(ll)) {
			      ll <- c(ll, NA)
			      ## FIXME? can we call  a <- factor(a, ...)
			      ##        only here,and be done?
			      TRUE
			  }
			  else if (!ifany && !anNAc)
			      FALSE
			  else
			      TRUE
		      }
		      else
			  FALSE
        } # else remains FALSE
	if(add.na) ## complete the "manual" addNA():
	    a <- factor(a, levels = ll, exclude = NULL)
	else
	    ll <- levels(a)
        a <- as.integer(a)
        if (fact.a && !miss.exc) { ## remove excluded levels
	    ll <- ll[keep <- which(match(ll, exclude, nomatch=0L) == 0L)]
	    a <- match(a, keep)
	} else if(!fact.a && add.na) {
	    ## remove NA level if it was added only for excluded in factor(a, exclude=.)
	    ## set those a[] to NA which correspond to excluded values,
	    ## but not those which correspond to NA-levels:
	    ## if(doNA) they must be counted,  possibly as 0,  e.g.,
	    ## for	table(1:3, exclude = 1) #-> useNA = "ifany"
	    ## or	table(1:3, exclude = 1, useNA = "always")
	    if(ifany && !aNA && add.ll) { # rm the NA-level again (why did we add it?)
		ll <- ll[!is.na(ll)]
		is.na(a) <- match(a0, c(exclude,NA), nomatch=0L) > 0L
	    } else { # e.g. !ifany :  useNA == "always"
		is.na(a) <- match(a0,   exclude,     nomatch=0L) > 0L
	    }
        }

	nl <- length(ll)
	dims <- c(dims, nl)
        if (prod(dims) > .Machine$integer.max)
            stop("attempt to make a table with >= 2^31 elements")
	dn <- c(dn, list(ll))
	## requiring   all(unique(a) == 1:nl)  :
	bin <- bin + pd * (a - 1L)
	pd <- pd * nl
    }
    names(dn) <- dnn
    bin <- bin[!is.na(bin)]
    if (length(bin)) bin <- bin + 1L # otherwise, that makes bin NA
    y <- array(tabulate(bin, pd), dims, dimnames = dn)
    class(y) <- "table"
    y
}


## NB: NA in dimnames should be printed.
print.table <-
function (x, digits = getOption("digits"), quote = FALSE, na.print = "",
	  zero.print = "0",
	  ## Numbers get right-justified by format(), irrespective of 'justify';
	  ## need to keep column headers aligned:
	  right = is.numeric(x) || is.complex(x),
	  justify = "none", ...)
{
    ## tables with empty extents have no contents and are hard to
    ## output in a readable way, so just say something descriptive and
    ## return.
    d <- dim(x)
    if (any(d == 0)) {
        cat ("< table of extent", paste(d, collapse=" x "), ">\n")
        return ( invisible(x) )
    }

    xx <- format(unclass(x), digits = digits, justify = justify)
    ## na.print handled here
    if(any(ina <- is.na(x)))
	xx[ina] <- na.print

    if(zero.print != "0" && any(i0 <- !ina & x == 0))
	## MM thinks this should be an option for many more print methods...
	xx[i0] <- zero.print ## keep it simple;  was sub(..., xx[i0])

    print(xx, quote = quote, right = right, ...)
    invisible(x)
}

summary.table <- function(object, ...)
{
    if(!inherits(object, "table"))
	stop(gettextf("'object' must inherit from class %s",
                      dQuote("table")),
             domain = NA)
    n.cases <- sum(object)
    n.vars <- length(dim(object))
    y <- list(n.vars = n.vars,
	      n.cases = n.cases)
    if(n.vars > 1) {
	m <- vector("list", length = n.vars)
	relFreqs <- object / n.cases
	for(k in 1L:n.vars)
	    m[[k]] <- apply(relFreqs, k, sum)
	expected <- apply(do.call("expand.grid", m), 1L, prod) * n.cases
	statistic <- sum((c(object) - expected)^2 / expected)
	lm <- lengths(m)
	parameter <- prod(lm) - 1L - sum(lm - 1L)
	y <- c(y, list(statistic = statistic,
		       parameter = parameter,
		       approx.ok = all(expected >= 5),
		       p.value = stats::pchisq(statistic, parameter, lower.tail=FALSE),
		       call = attr(object, "call")))
    }
    class(y) <- "summary.table"
    y
}

print.summary.table <-
function(x, digits = max(1L, getOption("digits") - 3L), ...)
{
    if(!inherits(x, "summary.table"))
	stop(gettextf("'x' must inherit from class %s",
                      dQuote("summary.table")),
             domain = NA)
    if(!is.null(x$call)) {
	cat("Call: "); print(x$call)
    }
    cat("Number of cases in table:", x$n.cases, "\n")
    cat("Number of factors:", x$n.vars, "\n")
    if(x$n.vars > 1) {
	cat("Test for independence of all factors:\n")
	ch <- x$statistic
	cat("\tChisq = ",	format(round(ch, max(0, digits - log10(ch)))),
	    ", df = ",		x$parameter,
	    ", p-value = ",	format.pval(x$p.value, digits, eps = 0),
	    "\n", sep = "")
	if(!x$approx.ok)
	    cat("\tChi-squared approximation may be incorrect\n")
    }
    invisible(x)
}

as.data.frame.table <-
    function(x, row.names = NULL, ..., responseName = "Freq",
             stringsAsFactors = TRUE, sep="", base = list(LETTERS))
{
    ex <- quote(data.frame(do.call("expand.grid",
				   c(dimnames(provideDimnames(x, sep=sep, base=base)),
				     KEEP.OUT.ATTRS = FALSE,
                                     stringsAsFactors = stringsAsFactors)),
                           Freq = c(x),
                           row.names = row.names))
    names(ex)[3L] <- responseName
    eval(ex)
}

is.table <- function(x) inherits(x, "table")
as.table <- function(x, ...) UseMethod("as.table")
as.table.default <- function(x, ...)
{
    if(is.table(x)) return(x)
    else if(is.array(x) || is.numeric(x)) {
	x <- as.array(x)
	structure(class = c("table", oldClass(x)), provideDimnames(x))
    } else stop("cannot coerce to a table")
}

marginSums <- function (x, margin = NULL)
{
   if (!is.array(x))
      if (is.numeric(x)) dim(x) <- length(x)
      else stop("'x' is not an array")


   if (length(margin)) {
      z <- apply(x, margin, sum)
      ## apply() may lose dims, in which case we need to put them
      ## back. It is probably only strictly necessary if margin
      ## has length 1. Need to convert margin to numeric for this
      ## to work, but can assume that x has named dimnames in that
      ## case (or apply() would have complained.
      if (! is.array(z))
      {
        if (is.character(margin))
            margin <- match(margin, names(dimnames(x)))
        dim(z) <- dim(x)[margin]
        dimnames(z) <- dimnames(x)[margin]
      }
      class(z) <- oldClass(x)
      z
   }
   else sum(x)
}

proportions <- function (x, margin = NULL)
{
    if (length(margin))
        sweep(x, margin, marginSums(x, margin), `/`, check.margin = FALSE)
    else x/sum(x)
}

prop.table <- proportions
margin.table <- marginSums

## prop.table <- function(x, margin = NULL)
## {
## ###    .Deprecated("proportions")
##     if(length(margin))
## 	sweep(x, margin, margin.table(x, margin), "/", check.margin=FALSE)
##     else
## 	x / sum(x)
## }

## margin.table <- function(x, margin = NULL)
## {
## ###    .Deprecated("marginSums")
##     if(!is.array(x)) stop("'x' is not an array")
##     if (length(margin)) {
## 	z <- apply(x, margin, sum)
## 	dim(z) <- dim(x)[margin]
## 	dimnames(z) <- dimnames(x)[margin]
##     }
##     else return(sum(x))
##     class(z) <- oldClass(x) # avoid adding "matrix"
##     z
## }

`[.table` <-
function(x, i, j, ..., drop = TRUE)
{
    ret <- NextMethod()
    ldr <- length(dim(ret))
    if((ldr > 1L) || (ldr == length(dim(x))))
        class(ret) <- "table"
    ret
}
