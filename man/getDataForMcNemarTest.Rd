% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/cert.R
\name{getDataForMcNemarTest}
\alias{getDataForMcNemarTest}
\title{Get result data set of Cert for McNemar's test}
\usage{
getDataForMcNemarTest(connectionDetails)
}
\arguments{
\item{connectionDetails}{connectionDetails information
generated by DatabaseConnector::createConnectionDetails function}
}
\value{
A data frame from summary table
generated by subsetting summary data set
}
\description{
It is necessary for run a McNemar's test
}

