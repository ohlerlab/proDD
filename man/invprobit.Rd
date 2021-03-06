% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/stats_functions.R
\name{invprobit}
\alias{invprobit}
\title{Inverse probit function}
\usage{
invprobit(x, rho, zeta, log = FALSE, oneminus = FALSE)
}
\arguments{
\item{x}{numeric vector}

\item{rho}{numeric vector of length 1 or the same length as x. Specifies
the inflection point of the inverse probit curve.}

\item{zeta}{numeric vector of length 1 or the same length as x. Specifies
the scale of the curve at the inflection point of the inverse probit curve.}

\item{log}{boolean if the log of the result is returned}

\item{oneminus}{boolean if one minus the result is returned}
}
\value{
a numeric vector of \code{length(x)}.
}
\description{
Calculate the values of the sigmoidal function that is defined by the
cumulative normal distribution function (\code{\link{pnorm}}). This
method provides a convient wrapper for the \code{pnorm} that automatically
handles negative zeta and is more consistent in its naming.
}
\examples{
 xg <- seq(-5, 5, length.out=101)
 plot(xg, invprobit(xg, rho=-2, zeta=-0.3))
}
